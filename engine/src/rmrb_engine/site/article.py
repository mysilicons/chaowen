"""正文页解析（/rmrb/pc/content/{YYYYMM}/{DD}/content_{id}.html）。

正文有两种信息来源，互为补充：
1. 结构化元数据藏在 HTML 注释 `<!--enpproperty … -->` 里（author/subtitle/id），比 DOM 稳；
2. 正文主体在 `<!--enpcontent--> … <!--/enpcontent-->` 之间，按出现顺序转成有序 blocks。
"""

from __future__ import annotations

import re
from urllib.parse import urljoin

from selectolax.lexbor import LexborHTMLParser

from ..core.errors import ParseError
from ..core.models import Article, Block

META_RE = re.compile(r"<!--enpproperty([\s\S]*?)-->")
AUTHOR_RE = re.compile(r"<author>([\s\S]*?)</author>")
SUBTITLE_RE = re.compile(r"<subtitle>([\s\S]*?)</subtitle>")
BODY_RE = re.compile(r"<!--enpcontent-->([\s\S]*?)<!--/enpcontent-->")
# 折叠换行与连续空白；全角空格也一并归为空白（缩进交给前端排版）
WS_RE = re.compile(r"[ \t\r\n\f\v\u00a0]+")


def parse_article(html: str, url: str) -> Article:
    """解析一篇正文。结构异常时抛 ParseError，而不是返回空文章。"""
    if not html or not html.strip():
        raise ParseError("正文页为空", detail="html_is_empty")

    tree = LexborHTMLParser(html)
    title_node = tree.css_first("div.article h1") or tree.css_first("h1")
    title = _clean(title_node.text(separator=" ", strip=True)) if title_node is not None else ""
    if not title:
        raise ParseError("未找到正文标题", detail="selector=div.article h1 matched 0")

    meta = META_RE.search(html)
    author = _meta_field(meta, AUTHOR_RE)
    subtitle = _meta_field(meta, SUBTITLE_RE)

    return Article(
        title=title,
        url=url,
        author=author or None,
        subtitle=subtitle or None,
        blocks=_parse_blocks(html, tree, url),
    )


def _parse_blocks(html: str, tree: LexborHTMLParser, base_url: str) -> list[Block]:
    # 页面里可能出现多个 enpcontent 区间（导语、相关链接等），
    # 正文是其中最长的那一段——按长度取最大，避免抓到摘要。
    candidates = BODY_RE.findall(html)
    if candidates:
        fragment = max(candidates, key=len)
    else:
        # 标记缺失时退回整篇文章容器，保证不丢正文
        container = tree.css_first("div.article")
        fragment = container.html if container is not None else ""

    if not fragment.strip():
        return []

    frag_tree = LexborHTMLParser(f"<html><body>{fragment}</body></html>")
    blocks: list[Block] = []

    for node in frag_tree.css("p"):
        image = node.css_first("img")
        src = image.attributes.get("src") if image is not None else None
        if src:
            blocks.append(Block.image(urljoin(base_url, src)))
            # 图片容器里若还有文字（少见），作为段落保留
            text = _clean(node.text(separator=" ", strip=True))
            if text:
                blocks.append(Block.paragraph(text))
            continue

        text = _clean(node.text(separator=" ", strip=True))
        if text:
            blocks.append(Block.paragraph(text))

    return blocks


def _meta_field(meta: re.Match[str] | None, pattern: re.Pattern[str]) -> str:
    if meta is None:
        return ""
    matched = pattern.search(meta.group(1))
    if matched is None:
        return ""
    # 作者原样保留（"本报记者  张  洋" 的内部空格有版式含义），只去掉首尾空白
    return matched.group(1).strip()


def _clean(text: str) -> str:
    return WS_RE.sub(" ", text.replace("\u3000", " ")).strip()
