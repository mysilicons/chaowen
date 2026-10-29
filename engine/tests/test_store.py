"""E-06 验收：存储层。"""

from __future__ import annotations

import threading
from datetime import date
from pathlib import Path

from rmrb_engine.store.db import Database
from rmrb_engine.store.repo import Repo

D = date(2026, 10, 29)


def make_repo(tmp_path: Path) -> Repo:
    return Repo(Database(tmp_path / "state.db"))


def test_upsert_is_idempotent(tmp_path: Path):
    repo = make_repo(tmp_path)

    for _ in range(3):
        repo.save_page(D, 1, status="done", title="要闻", size=100)

    assert len(repo.list_pages(D)) == 1
    page = repo.get_page(D, 1)
    assert page is not None
    assert page["title"] == "要闻"
    assert page["bytes"] == 100


def test_partial_update_keeps_existing_fields(tmp_path: Path):
    repo = make_repo(tmp_path)
    repo.save_page(D, 1, status="queued", title="要闻", pdf_url="https://x/1.pdf")

    # 只更新状态，不传 title/pdf_url
    repo.save_page(D, 1, status="done")

    page = repo.get_page(D, 1)
    assert page["status"] == "done"
    assert page["title"] == "要闻"
    assert page["pdf_url"] == "https://x/1.pdf"


def test_attempts_bump(tmp_path: Path):
    repo = make_repo(tmp_path)
    repo.save_page(D, 2, status="failed", error_code="HTTP_ERROR", bump_attempts=True)
    repo.save_page(D, 2, status="failed", error_code="HTTP_ERROR", bump_attempts=True)

    assert repo.get_page(D, 2)["attempts"] == 2


def test_concurrent_writes_from_two_threads(tmp_path: Path):
    repo = make_repo(tmp_path)
    errors: list[BaseException] = []

    def worker(offset: int) -> None:
        try:
            for i in range(50):
                repo.save_page(D, offset + i, status="done", title=f"p{offset + i}")
        except BaseException as exc:  # noqa: BLE001 - 测试里要把异常带出来
            errors.append(exc)

    threads = [threading.Thread(target=worker, args=(base,)) for base in (1, 101)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert not errors
    assert len(repo.list_pages(D)) == 100


def test_list_month_filters_by_prefix(tmp_path: Path):
    repo = make_repo(tmp_path)
    repo.save_issue(date(2026, 10, 1), page_count=8, status="archived")
    repo.save_issue(date(2026, 10, 29), page_count=20, status="archived")
    repo.save_issue(date(2026, 9, 30), page_count=20, status="archived")

    rows = repo.list_month(2026, 10)
    assert [row["date"] for row in rows] == ["2026-10-01", "2026-10-29"]


def test_issue_status_and_merged_path(tmp_path: Path):
    repo = make_repo(tmp_path)
    repo.save_issue(D, page_count=20, status="downloading")
    repo.save_issue(D, page_count=20, status="archived", merged_path="a.pdf", size=123)

    issue = repo.get_issue(D)
    assert issue["status"] == "archived"
    assert issue["merged_path"] == "a.pdf"
    assert issue["bytes"] == 123
    assert issue["singles_deleted"] == 0


def test_wal_mode_enabled(tmp_path: Path):
    repo = make_repo(tmp_path)
    mode = repo.db.conn.execute("PRAGMA journal_mode").fetchone()[0]

    assert mode.lower() == "wal"
