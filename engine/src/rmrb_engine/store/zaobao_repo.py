"""Ephemeral China-channel session. This module never opens a database or file."""

from datetime import UTC, datetime
from threading import RLock

from ..core.zaobao_models import ZaobaoArticle, ZaobaoSummary


class ZaobaoRepo:
    def __init__(self) -> None:
        self._lock = RLock()
        self.reset()

    def reset(self) -> None:
        with self._lock:
            self._items: dict[str, ZaobaoSummary] = {}
            self._articles: dict[str, ZaobaoArticle] = {}
            self._read: set[str] = set()
            self._fetched_at: str | None = None
            self._next_page = 2
            self._has_more = True

    def feed(self, offset: int = 0, limit: int = 60) -> dict:
        with self._lock:
            items = list(self._items.values())
            return {
                "items": [
                    dict(
                        item.dump(),
                        cached=item.article_id in self._articles,
                        read=item.article_id in self._read,
                    )
                    for item in items[offset : offset + limit]
                ],
                "fetchedAt": self._fetched_at,
                "total": len(items),
                "nextOffset": offset + limit if offset + limit < len(items) else None,
                "nextPage": self._next_page,
                "hasMore": self._has_more,
            }

    def save_feed(
        self,
        items: list[ZaobaoSummary],
        *,
        append: bool = False,
        next_page: int = 2,
        has_more: bool = True,
    ) -> None:
        with self._lock:
            if not append:
                self._items.clear()
                self._articles.clear()
                self._read.clear()
                self._fetched_at = datetime.now(UTC).isoformat(timespec="seconds")
            for item in items:
                self._items[item.article_id] = item.model_copy(deep=True)
            self._next_page, self._has_more = next_page, has_more

    def summary(self, identity: str) -> ZaobaoSummary | None:
        with self._lock:
            item = self._items.get(identity)
            return item.model_copy(deep=True) if item else None

    def article(self, identity: str) -> ZaobaoArticle | None:
        with self._lock:
            item = self._articles.get(identity)
            return item.model_copy(deep=True) if item else None

    def save_article(self, article: ZaobaoArticle) -> None:
        with self._lock:
            self._articles[article.article_id] = article.model_copy(deep=True)

    def mark_read(self, identity: str, read: bool) -> None:
        with self._lock:
            if read:
                self._read.add(identity)
            else:
                self._read.discard(identity)
