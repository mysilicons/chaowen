import threading

import httpx
import pytest
from test_zaobao_parser import ARTICLE, FEED, URL

from rmrb_engine.core.errors import EngineError
from rmrb_engine.net.zaobao import ZaobaoHttp
from rmrb_engine.services.zaobao_service import ZaobaoService
from rmrb_engine.site.zaobao import FEED_URL
from rmrb_engine.store.db import Database


def make_service(tmp_path, handler):
    http = ZaobaoHttp(client=httpx.Client(transport=httpx.MockTransport(handler)), interval=0)
    return ZaobaoService(http=http)


def test_feed_refresh_never_fetches_article_and_cache_is_offline(tmp_path):
    urls = []

    def handler(request):
        urls.append(str(request.url))
        return httpx.Response(
            200,
            text=FEED if str(request.url) == FEED_URL else ARTICLE,
            headers={"content-type": "text/html"},
        )

    service = make_service(tmp_path, handler)
    service.refresh_feed(threading.Event())
    assert urls == [FEED_URL]
    assert service.feed()["items"][0]["title"] == "测试新闻"
    service.fetch_article("1234567", threading.Event())
    article = service.article("1234567")
    assert article["cached"] is True
    assert article["article"]["blocks"][1]["text"] == "第一段加粗。"
    requests = urls.count(URL)
    service.fetch_article("1234567", threading.Event())
    assert urls.count(URL) == requests
    service.close()


def test_failed_refresh_keeps_snapshot_and_unknown_id_is_rejected(tmp_path):
    content = [FEED]
    service = make_service(
        tmp_path,
        lambda r: httpx.Response(200, text=content[0], headers={"content-type": "text/html"}),
    )
    service.refresh_feed(threading.Event())
    content[0] = "<main>broken</main>"
    with pytest.raises(EngineError):
        service.refresh_feed(threading.Event())
    assert len(service.feed()["items"]) == 1
    with pytest.raises(EngineError):
        service.fetch_article("999", threading.Event())
    service.close()


def test_upgrade_removes_only_news_tables(tmp_path):
    import sqlite3

    from rmrb_engine.store.db import DDL

    path = tmp_path / "state.db"
    with sqlite3.connect(path) as conn:
        conn.executescript(DDL)
        conn.execute("INSERT INTO schema_meta VALUES('version','3')")
        conn.execute(
            "INSERT INTO issues(date,status,updated_at) VALUES('2026-10-29','archived','now')"
        )
        conn.execute("CREATE TABLE zaobao_articles(article_id TEXT PRIMARY KEY,body TEXT)")
        conn.execute("INSERT INTO zaobao_articles VALUES('123','retired news body')")
    db = Database(path)
    assert db.conn.execute("SELECT status FROM issues").fetchone()[0] == "archived"
    assert not db.conn.execute(
        "SELECT name FROM sqlite_master WHERE name LIKE 'zaobao_%'"
    ).fetchall()
    db.close()


def test_network_refuses_cross_domain_redirect_before_visiting():
    seen = []

    def handler(request):
        seen.append(str(request.url))
        return httpx.Response(302, headers={"location": "https://www.zaobao.com.sg/news/china"})

    http = ZaobaoHttp(client=httpx.Client(transport=httpx.MockTransport(handler)), interval=0)
    with pytest.raises(EngineError):
        http.text(FEED_URL, threading.Event())
    assert seen == [FEED_URL]


def test_403_does_not_retry_and_size_limit_is_enforced():
    seen = []

    def handler(request):
        seen.append(request)
        return httpx.Response(403)

    http = ZaobaoHttp(client=httpx.Client(transport=httpx.MockTransport(handler)), interval=0)
    with pytest.raises(EngineError):
        http.text(URL, threading.Event())
    assert len(seen) == 1
    http = ZaobaoHttp(
        client=httpx.Client(
            transport=httpx.MockTransport(
                lambda r: httpx.Response(
                    200, content=b"x" * 40, headers={"content-type": "text/html"}
                )
            )
        ),
        interval=0,
    )
    with pytest.raises(EngineError):
        http.request(URL, threading.Event(), max_bytes=20)


def test_backend_does_not_download_or_store_images(tmp_path):
    seen = []

    def handler(request):
        seen.append(str(request.url))
        return httpx.Response(
            200,
            text=FEED if str(request.url) == FEED_URL else ARTICLE,
            headers={"content-type": "text/html"},
        )

    current = make_service(tmp_path, handler)
    current.refresh_feed(threading.Event())
    current.fetch_article("1234567", threading.Event())
    assert seen == [FEED_URL, URL]
    assert any(
        block["src"]
        for block in current.article("1234567")["article"]["blocks"]
        if block["type"] == "img"
    )
    assert all(block["local"] is None for block in current.article("1234567")["article"]["blocks"])
    current.close()


def test_rate_limit_keeps_full_retry_after_without_retry():
    import time

    http = ZaobaoHttp(
        client=httpx.Client(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(429, headers={"retry-after": "300"})
            )
        ),
        interval=0,
    )
    before = time.monotonic()
    with pytest.raises(EngineError) as exc:
        http.text(FEED_URL, threading.Event())
    assert exc.value.code.value == "RATE_LIMITED"
    assert http._next_request >= before + 300
    http.close()


def test_network_can_be_cancelled_before_any_request():
    seen = []
    http = ZaobaoHttp(
        client=httpx.Client(
            transport=httpx.MockTransport(
                lambda request: seen.append(request) or httpx.Response(200)
            )
        ),
        interval=0,
    )
    cancel = threading.Event()
    cancel.set()
    from rmrb_engine.services.control import Cancelled

    with pytest.raises(Cancelled):
        http.text(FEED_URL, cancel)
    assert not seen
    http.close()
