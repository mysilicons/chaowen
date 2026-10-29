"""E-07 验收：单期下载编排。

用 respx 把整条链路（版面页 → 各版详情 → PDF）在本地跑通，不碰真实站点。
"""

from __future__ import annotations

import json
from datetime import date
from pathlib import Path

import httpx
import pytest
import respx

from rmrb_engine.core.paths import LibraryPaths
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
  <div class="paper-bot">
    <p class="left ban">第{no:02d}版：{title}</p>
    <p class="right btn"><a href="{pdf_url}" download="rmrb20261029{no:02d}.pdf">PDF下载</a></p>
  </div>
  <div class="news"><ul><li><a href="{BASE}/pc/content/202610/29/content_{no}.html">文章{no}</a></li></ul></div>
  <p class="date left">人民日报 <span class="newstime">2026年10月29日 Thu</span></p>
  {_nav()}
</body></html>"""


def make_service(tmp_path: Path, events: list[tuple[str, dict]]) -> DownloadService:
    http = HttpClient(
        client=httpx.Client(),
        limiter=TokenBucket(rate=1000, burst=1000, sleep=lambda _s: None),
        jitter=0.0,
        sleep=lambda _s: None,
    )
    repo = Repo(Database(tmp_path / "state.db"))
    paths = LibraryPaths(library=tmp_path / "lib", cache=tmp_path / "cache")
    return DownloadService(
        http, repo, paths, emit=lambda event, data: events.append((event, data))
    )


@respx.mock
def test_full_issue_download_and_merge(tmp_path: Path):
    events: list[tuple[str, dict]] = []
    respx.get(LAYOUT_URL).mock(
        return_value=httpx.Response(200, text=page_html(1, "要闻", PDF1))
    )
    respx.get(NODE2_URL).mock(
        return_value=httpx.Response(200, text=page_html(2, "评论", PDF2))
    )
    respx.get(PDF1).mock(return_value=httpx.Response(200, content=PDF_BYTES))
    respx.get(PDF2).mock(return_value=httpx.Response(200, content=PDF_BYTES))

    service = make_service(tmp_path, events)
    result = service.run_issue(D)

    assert result.done == 2
    assert result.failed == 0
    assert result.status == "archived"
    assert result.merged is not None and result.merged.exists()

    # 单版默认删除，下载目录只剩成品 + 清单
    assert not service.paths.tmp_dir(D).exists()
    assert service.paths.manifest(D).exists()

    manifest = json.loads(service.paths.manifest(D).read_text(encoding="utf-8"))
    assert manifest["pageCount"] == 2
    assert manifest["singlesDeleted"] is True
    assert [page["pageNo"] for page in manifest["pages"]] == [1, 2]

    archived = [event for event, _ in events if event == "issue.archived"]
    assert len(archived) == 1


@respx.mock
def test_single_page_failure_blocks_merge(tmp_path: Path):
    events: list[tuple[str, dict]] = []
    respx.get(LAYOUT_URL).mock(
        return_value=httpx.Response(200, text=page_html(1, "要闻", PDF1))
    )
    respx.get(NODE2_URL).mock(
        return_value=httpx.Response(200, text=page_html(2, "评论", PDF2))
    )
    respx.get(PDF1).mock(return_value=httpx.Response(200, content=PDF_BYTES))
    respx.get(PDF2).mock(return_value=httpx.Response(500))

    service = make_service(tmp_path, events)
    result = service.run_issue(D)

    assert result.done == 1
    assert result.failed == 1
    assert result.status == "partial"
    assert result.merged is None
    assert not service.paths.merged_pdf(D).exists()
    # 失败时不删单版，便于重试
    assert service.paths.single_pdf(D, 1).exists()

    record = service.repo.get_page(D, 2)
    assert record["status"] == "failed"
    assert record["error_code"] == "HTTP_ERROR"
    assert record["attempts"] == 1


@respx.mock
def test_second_run_is_noop(tmp_path: Path):
    events: list[tuple[str, dict]] = []
    layout = respx.get(LAYOUT_URL).mock(
        return_value=httpx.Response(200, text=page_html(1, "要闻", PDF1))
    )
    respx.get(NODE2_URL).mock(
        return_value=httpx.Response(200, text=page_html(2, "评论", PDF2))
    )
    pdf1 = respx.get(PDF1).mock(return_value=httpx.Response(200, content=PDF_BYTES))
    pdf2 = respx.get(PDF2).mock(return_value=httpx.Response(200, content=PDF_BYTES))

    service = make_service(tmp_path, events)
    first = service.run_issue(D)
    assert first.done == 2

    calls_before = (pdf1.call_count, pdf2.call_count)
    second = service.run_issue(D)

    assert second.skipped == 2
    assert second.status == "archived"
    assert (pdf1.call_count, pdf2.call_count) == calls_before
    assert layout.call_count == 2  # 每次都会重新取一次目录


@respx.mock
def test_dry_run_makes_no_pdf_requests(tmp_path: Path):
    events: list[tuple[str, dict]] = []
    respx.get(LAYOUT_URL).mock(
        return_value=httpx.Response(200, text=page_html(1, "要闻", PDF1))
    )
    pdf1 = respx.get(PDF1).mock(return_value=httpx.Response(200, content=PDF_BYTES))

    service = make_service(tmp_path, events)
    result = service.run_issue(D, dry_run=True)

    assert result.status == "planned"
    assert [page.status for page in result.pages] == ["planned", "planned"]
    assert pdf1.call_count == 0
    assert not service.paths.tmp_dir(D).exists()


@respx.mock
def test_subset_download_does_not_merge(tmp_path: Path):
    """只下部分版面时不能合并，否则会产出"残缺整期"。"""
    events: list[tuple[str, dict]] = []
    respx.get(LAYOUT_URL).mock(
        return_value=httpx.Response(200, text=page_html(1, "要闻", PDF1))
    )
    respx.get(PDF1).mock(return_value=httpx.Response(200, content=PDF_BYTES))

    service = make_service(tmp_path, events)
    result = service.run_issue(D, pages=[1])

    assert result.done == 1
    assert result.status == "partial"
    assert result.merged is None
    assert not service.paths.merged_pdf(D).exists()


@respx.mock
def test_no_issue_raises(tmp_path: Path):
    from rmrb_engine.core.errors import EngineError

    events: list[tuple[str, dict]] = []
    respx.get(LAYOUT_URL).mock(return_value=httpx.Response(404))

    service = make_service(tmp_path, events)
    with pytest.raises(EngineError):
        service.run_issue(D)
