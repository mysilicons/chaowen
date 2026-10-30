"""Pagination is the China page's own public load-more flow, never a site crawl."""

import threading
import time

import httpx
import pytest
from test_zaobao_parser import ARTICLE, FEED, URL

from rmrb_engine.core.errors import EngineError
from rmrb_engine.net.zaobao import ZaobaoHttp
from rmrb_engine.services.zaobao_service import ZaobaoService
from rmrb_engine.site.zaobao import FEED_URL, more_url, parse_more
from rmrb_engine.store.db import Database


def page(items, number=2, total=100):
    return {
        "code": "00000",
        "result": {"pageNo": number, "pageSize": 27, "total": total, "data": items},
    }


OLDER = {
    "id": "7654321",
    "title": "更早的新闻",
    "url": "/news/china/story20261029-7654321",
    "contentPreview": "新闻摘要。",
    "publicationDate": "2026-10-29 17:36:26",
    "pictures": [],
}


def test_parse_public_load_more_and_scope():
    items, has_more = parse_more(page([OLDER]), 2)
    assert items[0].article_id == "7654321"
    assert items[0].published_at == "2026-10-29T17:36:26+08:00"
    assert items[0].excerpt == "新闻摘要。"
    assert has_more
    assert more_url(2) == "https://zbapi.zbstatic5.com/more/sitemap/8?pageNo=2&pageSize=27"
    with pytest.raises(EngineError):
        more_url(True)
    with pytest.raises(EngineError):
        parse_more({"code": "500", "result": {}}, 2)


def test_append_deduplicates_preserves_order_and_resume_cursor(tmp_path):
    seen = []

    def handler(request):
        seen.append(str(request.url))
        if str(request.url) == FEED_URL:
            return httpx.Response(200, text=FEED, headers={"content-type": "text/html"})
        return httpx.Response(200, json=page([{"title": "重复", "url": URL}, OLDER]))

    db = Database(tmp_path / "state.db")
    service = ZaobaoService(
        db,
        tmp_path,
        http=ZaobaoHttp(client=httpx.Client(transport=httpx.MockTransport(handler)), interval=0),
    )
    service.refresh_feed(threading.Event())
    service.load_more(threading.Event())
    result = service.feed()
    assert [i["articleId"] for i in result["items"]] == ["1234567", "7654321"]
    assert result["nextPage"] == 3
    assert seen == [FEED_URL, more_url(2)]
    service.close()
    service = ZaobaoService(Database(tmp_path / "state.db"), tmp_path)
    assert service.feed()["nextPage"] == 3
    service.close()


def test_failed_page_does_not_advance_and_empty_page_finishes(tmp_path):
    response = [page([])]
    http = ZaobaoHttp(
        client=httpx.Client(
            transport=httpx.MockTransport(
                lambda r: (
                    httpx.Response(200, text=FEED, headers={"content-type": "text/html"})
                    if str(r.url) == FEED_URL
                    else httpx.Response(200, json=response[0])
                )
            )
        ),
        interval=0,
    )
    service = ZaobaoService(Database(tmp_path / "state.db"), tmp_path, http=http)
    service.refresh_feed(threading.Event())
    response[0] = {"code": "fail"}
    with pytest.raises(EngineError):
        service.load_more(threading.Event())
    assert service.feed()["nextPage"] == 2
    response[0] = page([])
    service.load_more(threading.Event())
    assert service.feed()["hasMore"] is False
    assert len(service.feed()["items"]) == 1
    service.close()


def test_text_ready_before_slow_images_and_clear_cannot_resurrect_cache(tmp_path):
    image_started, release = threading.Event(), threading.Event()

    def handler(request):
        if str(request.url) == FEED_URL:
            return httpx.Response(200, text=FEED, headers={"content-type": "text/html"})
        if str(request.url) == URL:
            return httpx.Response(200, text=ARTICLE, headers={"content-type": "text/html"})
        image_started.set()
        release.wait(2)
        return httpx.Response(
            200, content=b"\x89PNG\r\n\x1a\n", headers={"content-type": "image/png"}
        )

    transport = httpx.MockTransport(handler)
    service = ZaobaoService(
        Database(tmp_path / "state.db"),
        tmp_path,
        http=ZaobaoHttp(client=httpx.Client(transport=transport), interval=0),
        media_http=ZaobaoHttp(client=httpx.Client(transport=transport), interval=0),
    )
    service.refresh_feed(threading.Event())
    started = time.monotonic()
    service.fetch_article("1234567", threading.Event())
    assert time.monotonic() - started < 1
    assert service.article("1234567")["cached"] is True
    assert image_started.wait(1)
    service.clear_cache()
    release.set()
    service.close()
    assert service.article("1234567")["cached"] is False
    assert not list((tmp_path / "zaobao/media").glob("*.img"))


def test_v2_cursor_migration_preserves_existing_feed(tmp_path):
    import sqlite3

    from rmrb_engine.store.db import DDL

    path = tmp_path / "state.db"
    with sqlite3.connect(path) as conn:
        conn.executescript(DDL)
        conn.execute("INSERT INTO schema_meta VALUES('version','2')")
        conn.execute(
            "CREATE TABLE zaobao_feed_state(id INTEGER PRIMARY KEY,fetched_at TEXT NOT NULL)"
        )
        conn.execute("INSERT INTO zaobao_feed_state VALUES(1,'2026-10-30T01:00:00Z')")
    db = Database(path)
    row = db.conn.execute("SELECT fetched_at,next_page,has_more FROM zaobao_feed_state").fetchone()
    assert tuple(row) == ("2026-10-30T01:00:00Z", 2, 1)
    assert path.with_name("state.db.v2.bak").exists()
    db.close()
