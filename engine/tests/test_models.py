"""E-01 验收：模型字段与协议一致（camelCase）。"""

from __future__ import annotations

from datetime import date

from rmrb_engine.core.models import (
    Article,
    Block,
    BlockType,
    Issue,
    Job,
    JobStatus,
    Manifest,
    ManifestPage,
    Page,
    PageKind,
)


def test_issue_dump_is_camel_case():
    issue = Issue(
        date=date(2026, 10, 29),
        page_count=1,
        source_url="https://x/node_01.html",
        pages=[
            Page(
                no=1,
                title="要闻",
                url="u",
                pdf_url="p",
                original_name="rmrb2026102901.pdf",
                thumb_url="t",
            )
        ],
    )
    data = issue.dump()

    assert data["pageCount"] == 1
    assert data["sourceUrl"] == "https://x/node_01.html"
    assert data["date"] == "2026-10-29"
    assert "page_count" not in data

    page = data["pages"][0]
    assert page["pdfUrl"] == "p"
    assert page["originalName"] == "rmrb2026102901.pdf"
    assert page["thumbUrl"] == "t"


def test_issue_accepts_both_naming_styles():
    assert Issue(page_count=2).page_count == 2
    assert Issue.model_validate({"pageCount": 2}).page_count == 2


def test_article_blocks_dump():
    article = Article(
        title="标题",
        url="https://x/content_1.html",
        author="本报记者  张  洋",
        blocks=[Block.paragraph("第一段"), Block.image("https://x/a.jpg")],
    )
    data = article.dump()

    assert data["blocks"][0] == {
        "type": "p",
        "text": "第一段",
        "src": None,
        "local": None,
        "caption": None,
    }
    assert data["blocks"][1]["type"] == "img"
    assert data["author"] == "本报记者  张  洋"


def test_manifest_uses_schema_key():
    manifest = Manifest(
        date=date(2026, 10, 29),
        page_count=20,
        merged="人民日报_2026-10-29.pdf",
        merged_bytes=23489152,
        pages=[ManifestPage(page_no=1, title="要闻")],
    )
    data = manifest.dump()

    assert data["schema"] == 1
    assert data["pageCount"] == 20
    assert data["mergedBytes"] == 23489152
    assert data["singlesDeleted"] is False
    assert data["pages"][0]["pageNo"] == 1


def test_job_status_is_timestamped_as_string():
    job = Job(id="20261029-1", date=date(2026, 10, 29), total=20)
    data = job.dump()

    assert data["status"] == "queued"
    assert data["date"] == "2026-10-29"


def test_enum_values_match_protocol():
    assert BlockType.PARAGRAPH == "p"
    assert PageKind.IMAGE_ONLY == "image_only"
    assert JobStatus.DOWNLOADING == "downloading"


def test_error_codes_match_protocol():
    """错误码必须与 docs/ipc.md §2.3 完全一致，不允许悄悄增删。"""
    from rmrb_engine.core.errors import ErrorCode

    expected = {
        "NO_ISSUE",
        "PARSE_ERROR",
        "HTTP_ERROR",
        "TIMEOUT",
        "BAD_RESPONSE",
        "CORRUPT",
        "DISK_ERROR",
        "MERGE_FAILED",
        "CIRCUIT_OPEN",
        "UNKNOWN_METHOD",
        "BAD_REQUEST",
    }
    assert {code.value for code in ErrorCode} == expected


def test_engine_error_envelope():
    from rmrb_engine.core.errors import EngineError, ErrorCode

    error = EngineError(ErrorCode.PARSE_ERROR, "未找到版面列表", detail="matched 0")
    envelope = error.to_envelope()

    assert envelope == {
        "code": "PARSE_ERROR",
        "message": "未找到版面列表",
        "detail": "matched 0",
    }
