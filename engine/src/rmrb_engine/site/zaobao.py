"""Pure parsers for the locally verified zaobao.com HTML. No recursive discovery."""

from __future__ import annotations

import json
import re
from datetime import datetime
from urllib.parse import urljoin, urlsplit, urlunsplit

from selectolax.lexbor import LexborHTMLParser, LexborNode

from ..core.errors import EngineError, ErrorCode, ParseError
from ..core.models import Block
from ..core.zaobao_models import ZaobaoArticle, ZaobaoSummary

FEED_URL = "https://www.zaobao.com/news/china"
MORE_BASE = "https://zbapi.zbstatic5.com/more/sitemap/8"
PAGE_SIZE = 27
STORY = re.compile(r"/news/china/story\d{8}-(\d{1,20})/?$")
MEDIA_HOSTS = frozenset({"dss0.zbstatic5.com", "cassette.sphdigital.com.sg"})
REMOVE = "script,style,aside,nav,.further-reading,.read-on-app-cover,[data-testid='related-words'],[data-testid='paywall'],.paywall,.advertisement"


def more_url(page: int) -> str:
    if type(page) is not int or not 2 <= page <= 1000:
        raise EngineError(ErrorCode.BAD_REQUEST, "早报分页页码非法")
    return f"{MORE_BASE}?pageNo={page}&pageSize={PAGE_SIZE}"


def parse_more(payload: object, page: int) -> tuple[list[ZaobaoSummary], bool]:
    if not isinstance(payload, dict) or payload.get("code") not in {"00000", "200"}:
        raise ParseError("早报历史列表返回失败")
    result = payload.get("result")
    if (
        not isinstance(result, dict)
        or result.get("pageNo") != page
        or not isinstance(result.get("data"), list)
    ):
        raise ParseError("早报分页结构已变化")
    records = result["data"]
    items: dict[str, ZaobaoSummary] = {}
    for record in records:
        item = _more_item(record)
        if item:
            items.setdefault(item.article_id, item)
    if records and not items:
        raise ParseError("早报历史列表未找到有效中国新闻")
    total = result.get("total")
    has_more = bool(records) and (type(total) is not int or page * PAGE_SIZE < total)
    return list(items.values()), has_more


def _more_item(record: object) -> ZaobaoSummary | None:
    if not isinstance(record, dict) or not isinstance(record.get("url"), str):
        return None
    try:
        url, identity = article_url(record["url"])
    except (EngineError, ValueError):
        return None
    title = (
        record.get("displayHeadlineZbcom") or record.get("displayHeadline") or record.get("title")
    )
    if not isinstance(title, str) or not title.strip():
        return None
    pictures = record.get("pictures") or []
    image = pictures[0] if pictures and isinstance(pictures[0], dict) else {}
    published = record.get("publicationDate")
    try:
        stamp = (
            datetime.strptime(published, "%Y-%m-%d %H:%M:%S").isoformat() + "+08:00"
            if isinstance(published, str)
            else None
        )
    except ValueError:
        stamp = None
    preview = record.get("contentPreview") or record.get("digest")
    return ZaobaoSummary(
        article_id=identity,
        title=title.strip(),
        url=url,
        published_at=stamp,
        time_label=stamp,
        excerpt=preview[:400] if isinstance(preview, str) else None,
        thumbnail=media_url(image.get("thumbnail") or image.get("uri") or ""),
    )


def article_url(raw: str) -> tuple[str, str]:
    parsed = urlsplit(urljoin(FEED_URL, raw))
    match = STORY.fullmatch(parsed.path)
    if parsed.scheme != "https" or parsed.netloc != "www.zaobao.com" or not match:
        raise EngineError(ErrorCode.BAD_REQUEST, "文章链接不在中国频道范围内")
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path.rstrip("/"), "", "")), match[1]


def media_url(raw: str) -> str | None:
    parsed = urlsplit(urljoin(FEED_URL, raw))
    if parsed.scheme == "https" and parsed.netloc in MEDIA_HOSTS:
        return parsed.geturl()
    return None


def _text(node: LexborNode | None) -> str | None:
    return node.text(strip=True) or None if node is not None else None


