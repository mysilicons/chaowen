"""批量下载（batch.start）验收。"""

from __future__ import annotations

import io
import json
from pathlib import Path

import httpx

from rmrb_engine.api import Engine
from rmrb_engine.core.paths import LibraryPaths
from rmrb_engine.ipc import RpcServer
from rmrb_engine.net.client import HttpClient
from rmrb_engine.net.limiter import TokenBucket
from rmrb_engine.services.queue import DownloadService
from rmrb_engine.store.db import Database
from rmrb_engine.store.repo import Repo


def build(tmp_path: Path) -> tuple[RpcServer, io.StringIO]:
    repo = Repo(Database(tmp_path / "state.db"))
    http = HttpClient(
        client=httpx.Client(),
        limiter=TokenBucket(rate=1000, burst=1000, sleep=lambda _s: None),
        jitter=0.0,
        sleep=lambda _s: None,
    )
    paths = LibraryPaths(library=tmp_path / "lib", cache=tmp_path / "cache")
    engine = Engine(DownloadService(http, repo, paths), repo)
    out = io.StringIO()
    return RpcServer(engine, iter([]), out), out


def test_batch_loops_every_day(tmp_path: Path):
    server, out = build(tmp_path)
    visited: list[str] = []
    server.engine.service.run_issue = lambda d, **kw: visited.append(d.isoformat()) or None  # type: ignore[method-assign]

    server.handle(
        json.dumps(
            {
                "id": 1,
                "method": "batch.start",
                "params": {"from": "2026-10-01", "to": "2026-10-03"},
            }
        )
    )

    lines = [json.loads(line) for line in out.getvalue().splitlines()]
    assert lines[0]["ok"] is True
    assert lines[0]["result"]["days"] == 3
    assert lines[0]["result"]["jobId"].startswith("batch-20261001-")

    assert visited == ["2026-10-01", "2026-10-02", "2026-10-03"]
    events = [line["event"] for line in lines if "event" in line]
    assert events.count("batch.progress") == 3
    assert events[-1] == "job.finished"


def test_batch_rejects_reversed_range(tmp_path: Path):
    server, out = build(tmp_path)

    server.handle(
        json.dumps(
            {
                "id": 2,
                "method": "batch.start",
                "params": {"from": "2026-10-05", "to": "2026-10-01"},
            }
        )
    )

    response = json.loads(out.getvalue().splitlines()[-1])
    assert response["ok"] is False
    assert response["error"]["code"] == "BAD_REQUEST"


def test_batch_continues_after_one_day_fails(tmp_path: Path):
    server, out = build(tmp_path)
    from rmrb_engine.core.errors import EngineError, ErrorCode

    visited: list[str] = []

    def fake(d, **kw):
        visited.append(d.isoformat())
        if d.isoformat() == "2026-10-02":
            raise EngineError(ErrorCode.NO_ISSUE, "no paper")

    server.engine.service.run_issue = fake  # type: ignore[method-assign]

    server.handle(
        json.dumps(
            {
                "id": 3,
                "method": "batch.start",
                "params": {"from": "2026-10-01", "to": "2026-10-03"},
            }
        )
    )

    lines = [json.loads(line) for line in out.getvalue().splitlines()]
    events = [line for line in lines if "event" in line]
    day_errors = [e for e in events if e["event"] == "batch.day"]
    assert len(day_errors) == 1
    assert day_errors[0]["data"]["date"] == "2026-10-02"
    assert visited == ["2026-10-01", "2026-10-02", "2026-10-03"]
    assert events[-1]["event"] == "job.finished"
