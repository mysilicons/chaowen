import io
import json
import threading
import time

from rmrb_engine.api import Engine
from rmrb_engine.core.paths import LibraryPaths
from rmrb_engine.ipc import RpcServer
from rmrb_engine.net.client import HttpClient
from rmrb_engine.services.queue import DownloadService
from rmrb_engine.store.db import Database
from rmrb_engine.store.repo import Repo


def make_server(tmp_path):
    repo = Repo(Database(tmp_path / "state.db"))
    engine = Engine(
        DownloadService(
            HttpClient(), repo, LibraryPaths(library=tmp_path / "lib", cache=tmp_path / "cache")
        ),
        repo,
    )
    out = io.StringIO()
    return engine, RpcServer(engine, [], out), out


def call(server, method, params=None, identity=1):
    server.handle(json.dumps({"id": identity, "method": method, "params": params or {}}))


def test_task_ack_precedes_events_and_other_rpc_stays_responsive(tmp_path):
    engine, server, out = make_server(tmp_path)
    started = threading.Event()
    release = threading.Event()

    def refresh(cancel):
        started.set()
        release.wait(2)

    engine.zaobao.service.refresh_feed = refresh
    call(server, "zaobao.feed.refresh")
    assert started.wait(1)
    call(server, "hello", identity=2)
    messages = [json.loads(line) for line in out.getvalue().splitlines()]
    assert messages[0]["id"] == 1 and messages[0]["ok"]
    assert any(m.get("id") == 2 and m["result"]["features"]["zaobaoReaderV1"] for m in messages)
    job = messages[0]["result"]["jobId"]
    call(server, "zaobao.feed.refresh", identity=3)
    messages = [json.loads(line) for line in out.getvalue().splitlines()]
    assert next(m for m in messages if m.get("id") == 3)["result"]["jobId"] == job
    release.set()
    engine.zaobao.close()
    assert any(
        json.loads(line).get("data", {}).get("state") == "succeeded"
        for line in out.getvalue().splitlines()
    )


def test_cancel_and_failure_have_queryable_terminal_state(tmp_path):
    engine, server, out = make_server(tmp_path)

    def refresh(cancel):
        cancel.wait(2)
        from rmrb_engine.net.zaobao import check_cancel

        check_cancel(cancel)

    engine.zaobao.service.refresh_feed = refresh
    call(server, "zaobao.feed.refresh")
    job = json.loads(out.getvalue().splitlines()[0])["result"]["jobId"]
    call(server, "zaobao.task.cancel", {"jobId": job}, 2)
    for _ in range(100):
        if engine.zaobao.task(job)["state"] == "cancelled":
            break
        time.sleep(0.01)
    assert engine.zaobao.task(job)["state"] == "cancelled"
    call(server, "zaobao.article.fetch", {"articleId": "https://localhost"}, 3)
    last = json.loads(out.getvalue().splitlines()[-1])
    assert last["ok"] is False and last["error"]["code"] == "BAD_REQUEST"
    engine.zaobao.close()


def test_cancelled_inflight_target_can_be_queued_again(tmp_path):
    engine, server, out = make_server(tmp_path)
    started = threading.Event()
    release = threading.Event()

    def refresh(cancel):
        started.set()
        release.wait(2)
        from rmrb_engine.net.zaobao import check_cancel

        check_cancel(cancel)

    engine.zaobao.service.refresh_feed = refresh
    call(server, "zaobao.feed.refresh")
    first = json.loads(out.getvalue().splitlines()[0])["result"]["jobId"]
    assert started.wait(1)
    call(server, "zaobao.task.cancel", {"jobId": first}, 2)
    call(server, "zaobao.feed.refresh", identity=3)
    messages = [json.loads(line) for line in out.getvalue().splitlines()]
    second = next(m for m in messages if m.get("id") == 3)["result"]["jobId"]
    assert second != first
    release.set()
    engine.zaobao.close()
