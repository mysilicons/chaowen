import threading
from pathlib import Path

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
    return ZaobaoService(Database(tmp_path / "state.db"), tmp_path / "cache", http=http)


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
    requests = len(urls)
    service.fetch_article("1234567", threading.Event())
    assert len(urls) == requests
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


def test_clear_preserves_read_state_and_people_tables(tmp_path):
    service = make_service(
        tmp_path,
        lambda r: httpx.Response(
            200,
            text=FEED if str(r.url) == FEED_URL else ARTICLE,
            headers={"content-type": "text/html"},
        ),
    )
    service.refresh_feed(threading.Event())
    service.fetch_article("1234567", threading.Event())
    service.mark_read("1234567", True)
    service.clear_cache()
    assert service.article("1234567")["cached"] is False
    assert service.feed()["items"][0]["read"] is True
    assert service.db.conn.execute("SELECT COUNT(*) FROM issues").fetchone()[0] == 0
    service.close()


def test_v1_upgrade_preserves_data_and_reopens(tmp_path):
    import sqlite3

    from rmrb_engine.store.db import DDL

    path = tmp_path / "state.db"
    with sqlite3.connect(path) as conn:
        conn.executescript(DDL)
        conn.execute("INSERT INTO schema_meta VALUES('version','1')")
        conn.execute(
            "INSERT INTO issues(date,status,updated_at) VALUES('2026-10-29','archived','now')"
        )
    db = Database(path)
    assert db.conn.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0] == "2"
    assert db.conn.execute("SELECT status FROM issues").fetchone()[0] == "archived"
    db.close()
    assert Path(str(path) + ".v1.bak").exists()
    db = Database(path)
    assert db.conn.execute("SELECT COUNT(*) FROM zaobao_articles").fetchone()[0] == 0
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
