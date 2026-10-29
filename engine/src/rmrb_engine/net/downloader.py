"""流式下载：.part 临时文件 + Range 续传 + 原子改名 + 内容校验。

关键行为：
- 永远不直接写目标文件，避免出现半个正式文件；
- 校验失败（非 PDF / 体积过小）时删掉 .part，避免下次续传垃圾数据；
- 网络中断时保留 .part，下次可续。
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from ..core.errors import EngineError, ErrorCode
from .client import HttpClient

PDF_MAGIC = b"%PDF-"
MIN_BYTES = 50 * 1024
CHUNK_SIZE = 64 * 1024


@dataclass(slots=True)
class DownloadResult:
    path: Path
    bytes: int
    resumed: bool
    status: int


def download(
    http: HttpClient,
    url: str,
    dest: Path,
    *,
    min_bytes: int = MIN_BYTES,
    chunk_size: int = CHUNK_SIZE,
) -> DownloadResult:
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")

    start = part.stat().st_size if part.exists() else 0
    headers = {"Range": f"bytes={start}-"} if start > 0 else None
    resumed = False

    with http.stream(url, headers=headers) as response:
        if start > 0 and response.status_code == 206:
            mode = "ab"
            resumed = True
        elif response.status_code == 200:
            mode = "wb"
            start = 0
        else:
            raise EngineError(
                ErrorCode.HTTP_ERROR, f"HTTP {response.status_code}", detail=url
            )

        status = response.status_code
        with part.open(mode) as handle:
            for chunk in response.iter_bytes(chunk_size):
                if chunk:
                    handle.write(chunk)
            handle.flush()
            os.fsync(handle.fileno())

    size = part.stat().st_size
    if size < min_bytes:
        part.unlink(missing_ok=True)
        raise EngineError(
            ErrorCode.BAD_RESPONSE, f"文件过小（{size} B）", detail=url
        )
    if not _is_pdf(part):
        part.unlink(missing_ok=True)
        raise EngineError(ErrorCode.BAD_RESPONSE, "响应不是 PDF", detail=url)

    os.replace(part, dest)
    return DownloadResult(path=dest, bytes=size, resumed=resumed, status=status)


def _is_pdf(path: Path) -> bool:
    with path.open("rb") as handle:
        return handle.read(len(PDF_MAGIC)) == PDF_MAGIC
