"""E-09 验收：NDJSON 协议。

重点不是"能跑"，而是 **stdout 只含合法 JSON** —— 双进程方案最常见的事故是
某处 print 把流污染，客户端表现为随机解析失败。
"""

from __future__ import annotations

import io
import json
from datetime import date
from pathlib import Path
from typing import Any

import httpx
import respx

from rmrb_engine.api import Engine
from rmrb_engine.core.paths import LibraryPaths
from rmrb_engine.ipc import RpcServer
from rmrb_engine.net.client import HttpClient
from rmrb_engine.net.limiter import TokenBucket
from rmrb_engine.services.queue import DownloadService
from rmrb_engine.store.db import Database
from rmrb_engine.store.repo import Repo

ROOT = Path(__file__).resolve().parents[2]
PDF_BYTES = (ROOT / "_probe" / "p1.pdf").read_bytes()

BASE = "https://paper.people.com.cn/rmrb"
D = date(2026, 10, 29)
LAYOUT_URL = f"{BASE}/pc/layout/202610/29/node_01.html"
NODE2_URL = f"{BASE}/pc/layout/202610/29/node_02.html"
PDF1 = f"{BASE}/pc/attachement/202610/29/p1.pdf"
PDF2 = f"{BASE}/pc/attachement/202610/29/p2.pdf"
PAGES = [(1, "要闻"), (2, "评论")]


def _nav() -> str:
    return "".join(
        f'<div class="swiper-slide"><a id="pageLink" '
        f'href="{BASE}/pc/layout/202610/29/node_{no:02d}.html">{no:02d}版：{title}</a></div>'
        for no, title in PAGES
    )


def page_html(no: int, title: str, pdf_url: str) -> str:
    return f"""<html><body>
  <div class="paper"><img src="{BASE}/pc/pic/202610/29/t{no}.jpg.2"></div>
  <div class="paper-bot"><p class="left ban">第{no:02d}版：{title}</p>
    <p class="right btn"><a href="{pdf_url}" download="rmrb20261029{no:02d}.pdf">PDF下载</a></p></div>
  <div class="news"><ul><li><a href="{BASE}/pc/content/202610/29/content_{no}.html">文章{no}</a></li></ul></div>
  <p class="date left">人民日报 <span class="newstime">2026年10月29日 Thu</span></p>
  {_nav()}
</body></html>"""


def make_server(tmp_path: Path, lines: list[str]) -> tuple[RpcServer, io.StringIO]:
    http = HttpClient(
        client=httpx.Client(),
        limiter=TokenBucket(rate=1000, burst=1000, sleep=lambda _s: None),
        jitter=0.0,
        sleep=lambda _s: None,
    )
    repo = Repo(Database(tmp_path / "state.db"))
    paths = LibraryPaths(library=tmp_path / "lib", cache=tmp_path / "cache")
    engine = Engine(DownloadService(http, repo, paths), repo)
    out = io.StringIO()
    server = RpcServer(engine, iter(lines), out)
    return server, out


def run_lines(tmp_path: Path, lines: list[str]) -> list[dict[str, Any]]:
    server, out = make_server(tmp_path, lines)
    server.run()
    raw = out.getvalue()
    parsed = []
    for line in raw.splitlines():
        parsed.append(json.loads(line))  # 任何非 JSON 行都会在这里炸
    return parsed


def req(request_id: int, method: str, params: dict[str, Any] | None = None) -> str:
    body: dict[str, Any] = {"id": request_id, "method": method}
    if params is not None:
        body["params"] = params
    return json.dumps(body, ensure_ascii=False)


def test_hello(tmp_path: Path):
    messages = run_lines(tmp_path, [req(0, "hello", {"protocol": 1, "client": "test"})])

    assert len(messages) == 1
    assert messages[0]["id"] == 0
    assert messages[0]["ok"] is True
    assert messages[0]["result"]["protocol"] == 1
    assert messages[0]["result"]["engine"]


def test_unknown_method_keeps_process_alive(tmp_path: Path):
    messages = run_lines(
        tmp_path,
        [
            req(1, "no.such.method"),
            req(2, "hello", {}),
        ],
    )

    assert messages[0]["ok"] is False
    assert messages[0]["error"]["code"] == "UNKNOWN_METHOD"
    assert messages[1]["ok"] is True  # 进程没有退出


