"""下载任务控制（暂停 / 继续 / 取消）验收。

关键点：download.start 立即返回，任务在工作线程里跑；
pause 之后不能再有新请求，resume 恢复，cancel 让任务提前收尾。
"""

from __future__ import annotations

import io
import json
import time
from pathlib import Path

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

BASE = "https://paper.people.com.cn/rmrb"
LAYOUT = f"{BASE}/pc/layout/202610/29/node_01.html"
NODES = [f"{BASE}/pc/layout/202610/29/node_{n:02d}.html" for n in (2, 3, 4)]
PDFS = [f"{BASE}/pc/attachement/202610/29/p{n}.pdf" for n in (1, 2, 3, 4)]
PDF_BYTES = (Path(__file__).resolve().parents[2] / "_probe" / "p1.pdf").read_bytes()


def page_html(no: int, title: str, pdf: str, total: int = 4) -> str:
    nav = "".join(
        f'<div class="swiper-slide"><a id="pageLink" '
        f'href="{BASE}/pc/layout/202610/29/node_{n:02d}.html">'
        f"{n:02d}版：{'要闻' if n == 1 else '评论'}</a></div>"
        for n in range(1, total + 1)
    )
    return f"""<html><body>
  <div class="paper"><img src="{BASE}/pc/pic/202610/29/t{no}.jpg.2"></div>
  <div class="paper-bot"><p class="left ban">第{no:02d}版：{title}</p>
    <p class="right btn"><a href="{pdf}" download="rmrb20261029{no:02d}.pdf">PDF下载</a></p></div>
  <div class="news"><ul><li><a href="{BASE}/pc/content/1.html">文章</a></li></ul></div>
  <p class="date left">人民日报 <span class="newstime">2026年10月29日 Thu</span></p>
  {nav}
</body></html>"""


def make(tmp_path: Path) -> tuple[RpcServer, io.StringIO]:
    repo = Repo(Database(tmp_path / "s.db"))
    http = HttpClient(
        client=httpx.Client(),
        limiter=TokenBucket(rate=1000, burst=1000, sleep=lambda _s: None),
        jitter=0.0,
        sleep=lambda _s: None,
    )
    engine = Engine(DownloadService(http, repo, LibraryPaths(tmp_path / "l", tmp_path / "c")), repo)
    out = io.StringIO()
    return RpcServer(engine, iter([]), out), out


def send(server: RpcServer, out: io.StringIO, method: str, params: dict | None = None) -> dict:
    payload = {"id": 1, "method": method}
    if params is not None:
        payload["params"] = params
    server.handle(json.dumps(payload))
    for line in reversed(out.getvalue().splitlines()):
        data = json.loads(line)
        if "id" in data:
            return data
    raise AssertionError("没有响应")


def wait_for(out: io.StringIO, needle: str, timeout: float = 8.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if needle in out.getvalue():
            return
        time.sleep(0.05)
    raise AssertionError(f"等待超时：{needle}")


@respx.mock
def test_cancel_stops_before_all_pages(tmp_path: Path):
    respx.get(LAYOUT).mock(return_value=httpx.Response(200, text=page_html(1, "要闻", PDFS[0])))
    for node, no in zip(NODES, (2, 3, 4), strict=True):
        respx.get(node).mock(
            return_value=httpx.Response(200, text=page_html(no, "评论", PDFS[no - 1]))
        )
    for pdf in PDFS:
        respx.get(pdf).mock(return_value=httpx.Response(200, content=PDF_BYTES))

    server, out = make(tmp_path)
    reply = send(server, out, "download.start", {"date": "2026-10-29"})
    job_id = reply["result"]["jobId"]

    cancel = send(server, out, "download.cancel", {"jobId": job_id})
    assert cancel["ok"] is True
    wait_for(out, '"cancelled": true')

    # 取消后不应产出合并文件
    assert not (tmp_path / "l" / "2026" / "2026-10-29").exists()


@respx.mock
def test_pause_blocks_new_requests(tmp_path: Path):
    respx.get(LAYOUT).mock(return_value=httpx.Response(200, text=page_html(1, "要闻", PDFS[0])))
    for node, no in zip(NODES, (2, 3, 4), strict=True):
        respx.get(node).mock(
            return_value=httpx.Response(200, text=page_html(no, "评论", PDFS[no - 1]))
        )
    pdf1 = respx.get(PDFS[0]).mock(return_value=httpx.Response(200, content=PDF_BYTES))
    for pdf in PDFS[1:]:
        respx.get(pdf).mock(return_value=httpx.Response(200, content=PDF_BYTES))

    server, out = make(tmp_path)
    reply = send(server, out, "download.start", {"date": "2026-10-29"})
    job_id = reply["result"]["jobId"]

    assert send(server, out, "download.pause", {"jobId": job_id})["ok"] is True
    time.sleep(0.4)
    before = pdf1.call_count

    # 暂停期间不应再有新的 PDF 请求
    time.sleep(0.5)
    assert pdf1.call_count == before

    assert send(server, out, "download.resume", {"jobId": job_id})["ok"] is True
    wait_for(out, '"ok": true, "failed": 0', timeout=10)


@respx.mock
def test_control_unknown_job_is_rejected(tmp_path: Path):
    server, out = make(tmp_path)

    reply = send(server, out, "download.pause", {"jobId": "nope"})

    assert reply["ok"] is False
    assert reply["error"]["code"] == "BAD_REQUEST"
