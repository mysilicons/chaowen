"""E-05 验收：下载器（续传、原子写、内容校验）。"""

from __future__ import annotations

from pathlib import Path

import httpx
import pytest
import respx

from rmrb_engine.core.errors import EngineError, ErrorCode
from rmrb_engine.net.client import HttpClient
from rmrb_engine.net.downloader import download
from rmrb_engine.net.limiter import TokenBucket

URL = "https://example.test/a.pdf"
PDF_BODY = b"%PDF-1.4\n" + b"0" * 4096


def make_client() -> HttpClient:
    limiter = TokenBucket(rate=1000, burst=1000, sleep=lambda _s: None)
    return HttpClient(client=httpx.Client(), limiter=limiter, jitter=0.0, sleep=lambda _s: None)


def test_download_writes_file_atomically(tmp_path: Path):
    dest = tmp_path / "out" / "01.pdf"

    with respx.mock:
        respx.get(URL).mock(return_value=httpx.Response(200, content=PDF_BODY))
        result = download(make_client(), URL, dest, min_bytes=1024)

    assert result.path == dest
    assert result.bytes == len(PDF_BODY)
    assert result.resumed is False
    assert dest.read_bytes() == PDF_BODY
    assert not dest.with_name(dest.name + ".part").exists()


def test_resume_uses_range_header(tmp_path: Path):
    dest = tmp_path / "01.pdf"
    part = tmp_path / "01.pdf.part"
    part.write_bytes(PDF_BODY[:2000])

    with respx.mock:
        route = respx.get(URL).mock(
            return_value=httpx.Response(
                206,
                content=PDF_BODY[2000:],
                headers={"Content-Range": f"bytes 2000-{len(PDF_BODY) - 1}/{len(PDF_BODY)}"},
            )
        )
        result = download(make_client(), URL, dest, min_bytes=1024)

    assert route.calls[0].request.headers["range"] == "bytes=2000-"
    assert result.resumed is True
    assert dest.read_bytes() == PDF_BODY


def test_server_ignoring_range_restarts_from_scratch(tmp_path: Path):
    dest = tmp_path / "01.pdf"
    part = tmp_path / "01.pdf.part"
    part.write_bytes(b"garbage")

    with respx.mock:
        respx.get(URL).mock(return_value=httpx.Response(200, content=PDF_BODY))
        result = download(make_client(), URL, dest, min_bytes=1024)

    assert result.resumed is False
    assert dest.read_bytes() == PDF_BODY


def test_non_pdf_response_is_rejected(tmp_path: Path):
    dest = tmp_path / "01.pdf"

    with respx.mock:
        respx.get(URL).mock(
            return_value=httpx.Response(200, content=b"<html>" + b"x" * 4096)
        )
        with pytest.raises(EngineError) as exc:
            download(make_client(), URL, dest, min_bytes=1024)

    assert exc.value.code == ErrorCode.BAD_RESPONSE
    assert not dest.exists()
    # 垃圾内容不能留着污染下一次续传
    assert not dest.with_name(dest.name + ".part").exists()


def test_truncated_response_is_rejected(tmp_path: Path):
    dest = tmp_path / "01.pdf"

    with respx.mock:
        respx.get(URL).mock(return_value=httpx.Response(200, content=b"%PDF-1.4\n"))
        with pytest.raises(EngineError) as exc:
            download(make_client(), URL, dest, min_bytes=1024)

    assert exc.value.code == ErrorCode.BAD_RESPONSE
    assert not dest.exists()


def test_interruption_keeps_part_and_leaves_no_target(tmp_path: Path):
    dest = tmp_path / "01.pdf"

    def broken_stream():
        yield b"%PDF-1.4\n" + b"a" * 512
        raise httpx.ReadError("connection dropped")

    with respx.mock:
        respx.get(URL).mock(return_value=httpx.Response(200, content=broken_stream()))
        with pytest.raises(EngineError):
            download(make_client(), URL, dest, min_bytes=1024)

    assert not dest.exists()
    part = dest.with_name(dest.name + ".part")
    assert part.exists()
    # 流式写入被杀断时缓冲区可能未落盘，只要求"有残留、且不是完整文件"
    assert part.stat().st_size < len(PDF_BODY)