def parse_feed(html: str) -> list[ZaobaoSummary]:
    tree = LexborHTMLParser(html)
    container = tree.css_first('main [data-testid="article-list"]')
    if container is None:
        raise ParseError("未找到早报中国频道列表")
    items: dict[str, ZaobaoSummary] = {}
    for card in container.css("article"):
        item = _feed_card(card)
        if item is not None:
            items.setdefault(item.article_id, item)
    if not items:
        raise ParseError("早报列表没有可识别的文章，页面结构可能已变化")
    return list(items.values())


def _feed_card(card: LexborNode) -> ZaobaoSummary | None:
    for link in card.css("a[href]"):
        try:
            url, identity = article_url(link.attributes.get("href") or "")
        except (EngineError, ValueError):
            continue
        title = link.attributes.get("title") or _text(link)
        if not title:
            continue
        image = card.css_first("img")
        return ZaobaoSummary(
            article_id=identity,
            title=title.strip(),
            url=url,
            time_label=_text(card.css_first("time, span")),
            thumbnail=media_url(image.attributes.get("src") or "") if image else None,
        )
    return None


def _metadata(tree: LexborHTMLParser) -> dict:
    for script in tree.css('script[type="application/ld+json"]'):
        try:
            value = json.loads(script.text())
        except (ValueError, TypeError):
            continue
        candidates = value if isinstance(value, list) else [value]
        for item in candidates:
            if isinstance(item, dict) and item.get("@type") == "NewsArticle":
                return item
    return {}


def _author(tree: LexborHTMLParser, meta: dict) -> str | None:
    byline = tree.css_first(
        '[data-testid="article-author"] a[href*="/byline/"], [data-testid="article-author"] a[href*="/author/"]'
    )
    if byline is not None:
        return _text(byline)
    value = meta.get("author")
    if isinstance(value, list):
        return (
            "、".join(
                v["name"] for v in value if isinstance(v, dict) and isinstance(v.get("name"), str)
            )
            or None
        )
    return value.get("name") if isinstance(value, dict) else None


def _image(node: LexborNode, caption: str | None = None) -> Block | None:
    raw = node.attributes.get("data-src") or node.attributes.get("src") or ""
    url = media_url(raw)
    return Block.image(url, caption or node.attributes.get("alt") or None) if url else None


def _blocks(node: LexborNode) -> list[Block]:
    result: list[Block] = []
    child = node.child
    while child is not None:
        result.extend(_node_blocks(child))
        child = child.next
    return result


def _node_blocks(node: LexborNode) -> list[Block]:
    if node.tag in {"p", "h2", "h3", "li", "blockquote"}:
        # Paragraphs may contain images; retain them rather than turning them into text.
        images = [b for image in node.css("img") if (b := _image(image))]
        text = _text(node)
        return ([Block.paragraph(text)] if text else []) + images
    if node.tag == "figure":
        caption = _text(node.css_first("figcaption"))
        return [b for image in node.css("img") if (b := _image(image, caption))]
    if node.tag == "img":
        block = _image(node)
        return [block] if block else []
    return _blocks(node)


def parse_article(html: str, raw_url: str) -> ZaobaoArticle:
    url, identity = article_url(raw_url)
    tree = LexborHTMLParser(html)
    body = tree.css_first('article#article-body[data-testid="article-body"]')
    title = _text(tree.css_first("h1.article-title"))
    if body is None or not title:
        raise ParseError("未找到早报正文，可能需要登录、验证或页面结构已变化")
    restricted = (
        tree.css_first('[data-testid="paywall"], .paywall, [data-testid="subscriber-only"]')
        is not None
    )
    meta = _metadata(tree)
    restricted = restricted or meta.get("isAccessibleForFree") is False
    author = _author(tree, meta)
    banner = tree.css_first('[data-testid="article-banner"]')
    blocks = []
    if banner is not None and (image := banner.css_first("img")) is not None:
        block = _image(image, _text(banner))
        if block:
            blocks.append(block)
    for node in body.css(REMOVE):
        node.decompose()
    blocks.extend(_blocks(body))
    if not any(block.text for block in blocks):
        raise ParseError("早报文章没有可提取正文")
    known = meta.get("@type") == "NewsArticle"
    return ZaobaoArticle(
        article_id=identity,
        title=title,
        url=url,
        author=author,
        published_at=meta.get("datePublished"),
        updated_at=meta.get("dateModified"),
        blocks=blocks,
        access="subscriber" if restricted else "public" if known else "unknown",
        content_state="preview" if restricted else "full" if known else "unknown",
    )
