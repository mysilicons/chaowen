"""合并整期 PDF。

合并必须在「页数正确 + 可重新打开」之后才原子替换目标文件，
否则宁可保留单版，也不能产出一个坏掉的存档。
"""

from __future__ import annotations

import logging
import os
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date as Date
from pathlib import Path

from pypdf import PdfReader, PdfWriter

from ..core.errors import EngineError, ErrorCode

# pypdf 对"字体字典重复定义"会刷大量 WARNING（人民日报 PDF 里很常见但不影响解析），
# 这些噪音会淹没我们自己的日志，统一压到 ERROR。
logging.getLogger("pypdf").setLevel(logging.ERROR)


@dataclass(slots=True)
class MergeResult:
    path: Path
    pages: int
    bytes: int


def merge_issue(
    singles: Sequence[Path],
    titles: Sequence[str],
    out: Path,
    *,
    issue_date: Date,
) -> MergeResult:
    if not singles:
        raise EngineError(ErrorCode.MERGE_FAILED, "没有可合并的版面")
    if len(singles) != len(titles):
        raise EngineError(
            ErrorCode.MERGE_FAILED,
            "版面与标题数量不一致",
            detail=f"{len(singles)} != {len(titles)}",
        )

    writer = PdfWriter()
    try:
        for single in singles:
            writer.append(str(single))
    except Exception as exc:  # pypdf 抛的异常类型很杂
        raise EngineError(ErrorCode.MERGE_FAILED, "合并失败", detail=str(exc)) from exc

    for index, title in enumerate(titles, start=1):
        writer.add_outline_item(f"第{index:02d}版 {title}", index - 1)

    writer.add_metadata(
        {
            "/Title": f"人民日报 {issue_date.isoformat()}",
            "/Author": "人民日报",
            "/Subject": f"人民日报电子版 {issue_date.isoformat()}",
        }
    )

    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + ".tmp")
    try:
        with tmp.open("wb") as handle:
            writer.write(handle)
        verify_pdf(tmp, expected_pages=len(singles))
    except EngineError:
        tmp.unlink(missing_ok=True)
        raise
    except Exception as exc:
        tmp.unlink(missing_ok=True)
        raise EngineError(ErrorCode.MERGE_FAILED, "写入失败", detail=str(exc)) from exc

    os.replace(tmp, out)
    return MergeResult(path=out, pages=len(singles), bytes=out.stat().st_size)


def verify_pdf(path: Path, *, expected_pages: int | None = None) -> int:
    """打开并检查页数/尺寸；任何异常都转成 MERGE_FAILED。"""
    path = Path(path)
    try:
        reader = PdfReader(str(path), strict=False)
        count = len(reader.pages)
        if expected_pages is not None and count != expected_pages:
            raise EngineError(
                ErrorCode.MERGE_FAILED,
                "合并后页数不符",
                detail=f"{count} != {expected_pages}",
            )
        if count == 0:
            raise EngineError(ErrorCode.MERGE_FAILED, "合并结果是空文档")

        first = reader.pages[0].mediabox
        if float(first.width) < 100 or float(first.height) < 100:
            raise EngineError(
                ErrorCode.MERGE_FAILED,
                "页面尺寸异常",
                detail=f"{first.width}x{first.height}",
            )
        reader.pages[-1]  # 末页也必须可读
    except EngineError:
        raise
    except Exception as exc:
        raise EngineError(ErrorCode.MERGE_FAILED, "PDF 校验失败", detail=str(exc)) from exc

    return count
