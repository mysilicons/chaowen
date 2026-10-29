"""library.month 方法验收。"""

from __future__ import annotations

import io
import json
from datetime import date
from pathlib import Path

from rmrb_engine.api import Engine
from rmrb_engine.core.paths import LibraryPaths
from rmrb_engine.ipc import RpcServer
from rmrb_engine.net.client import HttpClient
from rmrb_engine.net.limiter import TokenBucket
from rmrb_engine.services.queue import DownloadService
from rmrb_engine.store.db import Database
from rmrb_engine.store.repo import Repo


def make_server(tmp_path: Path, lines: list[str]) -> tuple[RpcServer, io.StringIO]:
    import httpx

    db = Database(tmp_path / "state.db")
    repo = Repo(db)
    http = HttpClient(
        client=httpx.Client(),
        limiter=TokenBucket(rate=1000, burst=1000, sleep=lambda _s: None),
        jitter=0.0,
        sleep=lambda _s: None,
    )
    paths = LibraryPaths(library=tmp_path / "lib", cache=tmp_path / "cache")
    engine = Engine(DownloadService(http, repo, paths), repo)
    out = io.StringIO()
    return RpcServer(engine, iter(lines), out), out


def send(server: RpcServer, out: io.StringIO, request_id: int, method: str, params: dict) -> dict:
    server.handle(json.dumps({"id": request_id, "method": method, "params": params}))
    last = out.getvalue().splitlines()[-1]
    return json.loads(last)


def test_library_month_returns_archived_days(tmp_path: Path):
    server, out = make_server(tmp_path, [])
    repo = server.engine.repo
    repo.save_issue(date(2026, 10, 1), page_count=8, status="archived", size=100)
    repo.save_issue(date(2026, 10, 29), page_count=20, status="archived", size=200)
    repo.save_issue(date(2026, 9, 30), page_count=20, status="archived", size=300)

    response = send(server, out, 1, "library.month", {"year": 2026, "month": 10})

    assert response["ok"] is True
    rows = response["result"]
    assert [row["date"] for row in rows] == ["2026-10-01", "2026-10-29"]
    assert rows[0]["pageCount"] == 8
    assert rows[1]["bytes"] == 200


def test_library_month_rejects_bad_params(tmp_path: Path):
    server, out = make_server(tmp_path, [])

    response = send(server, out, 2, "library.month", {"year": 2026, "month": 13})

    assert response["ok"] is False
    assert response["error"]["code"] == "BAD_REQUEST"
