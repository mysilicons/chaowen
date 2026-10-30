"""Synthetic fixtures follow the locally observed .com DOM, without copying news."""

import pytest

from rmrb_engine.core.errors import EngineError
from rmrb_engine.site.zaobao import FEED_URL, article_url, parse_article, parse_feed

URL = "https://www.zaobao.com/news/china/story20261030-1234567"
FEED = """<main><h1>中国</h1><div data-testid="article-list">
<article><a href="/news/china/story20261030-1234567"><img src="https://dss0.zbstatic5.com/image/zaobao/test"></a>
<a title="测试新闻" href="/news/china/story20261030-1234567?utm_source=test">测试新闻</a><span>10分钟前</span></article>
<article><a href="https://www.zaobao.com.sg/news/china/story20261030-9">跨域</a></article>
</div><aside><a href="/news/china/story20261030-999">热门推荐</a></aside></main>"""
ARTICLE = """<main><h1 class="article-title">测试新闻</h1>
<script type="application/ld+json">{"@type":"NewsArticle","datePublished":"2026-10-30T09:42:00+08:00","author":{"name":"测试作者"}}</script>
<div data-testid="article-banner"><img src="https://dss0.zbstatic5.com/image/zaobao/test"><div>封面说明</div></div>
<article id="article-body" data-testid="article-body"><p>第一段<strong>加粗</strong>。</p>
<section class="further-reading"><p>推荐广告</p><img src="https://dss0.zbstatic5.com/image/zaobao/ad"></section>
<p>第二段。</p><figure><img src="https://dss0.zbstatic5.com/image/zaobao/inside"><figcaption>图注</figcaption></figure>
<div class="read-on-app-cover"><p>应用提示</p></div><script>bad()</script></article></main>"""


def test_feed_only_discovers_main_list_and_deduplicates():
    items = parse_feed(FEED)
    assert len(items) == 1
    assert items[0].title == "测试新闻"
    assert items[0].url == URL
    assert items[0].article_id == "1234567"
    assert FEED_URL == "https://www.zaobao.com/news/china"


@pytest.mark.parametrize(
    "url",
    [
        "https://www.zaobao.com.sg/news/china/story20261030-1",
        "http://www.zaobao.com/news/china/story20261030-1",
        "https://www.zaobao.com@localhost/news/china/story20261030-1",
        "https://www.zaobao.com/news/world/story20261030-1",
        "https://www.zaobao.com/news/china",
    ],
)
def test_article_url_rejects_out_of_scope_targets(url):
    with pytest.raises(EngineError):
        article_url(url)


def test_feed_structure_change_is_not_successful_empty_feed():
    with pytest.raises(EngineError, match="列表"):
        parse_feed("<main><p>Unexpected</p></main>")


def test_article_preserves_blocks_excludes_recommendations_and_keeps_tail():
    article = parse_article(ARTICLE, URL)
    assert article.title == "测试新闻"
    assert article.author == "测试作者"
    assert article.published_at == "2026-10-30T09:42:00+08:00"
    assert [b.type for b in article.blocks] == ["img", "p", "p", "img"]
    assert article.blocks[1].text == "第一段加粗。"
    assert article.blocks[2].text == "第二段。"
    assert article.blocks[3].caption == "图注"
    assert article.content_state == "full"


def test_explicit_paywall_is_preview_even_with_many_paragraphs():
    html = ARTICLE.replace(
        '<article id="article-body"',
        '<div data-testid="paywall">订户专享</div><article id="article-body"',
    )
    article = parse_article(html, URL)
    assert (article.access, article.content_state) == ("subscriber", "preview")


def test_unknown_template_never_reports_full():
    with pytest.raises(EngineError):
        parse_article("<h1>Just a moment</h1><p>Verify you are human</p>", URL)