def test_bad_json_does_not_kill_process(tmp_path: Path):
    messages = run_lines(tmp_path, ["{not json", req(3, "hello", {})])

    assert messages[0]["ok"] is False
    assert messages[0]["error"]["code"] == "BAD_REQUEST"
    assert messages[0]["id"] is None
    assert messages[1]["ok"] is True


def test_missing_date_returns_bad_request(tmp_path: Path):
    messages = run_lines(tmp_path, [req(4, "issue.parse", {})])

    assert messages[0]["ok"] is False
    assert messages[0]["error"]["code"] == "BAD_REQUEST"


def test_oversized_line_is_rejected(tmp_path: Path):
    huge = json.dumps({"id": 5, "method": "hello", "params": {"x": "a" * (1024 * 1024 + 10)}})
    messages = run_lines(tmp_path, [huge])

    assert messages[0]["ok"] is False
    assert messages[0]["error"]["code"] == "BAD_REQUEST"


@respx.mock
def test_issue_parse_returns_protocol_shape(tmp_path: Path):
    respx.get(LAYOUT_URL).mock(
        return_value=httpx.Response(200, text=page_html(1, "要闻", PDF1))
    )

    messages = run_lines(tmp_path, [req(6, "issue.parse", {"date": "2026-10-29"})])

    assert messages[0]["ok"] is True
    result = messages[0]["result"]
    assert result["pageCount"] == 2
    assert result["pages"][0]["pdfUrl"] == PDF1
    assert result["pages"][0]["thumbUrl"].endswith(".jpg.2")


@respx.mock
def test_download_start_responds_before_events(tmp_path: Path):
    respx.get(LAYOUT_URL).mock(
        return_value=httpx.Response(200, text=page_html(1, "要闻", PDF1))
    )
    respx.get(NODE2_URL).mock(
        return_value=httpx.Response(200, text=page_html(2, "评论", PDF2))
    )
    respx.get(PDF1).mock(return_value=httpx.Response(200, content=PDF_BYTES))
    respx.get(PDF2).mock(return_value=httpx.Response(200, content=PDF_BYTES))

    messages = run_lines(tmp_path, [req(7, "download.start", {"date": "2026-10-29"})])

    # 第一条必须是回执，不能是事件
    assert "id" in messages[0] and "event" not in messages[0]
    assert messages[0]["ok"] is True
    job_id = messages[0]["result"]["jobId"]
    assert job_id

    events = [message for message in messages if "event" in message]
    names = [event["event"] for event in events]
    assert "download.progress" in names
    assert "issue.archived" in names
    assert names[-1] == "job.finished"
    assert all(event["data"]["jobId"] == job_id for event in events if "jobId" in event["data"])


@respx.mock
def test_every_output_line_is_valid_json(tmp_path: Path):
    """整条链路跑完，stdout 的每一行都必须能被 json.loads。"""
    respx.get(LAYOUT_URL).mock(
        return_value=httpx.Response(200, text=page_html(1, "要闻", PDF1))
    )
    respx.get(NODE2_URL).mock(
        return_value=httpx.Response(200, text=page_html(2, "评论", PDF2))
    )
    respx.get(PDF1).mock(return_value=httpx.Response(200, content=PDF_BYTES))
    respx.get(PDF2).mock(return_value=httpx.Response(200, content=PDF_BYTES))

    raw_messages = [
        req(8, "hello", {}),
        req(9, "issue.parse", {"date": "2026-10-29"}),
        req(10, "download.start", {"date": "2026-10-29"}),
        req(11, "issue.status", {"date": "2026-10-29"}),
    ]

    server, out = make_server(tmp_path, raw_messages)
    server.run()

    lines = [line for line in out.getvalue().splitlines() if line.strip()]
    assert len(lines) >= 6
    for line in lines:
        json.loads(line)

    status_lines = [
        json.loads(line) for line in lines if json.loads(line).get("id") == 11
    ]
    assert status_lines[0]["result"]["status"] == "archived"
