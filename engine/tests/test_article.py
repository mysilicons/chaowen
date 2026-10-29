"""E-03 验收：正文解析。"""

from __future__ import annotations

from pathlib import Path

import pytest

from rmrb_engine.core.errors import ParseError
from rmrb_engine.core.models import BlockType
from rmrb_engine.site.article import parse_article

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "_probe"

URL_30188305 = "https://paper.people.com.cn/rmrb/pc/content/202610/29/content_30188305.html"
URL_30188309 = "https://paper.people.com.cn/rmrb/pc/content/202610/29/content_30188309.html"


def read_fixture(name: str) -> str:
    path = PROBE / name
    if not path.exists():
        pytest.fail(f"缺少夹具 {path}")
    return path.read_text(encoding="utf-8")


def test_regular_article():
    article = parse_article(read_fixture("content_30188305.html"), URL_30188305)

    assert "更加清醒坚定" in article.title
    assert article.author == "本报记者  张  洋"
    assert article.blocks, "正文不能为空"
    assert all(block.type == BlockType.PARAGRAPH for block in article.blocks)

    assert len(article.blocks) == 29
    total_chars = sum(len(block.text or "") for block in article.blocks)
    assert total_chars > 1500


def test_indent_is_stripped():
    """原文用全角空格缩进，交给前端排版时要先剥掉，否则会双缩进。"""
    article = parse_article(read_fixture("content_30188305.html"), URL_30188305)

    assert not any((block.text or "").startswith("　") for block in article.blocks)
    assert not any((block.text or "").startswith(" ") for block in article.blocks)


def test_image_report():
    article = parse_article(read_fixture("content_30188309.html"), URL_30188309)

    first = article.blocks[0]
    assert first.type == BlockType.IMAGE
    assert first.src is not None
    assert first.src.startswith("https://paper.people.com.cn/rmrb/pc/pic/202610/29/")

    paragraphs = [block for block in article.blocks if block.type == BlockType.PARAGRAPH]
    assert len(paragraphs) == 3


def test_missing_body_marker_falls_back():
    html = read_fixture("content_30188305.html")
    html = html.replace("<!--enpcontent-->", "").replace("<!--/enpcontent-->", "")

    article = parse_article(html, URL_30188305)
    assert article.blocks


def test_missing_meta_comment_is_tolerated():
    html = read_fixture("content_30188305.html")
    html = html.replace("enpproperty", "enp-property")

    article = parse_article(html, URL_30188305)
    assert article.author is None
    assert article.blocks


def test_empty_html_raises():
    with pytest.raises(ParseError):
        parse_article("", URL_30188305)


def test_missing_title_raises():
    with pytest.raises(ParseError) as exc:
        parse_article("<html><body><div>没有标题</div></body></html>", URL_30188305)
    assert "标题" in str(exc.value)
