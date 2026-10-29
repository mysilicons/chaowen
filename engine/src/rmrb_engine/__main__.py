"""引擎入口。

三种用法：
- `--version` / `--parse` / `--article`：离线自检，不联网；
- `--serve`：IPC 服务模式（stdout 只输出协议 JSON）；
- `--download YYYY-MM-DD`：命令行下载一期，便于人工验收。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date as Date
from pathlib import Path

from platformdirs import user_cache_dir

from . import __version__
from .api import Engine
from .core.paths import LibraryPaths
from .ipc import RpcServer
from .net.client import HttpClient
from .services.queue import DownloadService
from .store.db import Database
from .store.repo import Repo

DEFAULT_BASE_URL = "https://paper.people.com.cn/rmrb/pc/layout/202610/29/node_01.html"


def default_library() -> Path:
    env = os.environ.get("RMRB_LIBRARY")
    if env:
        return Path(env)
    return Path.home() / "Documents" / "人民日报"


def build_engine(library: Path, cache: Path) -> Engine:
    db = Database(cache / "state.db")
    repo = Repo(db)
    http = HttpClient()
    paths = LibraryPaths(library=library, cache=cache)
    service = DownloadService(http, repo, paths)
    return Engine(service, repo)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="rmrb-engine", description="人民日报阅报器引擎")
    parser.add_argument("--version", action="store_true", help="打印版本号")
    parser.add_argument("--parse", metavar="HTML", help="解析本地版面页 HTML")
    parser.add_argument("--article", metavar="HTML", help="解析本地正文页 HTML")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help="解析用的页面 URL")
    parser.add_argument("--json", action="store_true", help="以 JSON 输出")
    parser.add_argument("--serve", action="store_true", help="IPC 服务模式（NDJSON over stdio）")
    parser.add_argument("--download", metavar="YYYY-MM-DD", help="下载一期到下载目录")
    parser.add_argument("--pages", metavar="1,3,5", help="只下载指定版")
    parser.add_argument("--library", metavar="DIR", help="下载目录")
    parser.add_argument("--cache", metavar="DIR", help="缓存目录")
    return parser


def _parse_pages(raw: str | None) -> list[int] | None:
    if not raw:
        return None
    pages: list[int] = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start, end = part.split("-", 1)
            pages.extend(range(int(start), int(end) + 1))
        else:
            pages.append(int(part))
    return sorted(set(pages))


def main(argv: list[str] | None = None) -> int:
    # Windows 控制台/管道默认可能不是 UTF-8，会把中文和 JSON 写坏。
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")

    parser = build_parser()
    args = parser.parse_args(argv)

    if args.version:
        print(f"rmrb-engine {__version__}")
        return 0

    if args.parse:
        from .site.parser import parse_layout

        html = Path(args.parse).read_text(encoding="utf-8")
        issue = parse_layout(html, args.base_url)
        if args.json:
            print(json.dumps(issue.dump(), ensure_ascii=False, indent=2))
        else:
            current = next((p for p in issue.pages if p.pdf_url), None)
            print(f"date={issue.date} pages={issue.page_count} source={args.base_url}")
            if current is not None:
                print(
                    f"current={current.no:02d} {current.title} "
                    f"articles={len(current.articles)} pdf={current.pdf_url}"
                )
        return 0

    if args.article:
        from .site.article import parse_article

        html = Path(args.article).read_text(encoding="utf-8")
        article = parse_article(html, args.base_url)
        if args.json:
            print(json.dumps(article.dump(), ensure_ascii=False, indent=2))
        else:
            images = sum(1 for block in article.blocks if block.type == "img")
            chars = sum(len(block.text or "") for block in article.blocks)
            print(f"title={article.title}")
            print(
                f"author={article.author} blocks={len(article.blocks)} "
                f"images={images} chars={chars}"
            )
        return 0

    library = Path(args.library) if args.library else default_library()
    cache = Path(args.cache) if args.cache else Path(user_cache_dir("rmrb-reader"))

    if args.serve:
        engine = build_engine(library, cache)
        RpcServer(engine, sys.stdin, sys.stdout).run()
        return 0

    if args.download:
        try:
            day = Date.fromisoformat(args.download)
        except ValueError:
            print(f"日期格式错误：{args.download}", file=sys.stderr)
            return 2

        engine = build_engine(library, cache)
        engine.bind_emitter(
            lambda event, data: print(f"[{event}] {json.dumps(data, ensure_ascii=False)}", file=sys.stderr)
        )
        result = engine.service.run_issue(day, pages=_parse_pages(args.pages))
        print(
            f"date={result.date} status={result.status} done={result.done} "
            f"skipped={result.skipped} failed={result.failed} bytes={result.size}"
        )
        if result.merged:
            print(f"merged={result.merged} ({result.merged_bytes} B)")
        return 0 if result.failed == 0 else 1

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
