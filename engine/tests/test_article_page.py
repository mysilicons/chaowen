"""E-10 / E-11 验收：文字模式抓取、图片本地化、版型判定、缓存。"""

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
from rmrb_engine.services.classify import classify
from rmrb_engine.services.queue import DownloadService
from rmrb_engine.store.db import Database
from rmrb_engine.store.repo import Repo

BASE = "https://paper.people.com.cn/rmrb"
D = date(2026, 10, 29)
NODE = f"{BASE}/pc/layout/202610/29/node_03.html"
C1 = f"{BASE}/pc/content/202610/29/content_1.html"
C2 = f"{BASE}/pc/content/202610/29/content_2.html"
IMG = f"{BASE}/pc/pic/202610/29/pic.jpg"

NODE_HTML = f"""<html><body>
  <div class="paper"><img src="{BASE}/pc/pic/202610/29/t3.jpg.2"></div>
  <div class="paper-bot"><p class="left ban">第03版：国际</p>
    <p class="right btn"><a href="{BASE}/pc/attachement/202610/29/p3.pdf">PDF下载</a></p></div>
  <div class="news"><ul>
    <li><a href="{C1}">文章一</a></li>
    <li><a href="{C2}">文章二</a></li>
  </ul></div>
  <p class="date left">人民日报 <span class="newstime">2026年10月29日 Thu</span></p>
</body></html>"""


def content_html(title: str, body: str, with_image: bool = False) -> str:
    img = f'<p><img src="{IMG}"></p>' if with_image else ""
    return f"""<html><body><div class="article">
  <h1><p>{title}</p></h1>
  <p class="sec"></p>
  <!--enpcontent-->{img}{body}<!--/enpcontent-->
  <!--enpproperty <author>本报记者 张三</author><subtitle></subtitle>--></div></body></html>"""


def build(tmp_path: Path) -> tuple[RpcServer, io.StringIO]:
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
    return RpcServer(engine, iter([]), out), out


def rpc(server: RpcServer, out: io.StringIO, method: str, params: dict) -> dict:
    server.handle(json.dumps({"id": 1, "method": method, "params": params}))
    return json.loads(out.getvalue().splitlines()[-1])


@respx.mock
def test_article_page_returns_blocks_with_local_images(tmp_path: Path):
    respx.get(NODE).mock(return_value=httpx.Response(200, text=NODE_HTML))
    respx.get(C1).mock(
        return_value=httpx.Response(200, text=content_html("标题一", "<p>　　" + "正" * 80 + "</p>"))
    )
    respx.get(C2).mock(
        return_value=httpx.Response(200, text=content_html("标题二", "<p>" + "文" * 80 + "</p>", with_image=True))
    )
    respx.get(IMG).mock(return_value=httpx.Response(200, content=b"\xff\xd8\xff fake jpeg"))

    server, out = build(tmp_path)
    response = rpc(server, out, "article.page", {"date": D.isoformat(), "pageNo": 3})

    assert response["ok"] is True
    result = response["result"]
    assert result["kind"] == "normal"
    assert result["title"] == "国际"
    assert len(result["articles"]) == 2

    second = result["articles"][1]
    image_block = next(block for block in second["blocks"] if block["type"] == "img")
    assert image_block["src"] == IMG
    assert image_block["local"] is not None
    assert Path(image_block["local"]).exists()


@respx.mock
def test_second_call_hits_cache(tmp_path: Path):
    node = respx.get(NODE).mock(return_value=httpx.Response(200, text=NODE_HTML))
    c1 = respx.get(C1).mock(
        return_value=httpx.Response(200, text=content_html("标题一", "<p>正文内容足够长以通过版型判定。</p>"))
    )
    respx.get(C2).mock(
        return_value=httpx.Response(200, text=content_html("标题二", "<p>另一段正文内容。</p>"))
    )

    server, out = build(tmp_path)
    rpc(server, out, "article.page", {"date": D.isoformat(), "pageNo": 3})
    calls = (node.call_count, c1.call_count)

    rpc(server, out, "article.page", {"date": D.isoformat(), "pageNo": 3})

    assert (node.call_count, c1.call_count) == calls  # 二次 0 请求


@respx.mock
def test_refresh_bypasses_cache(tmp_path: Path):
    node = respx.get(NODE).mock(return_value=httpx.Response(200, text=NODE_HTML))
    respx.get(C1).mock(return_value=httpx.Response(200, text=content_html("标题一", "<p>正文内容。</p>")))
    respx.get(C2).mock(return_value=httpx.Response(200, text=content_html("标题二", "<p>正文内容。</p>")))

    server, out = build(tmp_path)
    rpc(server, out, "article.page", {"date": D.isoformat(), "pageNo": 3})
    before = node.call_count

    rpc(server, out, "article.page", {"date": D.isoformat(), "pageNo": 3, "refresh": True})

    assert node.call_count == before + 1


@respx.mock
def test_bad_page_no_rejected(tmp_path: Path):
    server, out = build(tmp_path)

    response = rpc(server, out, "article.page", {"date": D.isoformat(), "pageNo": 99})

    assert response["ok"] is False
    assert response["error"]["code"] == "BAD_REQUEST"


def test_classify_kinds():
    from rmrb_engine.core.models import Article, Block, PageKind

    empty = classify([])
    assert empty == PageKind.EMPTY

    image_only = classify(
        [Article(title="图片报道", url="u", blocks=[Block.image("s"), Block.paragraph("图为某某。")])]
    )
    assert image_only == PageKind.IMAGE_ONLY

    single = classify(
        [Article(title="t", url="u", blocks=[Block.paragraph("字" * 100)])]
    )
    assert single == PageKind.SINGLE

    normal = classify(
        [
            Article(title="t1", url="u1", blocks=[Block.paragraph("字" * 80)]),
            Article(title="t2", url="u2", blocks=[Block.paragraph("字" * 80)]),
        ]
    )
    assert normal == PageKind.NORMAL
