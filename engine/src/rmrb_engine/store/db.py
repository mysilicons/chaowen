"""SQLite 连接管理：WAL + 每线程独立连接。"""

from __future__ import annotations

import sqlite3
import threading
from pathlib import Path

SCHEMA_VERSION = 2

DDL = """
CREATE TABLE IF NOT EXISTS schema_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS issues (
  date            TEXT PRIMARY KEY,
  page_count      INTEGER NOT NULL DEFAULT 0,
  status          TEXT NOT NULL,
  merged_path     TEXT,
  bytes           INTEGER,
  singles_deleted INTEGER NOT NULL DEFAULT 0,
  updated_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pages (
  date       TEXT NOT NULL,
  page_no    INTEGER NOT NULL,
  title      TEXT,
  pdf_url    TEXT,
  thumb_url  TEXT,
  file       TEXT,
  bytes      INTEGER,
  sha256     TEXT,
  etag       TEXT,
  status     TEXT NOT NULL,
  attempts   INTEGER NOT NULL DEFAULT 0,
  error_code TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (date, page_no)
);

CREATE INDEX IF NOT EXISTS idx_pages_status ON pages(status);
CREATE INDEX IF NOT EXISTS idx_issues_status ON issues(status);
"""


class Database:
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._local = threading.local()
        self._init_schema()

    @property
    def conn(self) -> sqlite3.Connection:
        conn: sqlite3.Connection | None = getattr(self._local, "conn", None)
        if conn is None:
            conn = sqlite3.connect(self.path, timeout=10.0)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA busy_timeout=5000")
            conn.execute("PRAGMA synchronous=NORMAL")
            self._local.conn = conn
        return conn

    def _init_schema(self) -> None:
        from .zaobao_repo import ZAOBAO_DDL

        self.conn.executescript(DDL)
        row = self.conn.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
        version = int(row[0]) if row else 0
        if version > SCHEMA_VERSION:
            raise RuntimeError("数据库版本较新，请更新朝闻后再打开")
        if version == 1:
            with sqlite3.connect(str(self.path) + ".v1.bak") as backup:
                self.conn.backup(backup)
        with self.conn:
            self.conn.execute("BEGIN IMMEDIATE")
            for statement in ZAOBAO_DDL:
                self.conn.execute(statement)
            self.conn.execute(
                "INSERT INTO schema_meta(key, value) VALUES('version', ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                (str(SCHEMA_VERSION),),
            )

    def close(self) -> None:
        conn: sqlite3.Connection | None = getattr(self._local, "conn", None)
        if conn is not None:
            conn.close()
            self._local.conn = None
