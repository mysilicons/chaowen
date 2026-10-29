"""新版版面页解析（/rmrb/pc/layout/{YYYYMM}/{DD}/node_{NN}.html）。

一个版面页同时提供三类信息：
1. 整期版面列表（swiper 导航，含全部版号与标题）；
2. 当前版的 PDF 直链、缩略图、"本版新闻"列表；
3. 报纸日期。

因此解析任意一个 node_NN.html 都能得到整期目录，但只有当前版的 PDF 直链。
其余版的 PDF 直链需逐个抓取对应 node_NN.html（见 parse_page_detail）。
"""

from __future__ import annotations

import re
from datetime import date as Date
from functools import lru_cache
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

from selectolax.lexbor import LexborHTMLParser

from ..core.errors import ParseError
from ..core.models import ArticleRef, Issue, Page

RULES_PATH = Path(__file__).with_name("rules") / "v2.yml"

# "01版：要闻" 与 "第01版：要闻" 都要能匹配
LABEL_RE = re.compile(r"^\s*第?\s*(\d{1,2})\s*版\s*[：:]\s*(.+?)\s*$")
DATE_RE = re.compile(r"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日")
PAGE_LINK_FALLBACK_RE = re.compile(
    r"<a\b([^>]*\bid=[\"']?pageLink[\"']?[^>]*)>([^<]*)</a>", re.IGNORECASE
)
HREF_RE = re.compile(r"href=[\"']([^\"']+)[\"']", re.IGNORECASE)
PDF_FALLBACK_RE = re.compile(r"href=[\"']([^\"']+\.pdf)[\"']", re.IGNORECASE)

DEFAULT_RULES: dict[str, Any] = {
    "layout": {
        "page_list": 'div.swiper-slide a[id="pageLink"]',
        "page_label": "p.ban",
        "pdf_link": 'div.paper-bot a[href$=".pdf"]',
        "thumb": 'div.paper img[src$=".jpg.2"]',
        "articles": "div.news ul li a",
        "date": "span.newstime",
    }
}


@lru_cache(maxsize=1)
def load_rules() -> dict[str, Any]:
    """读取规则文件；缺失或损坏时退回内置默认值。"""
    try:
        import yaml

        with RULES_PATH.open(encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
        if isinstance(data, dict) and isinstance(data.get("layout"), dict):
            return data
    except (OSError, ImportError, ValueError):
        pass
    return DEFAULT_RULES


def parse_layout(html: str, base_url: str) -> Issue:
    """解析版面页，返回整期目录（当前页附带 PDF/缩略图/文章详情）。"""
    if not html or not html.strip():
        raise ParseError("页面内容为空", detail="html_is_empty")

    rules = load_rules()["layout"]
    tree = LexborHTMLParser(html)

    pages = _parse_page_list(tree, rules, base_url)
    if not pages:
        raise ParseError(
            "未找到版面列表",
            detail=f"selector={rules['page_list']} matched 0",
        )

    issue = Issue(
        date=_parse_date(tree, rules),
        page_count=len(pages),
        pages=pages,
        source_url=base_url,
    )
    _apply_current_detail(tree, rules, base_url, issue)
    return issue


def parse_page_detail(html: str, base_url: str, no: int | None = None) -> Page:
    """解析单个版面页，返回该版的详情（PDF 直链、缩略图、本版新闻）。"""
    if not html or not html.strip():
        raise ParseError("页面内容为空", detail="html_is_empty")

    rules = load_rules()["layout"]
    tree = LexborHTMLParser(html)

    label = tree.css_first(rules["page_label"])
    matched = LABEL_RE.match(label.text(strip=True)) if label is not None else None
    page_no = int(matched.group(1)) if matched else (no or 0)
    title = matched.group(2) if matched else ""

    page = Page(no=page_no, title=title, url=base_url)
    _fill_page(page, tree, rules, base_url)
    return page


# --------------------------------------------------------------------------- #
# 内部实现
# --------------------------------------------------------------------------- #


def _parse_page_list(tree: LexborHTMLParser, rules: dict[str, str], base_url: str) -> list[Page]:
    pages: list[Page] = []
    seen: set[int] = set()

    for node in tree.css(rules["page_list"]):
        href = node.attributes.get("href") or ""
        matched = LABEL_RE.match(node.text(strip=True))
        if not href or not matched:
            continue
        no = int(matched.group(1))
        if no in seen:  # 防御：列表被重复渲染
            continue
        seen.add(no)
        pages.append(Page(no=no, title=matched.group(2), url=urljoin(base_url, href)))

    if pages:
        return pages

    # 选择器失效时用正则兜底（站点模板变化的第一道缓冲）
    for attrs, label in PAGE_LINK_FALLBACK_RE.findall(tree.html or ""):
        href_match = HREF_RE.search(attrs)
        label_match = LABEL_RE.match(label.strip())
        if not href_match or not label_match:
            continue
        no = int(label_match.group(1))
        if no in seen:
            continue
        seen.add(no)
        pages.append(
            Page(no=no, title=label_match.group(2), url=urljoin(base_url, href_match.group(1)))
        )

    return pages


def _apply_current_detail(
    tree: LexborHTMLParser, rules: dict[str, str], base_url: str, issue: Issue
) -> None:
    label = tree.css_first(rules["page_label"])
    if label is None:
        return
    matched = LABEL_RE.match(label.text(strip=True))
    if matched is None:
        return

    no = int(matched.group(1))
    page = next((p for p in issue.pages if p.no == no), None)
    if page is None:
        return
    if not page.title:
        page.title = matched.group(2)
    _fill_page(page, tree, rules, base_url)


def _fill_page(page: Page, tree: LexborHTMLParser, rules: dict[str, str], base_url: str) -> None:
    link = tree.css_first(rules["pdf_link"])
    href = link.attributes.get("href") if link is not None else None

    if not href:
        fallback = PDF_FALLBACK_RE.search(tree.html or "")
        href = fallback.group(1) if fallback else None

    if href:
        page.pdf_url = urljoin(base_url, href)
        if link is not None:
            page.original_name = link.attributes.get("download")

    img = tree.css_first(rules["thumb"]) or tree.css_first("div.paper img")
    src = img.attributes.get("src") if img is not None else None
    if src:
        page.thumb_url = urljoin(base_url, src)

    refs: list[ArticleRef] = []
    for anchor in tree.css(rules["articles"]):
        anchor_href = anchor.attributes.get("href") or ""
        text = anchor.text(strip=True)
        if anchor_href and text:
            refs.append(ArticleRef(title=text, url=urljoin(base_url, anchor_href)))
    page.articles = refs


def _parse_date(tree: LexborHTMLParser, rules: dict[str, str]) -> Date | None:
    node = tree.css_first(rules["date"])
    if node is None:
        return None
    matched = DATE_RE.search(node.text(strip=True))
    if matched is None:
        return None
    return Date(int(matched.group(1)), int(matched.group(2)), int(matched.group(3)))
