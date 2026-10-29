"""issue.parse 缓存：历史日期第二次调用零网络。"""

from __future__ import annotations

import io
import json
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
URL = f"{BASE}/pc/layout/202610/20/node_01.html"
HTML = f"""<html><body>
<div class="paper-bot"><p class="left ban">第01版：要闻</p>
<p class="right btn"><a href="{BASE}/pc/attachement/202610/20/p1.pdf">PDF</a></p></div>
<div class="paper"><img src="{BASE}/pc/pic/202610/20/t1.jpg.2"></div>
<div class="news"><ul></ul></div>
<p class="date left">人民日报 <span class="newstime">2026年10月20日 Tue</span></p>
<div class="swiper-slide"><a id="pageLink" href="node_01.html">01版：要闻</a></div>
<div class="swiper-slide"><a id="pageLink" href="node_02.html">02版：评论</a></div>
</body></html>"""


def build(tmp_path: Path) -> tuple[RpcServer, io.StringIO]:
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


@respx.mock
def test_second_parse_hits_cache(tmp_path: Path):
    route = respx.get(URL).mock(return_value=httpx.Response(200, text=HTML))
    server, out = build(tmp_path)

    server.handle(json.dumps({"id": 1, "method": "issue.parse", "params": {"date": "2026-10-20"}}))
    first = route.call_count
    server.handle(json.dumps({"id": 2, "method": "issue.parse", "params": {"date": "2026-10-20"}}))

    assert first == 1
    assert route.call_count == 1, "历史日期第二次解析不应再打网络"
    result = json.loads(out.getvalue().splitlines()[-1])["result"]
    assert result["pageCount"] == 2
    assert result["pages"][0]["thumbUrl"]
