"""文字模式：抓取一版的全部文章，转成 blocks 并缓存。

设计要点：
- 图片下载到本地缓存；blocks 里 `src` 保留原址、`local` 是本地路径；
- 整页结果写 JSON 缓存，二次打开 0 请求；
- 全程走 HttpClient，天然受 1 req/s 限速约束。
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Callable
from datetime import date as Date
from typing import Any

from ..core.errors import EngineError
from ..core.models import Article, Block, BlockType, Page, PageKind
from ..core.paths import LibraryPaths, layout_url
from ..net.client import HttpClient
from ..site.article import parse_article
from ..site.parser import parse_page_detail
from ..store.repo import Repo
from .classify import classify

Emitter = Callable[[str, dict], None]


class ArticleService:
    def __init__(
        self,
        http: HttpClient,
        repo: Repo,
        paths: LibraryPaths,
        *,
        emit: Emitter | None = None,
    ) -> None:
        self.http = http
        self.repo = repo
        self.paths = paths
        self.emit = emit or (lambda _event, _data: None)

    def fetch_page(self, d: Date, page_no: int, *, refresh: bool = False) -> dict[str, Any]:
        cache_file = self.paths.text_json(d, page_no)
        if cache_file.exists() and not refresh:
            try:
                return json.loads(cache_file.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                cache_file.unlink(missing_ok=True)  # 缓存坏了就重抓

        page = self._page_detail(d, page_no)
        total = len(page.articles)
        articles: list[Article] = []
        failed = 0

        for index, ref in enumerate(page.articles, start=1):
            try:
                html = self.http.get_text(ref.url)
                article = parse_article(html, ref.url)
                article.blocks = [self._localise(block) for block in article.blocks]
                articles.append(article)
            except EngineError:
                failed += 1
            self.emit(
                "article.progress",
                {
                    "date": d.isoformat(),
                    "pageNo": page_no,
                    "done": index,
                    "total": total,
                },
            )

        kind = PageKind.FAILED if (failed and not articles) else classify(articles)
        payload = {
            "date": d.isoformat(),
            "pageNo": page_no,
            "title": page.title,
            "kind": kind.value,
            "articles": [article.dump() for article in articles],
        }

        if articles:
            cache_file.parent.mkdir(parents=True, exist_ok=True)
            tmp = cache_file.with_name(cache_file.name + ".tmp")
            tmp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            tmp.replace(cache_file)

        return payload

    # ------------------------------------------------------------------ #

    def _page_detail(self, d: Date, page_no: int) -> Page:
        """抓该版页面拿文章列表；标题可用库里的记录兜底。"""
        node_url = layout_url(d).replace("node_01.html", f"node_{page_no:02d}.html")
        html = self.http.get_text(node_url)
        page = parse_page_detail(html, node_url, no=page_no)

        if not page.title:
            record = self.repo.get_page(d, page_no)
            if record and record["title"]:
                page.title = record["title"]
        return page

    def _localise(self, block: Block) -> Block:
        if block.type != BlockType.IMAGE or not block.src:
            return block
        try:
            data = self.http.get_bytes(block.src)
            digest = hashlib.sha1(block.src.encode("utf-8")).hexdigest()[:16]
            target = self.paths.image_cache(digest + _suffix(block.src))
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists():
                target.write_bytes(data)
            block.local = str(target)
        except EngineError:
            block.local = None  # 单张图挂掉不影响正文
        return block


def _suffix(url: str) -> str:
    lowered = url.lower()
    for ext in (".jpg", ".jpeg", ".png", ".webp"):
        if lowered.endswith(ext):
            return ext
    return ".jpg"
