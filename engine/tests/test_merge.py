"""E-08 验收：合并与校验。"""

from __future__ import annotations

import shutil
from datetime import date
from pathlib import Path

import pytest
from pypdf import PdfReader

from rmrb_engine.core.errors import EngineError, ErrorCode
from rmrb_engine.services.merge import merge_issue, verify_pdf

ROOT = Path(__file__).resolve().parents[2]
SINGLE = ROOT / "_probe" / "p1.pdf"
D = date(2026, 10, 29)


@pytest.fixture
def singles(tmp_path: Path) -> list[Path]:
    paths = []
    for index in range(1, 4):
        target = tmp_path / f"{index:02d}.pdf"
        shutil.copyfile(SINGLE, target)
        paths.append(target)
    return paths


def test_merge_page_count_and_order(tmp_path: Path, singles: list[Path]):
    out = tmp_path / "人民日报_2026-10-29.pdf"
    result = merge_issue(singles, ["要闻", "评论", "国际"], out, issue_date=D)

    assert result.pages == 3
    assert out.exists()
    assert result.bytes == out.stat().st_size
    assert len(PdfReader(str(out)).pages) == 3


def test_merge_writes_bookmarks(tmp_path: Path, singles: list[Path]):
    out = tmp_path / "merged.pdf"
    merge_issue(singles, ["要闻", "评论", "国际"], out, issue_date=D)

    outline = PdfReader(str(out)).outline
    assert len(outline) == 3
    titles = [item.title for item in outline]
    assert titles == ["第01版 要闻", "第02版 评论", "第03版 国际"]


def test_merge_writes_metadata(tmp_path: Path, singles: list[Path]):
    out = tmp_path / "merged.pdf"
    merge_issue(singles, ["要闻", "评论", "国际"], out, issue_date=D)

    meta = PdfReader(str(out)).metadata
    assert meta["/Title"] == "人民日报 2026-10-29"
    assert meta["/Author"] == "人民日报"


def test_no_tmp_left_behind(tmp_path: Path, singles: list[Path]):
    out = tmp_path / "merged.pdf"
    merge_issue(singles, ["要闻", "评论", "国际"], out, issue_date=D)

    assert not (tmp_path / "merged.pdf.tmp").exists()


def test_corrupt_single_raises_and_keeps_previous_output(tmp_path: Path, singles: list[Path]):
    out = tmp_path / "merged.pdf"
    out.write_bytes(b"previous-good-file")

    singles[1].write_bytes(b"not a pdf at all")

    with pytest.raises(EngineError) as exc:
        merge_issue(singles, ["要闻", "评论", "国际"], out, issue_date=D)

    assert exc.value.code == ErrorCode.MERGE_FAILED
    assert out.read_bytes() == b"previous-good-file"
    assert not (tmp_path / "merged.pdf.tmp").exists()


def test_verify_detects_wrong_page_count(tmp_path: Path, singles: list[Path]):
    out = tmp_path / "merged.pdf"
    merge_issue(singles, ["要闻", "评论", "国际"], out, issue_date=D)

    with pytest.raises(EngineError) as exc:
        verify_pdf(out, expected_pages=20)
    assert "页数不符" in str(exc.value)


def test_verify_rejects_garbage(tmp_path: Path):
    bad = tmp_path / "bad.pdf"
    bad.write_bytes(b"%PDF-1.4\n garbage")

    with pytest.raises(EngineError) as exc:
        verify_pdf(bad)

    assert exc.value.code == ErrorCode.MERGE_FAILED


def test_mismatched_inputs_rejected(tmp_path: Path, singles: list[Path]):
    with pytest.raises(EngineError):
        merge_issue(singles, ["要闻"], tmp_path / "x.pdf", issue_date=D)
