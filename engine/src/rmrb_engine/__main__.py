"""引擎命令行入口。

E-02 阶段只提供 --version 与 --parse 两个自检入口；
IPC 服务模式见 E-09（届时 stdout 只允许输出协议 JSON）。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import __version__

DEFAULT_BASE_URL = "https://paper.people.com.cn/rmrb/pc/layout/202610/29/node_01.html"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="rmrb-engine", description="人民日报阅报器引擎")
    parser.add_argument("--version", action="store_true", help="打印版本号")
    parser.add_argument("--parse", metavar="HTML", help="解析本地版面页 HTML 并输出摘要")
    parser.add_argument("--article", metavar="HTML", help="解析本地正文页 HTML 并输出摘要")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help="解析用的页面 URL")
    parser.add_argument("--json", action="store_true", help="以 JSON 输出")
    return parser


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

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
