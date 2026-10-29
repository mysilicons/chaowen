"""状态读写。所有写操作用短事务，避免长事务阻塞并发读。"""

from __future__ import annotations

from datetime import date as Date
from datetime import datetime
from typing import Any

from .db import Database


def _now() -> str:
    return datetime.now().isoformat(timespec="seconds")


class Repo:
    def __init__(self, db: Database) -> None:
        self.db = db

    # ------------------------------------------------------------------ #
    # pages
    # ------------------------------------------------------------------ #

    def save_page(
        self,
        d: Date,
        page_no: int,
        *,
        status: str,
        title: str | None = None,
        pdf_url: str | None = None,
        thumb_url: str | None = None,
        file: str | None = None,
        size: int | None = None,
        sha256: str | None = None,
        etag: str | None = None,
        error_code: str | None = None,
        bump_attempts: bool = False,
    ) -> None:
        """插入或更新一版。传 None 的字段保留旧值（COALESCE）。"""
        attempts_expr = "pages.attempts + 1" if bump_attempts else "pages.attempts"
        with self.db.conn:
            self.db.conn.execute(
                f"""
                INSERT INTO pages (date, page_no, title, pdf_url, thumb_url, file,
                                   bytes, sha256, etag, status, attempts, error_code, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(date, page_no) DO UPDATE SET
                    title      = COALESCE(excluded.title, pages.title),
                    pdf_url    = COALESCE(excluded.pdf_url, pages.pdf_url),
                    thumb_url  = COALESCE(excluded.thumb_url, pages.thumb_url),
                    file       = COALESCE(excluded.file, pages.file),
                    bytes      = COALESCE(excluded.bytes, pages.bytes),
                    sha256     = COALESCE(excluded.sha256, pages.sha256),
                    etag       = COALESCE(excluded.etag, pages.etag),
                    status     = excluded.status,
                    attempts   = {attempts_expr},
                    error_code = excluded.error_code,
                    updated_at = excluded.updated_at
                """,
                (
                    d.isoformat(),
                    page_no,
                    title,
                    pdf_url,
                    thumb_url,
                    file,
                    size,
                    sha256,
                    etag,
                    status,
                    1 if bump_attempts else 0,
                    error_code,
                    _now(),
                ),
            )

    def get_page(self, d: Date, page_no: int) -> dict[str, Any] | None:
        row = self.db.conn.execute(
            "SELECT * FROM pages WHERE date = ? AND page_no = ?", (d.isoformat(), page_no)
        ).fetchone()
        return dict(row) if row else None

    def list_pages(self, d: Date) -> list[dict[str, Any]]:
        rows = self.db.conn.execute(
            "SELECT * FROM pages WHERE date = ? ORDER BY page_no", (d.isoformat(),)
        ).fetchall()
        return [dict(row) for row in rows]

    def list_by_status(self, status: str) -> list[dict[str, Any]]:
        rows = self.db.conn.execute(
            "SELECT * FROM pages WHERE status = ? ORDER BY date DESC, page_no", (status,)
        ).fetchall()
        return [dict(row) for row in rows]

    # ------------------------------------------------------------------ #
    # issues
    # ------------------------------------------------------------------ #

    def save_issue(
        self,
        d: Date,
        *,
        page_count: int,
        status: str,
        merged_path: str | None = None,
        size: int | None = None,
        singles_deleted: bool = False,
    ) -> None:
        with self.db.conn:
            self.db.conn.execute(
                """
                INSERT INTO issues (date, page_count, status, merged_path, bytes,
                                    singles_deleted, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET
                    page_count      = excluded.page_count,
                    status          = excluded.status,
                    merged_path     = COALESCE(excluded.merged_path, issues.merged_path),
                    bytes           = COALESCE(excluded.bytes, issues.bytes),
                    singles_deleted = excluded.singles_deleted,
                    updated_at      = excluded.updated_at
                """,
                (
                    d.isoformat(),
                    page_count,
                    status,
                    merged_path,
                    size,
                    1 if singles_deleted else 0,
                    _now(),
                ),
            )

    def get_issue(self, d: Date) -> dict[str, Any] | None:
        row = self.db.conn.execute(
            "SELECT * FROM issues WHERE date = ?", (d.isoformat(),)
        ).fetchone()
        return dict(row) if row else None

    def list_month(self, year: int, month: int) -> list[dict[str, Any]]:
        prefix = f"{year:04d}-{month:02d}"
        rows = self.db.conn.execute(
            "SELECT * FROM issues WHERE date LIKE ? ORDER BY date", (f"{prefix}-%",)
        ).fetchall()
        return [dict(row) for row in rows]

