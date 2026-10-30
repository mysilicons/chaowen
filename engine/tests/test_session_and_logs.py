import threading

import httpx
import pytest
from test_zaobao_parser import ARTICLE, FEED

from rmrb_engine.core.errors import EngineError
from rmrb_engine.diagnostics import configure_logging, log_exception
from rmrb_engine.net.zaobao import ZaobaoHttp
from rmrb_engine.services.control import Cancelled
from rmrb_engine.services.zaobao_service import ZaobaoService


def service(handler):
    return ZaobaoService(
        http=ZaobaoHttp(client=httpx.Client(transport=httpx.MockTransport(handler)), interval=0)
    )


def test_news_never_creates_files_and_new_session_forgets_everything(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    # Use the actual feed URL; neither constructor nor reading may touch disk.
    from rmrb_engine.site.zaobao import FEED_URL

    current = service(
        lambda r: httpx.Response(
            200,
            text=FEED if str(r.url) == FEED_URL else ARTICLE,
            headers={"content-type": "text/html"},
        )
    )
    current.refresh_feed(threading.Event())
    current.fetch_article("1234567", threading.Event())
    assert current.article("1234567")["cached"]
    assert all(
        block.get("local") is None for block in current.article("1234567")["article"]["blocks"]
    )
    current.reset()
    assert current.feed()["items"] == []
    assert current.feed()["nextPage"] == 2
    with pytest.raises(EngineError):
        current.article("1234567")
    current.close()
    fresh = service(lambda r: httpx.Response(500))
    assert fresh.feed()["items"] == []
    fresh.close()
    assert list(tmp_path.iterdir()) == []


def test_reset_during_request_prevents_old_result_returning():
    started, release = threading.Event(), threading.Event()

    def handler(request):
        started.set()
        release.wait(2)
        return httpx.Response(200, text=FEED, headers={"content-type": "text/html"})

    current = service(handler)
    errors = []

    def load():
        try:
            current.refresh_feed(threading.Event())
        except Cancelled:
            errors.append("cancelled")

    thread = threading.Thread(target=load)
    thread.start()
    assert started.wait(1)
    current.reset()
    release.set()
    thread.join(2)
    assert errors == ["cancelled"]
    assert current.feed()["items"] == []
    current.close()


def test_logs_are_byte_bounded_rotated_and_never_pollute_stdout(tmp_path, capsys):
    logger = configure_logging(tmp_path, max_bytes=256, backup_count=2)
    for i in range(100):
        logger.info("日志 %s %s", i, "中" * 80)
    paths = list(tmp_path.glob("engine.log*"))
    assert len(paths) <= 3
    assert all(p.stat().st_size <= 256 for p in paths)
    assert "99" in (tmp_path / "engine.log").read_text(encoding="utf-8")
    assert capsys.readouterr().out == ""


def test_exception_logs_include_stack_without_news_payload_or_credentials(tmp_path):
    configure_logging(tmp_path)
    try:
        raise ValueError("PRIVATE_ARTICLE_BODY password=SECRET")
    except ValueError as exc:
        log_exception("test.failure", exc)
    text = (tmp_path / "engine.log").read_text(encoding="utf-8")
    assert "ValueError" in text and "test_exception_logs" in text
    assert "PRIVATE_ARTICLE_BODY" not in text and "SECRET" not in text


def test_legacy_cleanup_removes_only_news_directory(tmp_path):
    from rmrb_engine.store.legacy_news import purge_legacy_news

    news = tmp_path / "zaobao" / "media"
    news.mkdir(parents=True)
    (news / "old.jpg").write_bytes(b"news")
    newspaper = tmp_path / "2026-10-30"
    newspaper.mkdir()
    (newspaper / "page.pdf").write_bytes(b"newspaper")
    backup = tmp_path / "state.db.v1.bak"
    backup.write_bytes(b"old backup")
    purge_legacy_news(tmp_path)
    purge_legacy_news(tmp_path)
    assert not (tmp_path / "zaobao").exists()
    assert (newspaper / "page.pdf").read_bytes() == b"newspaper"
    assert backup.read_bytes() == b"old backup"


def test_log_byte_budget_includes_windows_newline(tmp_path):
    import logging

    from rmrb_engine.diagnostics import ByteRotatingHandler

    handler = ByteRotatingHandler(
        tmp_path / "engine.log", maxBytes=64, backupCount=2, encoding="utf-8", delay=True
    )
    handler.setFormatter(logging.Formatter("%(message)s"))
    handler.emit(logging.LogRecord("test", logging.INFO, "", 0, "x" * 63, (), None))
    assert (tmp_path / "engine.log").stat().st_size <= 64
    handler.close()
