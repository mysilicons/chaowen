"""版面页解析器测试（E-02 验收）。

夹具来自 2026-10-29 与 2026-10-24 的真实抓取，见 _probe/。
"""

from __future__ import annotations

from datetime import date
from pathlib import Path

import pytest

from rmrb_engine.core.errors import ParseError
from rmrb_engine.site.parser import parse_layout, parse_page_detail

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "_probe"

BASE_20261029_01 = "https://paper.people.com.cn/rmrb/pc/layout/202610/29/node_01.html"
BASE_20261029_08 = "https://paper.people.com.cn/rmrb/pc/layout/202610/29/node_08.html"
BASE_20261024_01 = "https://paper.people.com.cn/rmrb/pc/layout/202610/24/node_01.html"


def read_fixture(name: str) -> str:
    path = PROBE / name
    if not path.exists():
        pytest.fail(f"缺少夹具 {path}，请先抓取")
    return path.read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def issue_20261029():
    return parse_layout(read_fixture("pc_20261029_01.html"), BASE_20261029_01)


def test_page_count_is_20(issue_20261029):
    assert issue_20261029.page_count == 20
    assert [p.no for p in issue_20261029.pages] == list(range(1, 21))


def test_page_titles(issue_20261029):
    pages = {p.no: p for p in issue_20261029.pages}
    assert pages[1].title == "要闻"
    assert pages[5].title == "评论"
    assert pages[8].title == "广告"
    assert pages[20].title == "副刊"


def test_issue_date(issue_20261029):
    assert issue_20261029.date == date(2026, 10, 29)


def test_current_page_pdf_link(issue_20261029):
    page = issue_20261029.pages[0]
    assert page.pdf_url is not None
    assert page.pdf_url.startswith("https://paper.people.com.cn/rmrb/pc/attachement/202610/29/")
    assert page.pdf_url.endswith(".pdf")
    assert page.original_name == "rmrb2026102901.pdf"


def test_current_page_articles(issue_20261029):
    page = issue_20261029.pages[0]
    assert len(page.articles) == 8
    assert all(a.url.startswith("https://paper.people.com.cn/rmrb/pc/content/") for a in page.articles)
    assert all(a.title for a in page.articles)


def test_thumb_url(issue_20261029):
    page = issue_20261029.pages[0]
    assert page.thumb_url is not None
    assert page.thumb_url.startswith("https://paper.people.com.cn/rmrb/pc/pic/202610/29/")
    assert page.thumb_url.endswith(".jpg.2")


def test_only_current_page_has_pdf_link(issue_20261029):
    """版面列表只给目录；其余版的 PDF 直链要单独抓它们自己的页面。"""
    assert [p.no for p in issue_20261029.pages if p.pdf_url] == [1]


def test_ad_page_has_single_article():
    issue = parse_layout(read_fixture("pc_20261029_08.html"), BASE_20261029_08)
    page = issue.pages[7]
    assert page.no == 8
    assert page.title == "广告"
    assert len(page.articles) == 1


def test_weekend_issue_has_8_pages():
    issue = parse_layout(read_fixture("pc_20261024_01.html"), BASE_20261024_01)
    assert issue.page_count == 8
    assert issue.date == date(2026, 10, 24)


def test_parse_page_detail():
    page = parse_page_detail(read_fixture("pc_20261029_08.html"), BASE_20261029_08)
    assert page.no == 8
    assert page.title == "广告"
    assert page.pdf_url is not None and page.pdf_url.endswith(".pdf")
    assert page.original_name is not None and page.original_name.startswith("rmrb2026102908")
    assert len(page.articles) == 1


def test_empty_html_raises():
    with pytest.raises(ParseError) as exc:
        parse_layout("", BASE_20261029_01)
    assert exc.value.code.value == "PARSE_ERROR"


def test_broken_html_reports_selector():
    """结构变化时必须给出可诊断信息，而不是静默返回空列表。"""
    with pytest.raises(ParseError) as exc:
        parse_layout("<html><body><p>无版面</p></body></html>", BASE_20261029_01)
    assert "matched 0" in (exc.value.detail or "")
