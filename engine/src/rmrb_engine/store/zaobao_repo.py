"""Transactional snapshots and article JSON: a single SQLite commit owns consistency."""

import json
from datetime import UTC, datetime

from ..core.zaobao_models import ZaobaoArticle, ZaobaoSummary
from .db import Database

ZAOBAO_DDL = (
    "CREATE TABLE IF NOT EXISTS zaobao_articles (article_id TEXT PRIMARY KEY, summary TEXT NOT NULL, body TEXT, read_at TEXT, accessed_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS zaobao_feed_items (position INTEGER PRIMARY KEY, article_id TEXT UNIQUE NOT NULL)",
    "CREATE TABLE IF NOT EXISTS zaobao_feed_state (id INTEGER PRIMARY KEY CHECK(id=1), fetched_at TEXT NOT NULL)",
)


def now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


class ZaobaoRepo:
    def __init__(self, db: Database) -> None:
        self.db = db

    def feed(self, offset: int = 0, limit: int = 60) -> dict:
        conn = self.db.conn
        # A single SELECT reads items and timestamp from the same WAL snapshot.
        rows = conn.execute(
            "SELECT a.summary,a.body IS NOT NULL AS cached,a.read_at,(SELECT fetched_at FROM zaobao_feed_state WHERE id=1) AS fetched_at FROM zaobao_feed_items f JOIN zaobao_articles a USING(article_id) ORDER BY f.position LIMIT ? OFFSET ?",
            (limit, offset),
        ).fetchall()
        total = conn.execute("SELECT count(*) FROM zaobao_feed_items").fetchone()[0]
        state = conn.execute(
            "SELECT next_page,has_more FROM zaobao_feed_state WHERE id=1"
        ).fetchone()
        return {
            "items": [
                dict(json.loads(r["summary"]), cached=bool(r["cached"]), read=bool(r["read_at"]))
                for r in rows
            ],
            "fetchedAt": rows[0]["fetched_at"] if rows else None,
            "total": total,
            "nextOffset": offset + len(rows) if offset + len(rows) < total else None,
            "nextPage": state[0] if state else 2,
            "hasMore": bool(state[1]) if state else True,
        }

    def save_feed(
        self,
        items: list[ZaobaoSummary],
        *,
        append: bool = False,
        next_page: int = 2,
        has_more: bool = True,
    ) -> None:
        with self.db.conn as conn:
            if not append:
                conn.execute("DELETE FROM zaobao_feed_items")
            position = conn.execute(
                "SELECT coalesce(max(position)+1,0) FROM zaobao_feed_items"
            ).fetchone()[0]
            for item in items:
                conn.execute(
                    "INSERT INTO zaobao_articles(article_id,summary,accessed_at) VALUES(?,?,?) ON CONFLICT(article_id) DO UPDATE SET summary=excluded.summary",
                    (item.article_id, item.model_dump_json(by_alias=True), now()),
                )
                conn.execute(
                    "INSERT OR IGNORE INTO zaobao_feed_items VALUES(?,?)",
                    (position, item.article_id),
                )
                position += 1
            conn.execute(
                "INSERT INTO zaobao_feed_state(id,fetched_at,next_page,has_more) VALUES(1,?,?,?) ON CONFLICT(id) DO UPDATE SET fetched_at=CASE WHEN ? THEN zaobao_feed_state.fetched_at ELSE excluded.fetched_at END,next_page=excluded.next_page,has_more=excluded.has_more",
                (now(), next_page, int(has_more), append),
            )

    def update_media(self, article: ZaobaoArticle) -> bool:
        with self.db.conn as conn:
            result = conn.execute(
                "UPDATE zaobao_articles SET body=? WHERE article_id=? AND json_extract(body,'$.fetchedAt')=?",
                (article.model_dump_json(by_alias=True), article.article_id, article.fetched_at),
            )
        return result.rowcount == 1

    def summary(self, identity: str) -> ZaobaoSummary | None:
        row = self.db.conn.execute(
            "SELECT summary FROM zaobao_articles WHERE article_id=?", (identity,)
        ).fetchone()
        return ZaobaoSummary.model_validate_json(row[0]) if row else None

    def article(self, identity: str) -> ZaobaoArticle | None:
        row = self.db.conn.execute(
            "SELECT body FROM zaobao_articles WHERE article_id=?", (identity,)
        ).fetchone()
        if row is None or row[0] is None:
            return None
        try:
            article = ZaobaoArticle.model_validate_json(row[0])
        except ValueError:
            with self.db.conn as conn:
                conn.execute("UPDATE zaobao_articles SET body=NULL WHERE article_id=?", (identity,))
            return None
        return article

    def save_article(self, article: ZaobaoArticle) -> None:
        with self.db.conn as conn:
            conn.execute(
                "UPDATE zaobao_articles SET body=?,accessed_at=? WHERE article_id=?",
                (article.model_dump_json(by_alias=True), now(), article.article_id),
            )

    def mark_read(self, identity: str, read: bool) -> None:
        with self.db.conn as conn:
            conn.execute(
                "UPDATE zaobao_articles SET read_at=?,accessed_at=? WHERE article_id=?",
                (now() if read else None, now(), identity),
            )

    def clear(self) -> int:
        with self.db.conn as conn:
            size = conn.execute(
                "SELECT coalesce(sum(length(CAST(body AS BLOB))),0) FROM zaobao_articles"
            ).fetchone()[0]
            conn.execute("UPDATE zaobao_articles SET body=NULL")
        return size
