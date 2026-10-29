"""issue.parse 用库内已解析结果补齐缩略图与 PDF 直链。

版面列表只带当前页的图片地址；如果不补齐，书架里其余 19 版全是空白占位。
补齐走 SQLite（0 请求），而不是再抓 20 个页面 —— 低速约束下这是关键差别。
"""

from __future__ import annotations

import io
import json
from datetime import date
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
D = date(2026, 10, 29)
LAYOUT_URL = f"{BASE}/pc/layout/202610/29/node_01.html"

LAYOUT_HTML = f"""<html><body>
  <div class="paper"><img src="{BASE}/pc/pic/202610/29/t1.jpg.2"></div>
  <div class="paper-bot"><p class="left ban">第01版：要闻</p>
    <p class="right btn"><a href="{BASE}/pc/attachement/202610/29/p1.pdf">PDF下载</a></p></div>
  <div class="news"><ul></ul></div>
  <p class="date left">人民日报 <span class="newstime">2026年10月29日 Thu</span></p>
  <div class="swiper-slide"><a id="pageLink" href="{BASE}/pc/layout/202610/29/node_01.html">01版：要闻</a></div>
  <div class="swiper-slide"><a id="pageLink" href="{BASE}/pc/layout/202610/29/node_02.html">02版：评论</a></div>
  <div class="swiper-slide"><a id="pageLink" href="{BASE}/pc/layout/202610/29/node_03.html">03版：国际</a></div>
</body></html>"""


def build(tmp_path: Path) -> tuple[RpcServer, io.StringIO, Repo]:
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
    return RpcServer(engine, iter([]), out), out, repo


def parse(server: RpcServer, out: io.StringIO) -> dict:
    server.handle(json.dumps({"id": 1, "method": "issue.parse", "params": {"date": D.isoformat()}}))
    return json.loads(out.getvalue().splitlines()[-1])


@respx.mock
def test_thumbs_filled_from_database(tmp_path: Path):
    respx.get(LAYOUT_URL).mock(return_value=httpx.Response(200, text=LAYOUT_HTML))
    server, out, repo = build(tmp_path)

    # 模拟下载过一期：第 2、3 版的图与直链已经入库
    repo.save_page(D, 2, status="done", title="评论", thumb_url="https://x/t2.jpg.2")
    repo.save_page(D, 3, status="done", title="国际", thumb_url="https://x/t3.jpg.2")

    response = parse(server, out)

    pages = {page["no"]: page for page in response["result"]["pages"]}
    assert pages[1]["thumbUrl"].endswith("t1.jpg.2")  # 来自版面列表
    assert pages[2]["thumbUrl"] == "https://x/t2.jpg.2"  # 来自数据库
    assert pages[3]["thumbUrl"] == "https://x/t3.jpg.2"
    assert all(page["thumbUrl"] for page in pages.values())


@respx.mock
def test_unknown_pages_stay_null(tmp_path: Path):
    respx.get(LAYOUT_URL).mock(return_value=httpx.Response(200, text=LAYOUT_HTML))
    server, out, _ = build(tmp_path)

    response = parse(server, out)

    pages = {page["no"]: page for page in response["result"]["pages"]}
    assert pages[1]["thumbUrl"] is not None
    assert pages[2]["thumbUrl"] is None
