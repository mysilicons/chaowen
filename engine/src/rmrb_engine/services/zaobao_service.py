"""On-demand China news kept only for the active in-memory session."""

from __future__ import annotations

import json
import logging
import threading
from collections.abc import Callable
from datetime import UTC, datetime

from ..core.errors import EngineError, ErrorCode
from ..core.zaobao_models import ZaobaoSummary
from ..net.zaobao import ZaobaoHttp, check_cancel
from ..site.zaobao import FEED_URL, more_url, parse_article, parse_feed, parse_more
from ..store.zaobao_repo import ZaobaoRepo
from .control import Cancelled

BODY_BUDGET = 700 * 1024
logger = logging.getLogger("rmrb_engine.zaobao")


class ZaobaoService:
    def __init__(self, *, http: ZaobaoHttp | None = None) -> None:
        self.repo = ZaobaoRepo()
        self.http = http or ZaobaoHttp()
        self._lock = threading.RLock()
        self._session = 0

    @property
    def session(self) -> int:
        with self._lock:
            return self._session

    def reset(self) -> dict:
        with self._lock:
            self._session += 1
            self.repo.reset()
            logger.info("session.reset generation=%d", self._session)
            return {"session": self._session}

    def close(self) -> None:
        self.reset()
        self.http.close()

    def feed(self, offset: object = 0, limit: object = 60) -> dict:
        if type(offset) is not int or type(limit) is not int or offset < 0 or not 1 <= limit <= 100:
            raise EngineError(ErrorCode.BAD_REQUEST, "早报列表分页参数非法")
        return self.repo.feed(offset, limit)

    def summary(self, identity: object) -> ZaobaoSummary:
        if (
            not isinstance(identity, str)
            or not identity.isascii()
            or not identity.isdecimal()
            or len(identity) > 20
        ):
            raise EngineError(ErrorCode.BAD_REQUEST, "articleId 非法")
        summary = self.repo.summary(identity)
        if summary is None:
            raise EngineError(ErrorCode.BAD_REQUEST, "文章不在当前中国频道列表中")
        return summary

    def article(self, identity: object) -> dict:
        summary = self.summary(identity)
        article = self.repo.article(summary.article_id)
        return {"cached": article is not None, "article": article.dump() if article else None}

    def _commit(self, session: int, cancel: threading.Event, operation: Callable[[], None]) -> None:
        with self._lock:
            check_cancel(cancel)
            if session != self._session:
                raise Cancelled()
            operation()

    def refresh_feed(self, cancel: threading.Event) -> None:
        session = self.session
        items = parse_feed(self.http.text(FEED_URL, cancel))
        self._check_size({"items": [item.dump() for item in items]})
        self._commit(session, cancel, lambda: self.repo.save_feed(items))
        logger.info("feed.loaded items=%d", len(items))

    def load_more(self, cancel: threading.Event) -> None:
        with self._lock:
            session, state = self._session, self.repo.feed(limit=1)
        if not state["hasMore"]:
            return
        page = state["nextPage"]
        items, has_more = parse_more(self.http.json(more_url(page), cancel), page)
        self._commit(
            session,
            cancel,
            lambda: self.repo.save_feed(items, append=True, next_page=page + 1, has_more=has_more),
        )
        logger.info("feed.more page=%d items=%d hasMore=%s", page, len(items), has_more)

    def fetch_article(
        self, identity: str, cancel: threading.Event, *, refresh: bool = False
    ) -> None:
        with self._lock:
            session, summary = self._session, self.summary(identity)
            if not refresh and self.repo.article(identity) is not None:
                return
        article = parse_article(self.http.text(summary.url, cancel), summary.url)
        article.fetched_at = datetime.now(UTC).isoformat(timespec="microseconds")
        self._check_size(article.dump())
        self._commit(session, cancel, lambda: self.repo.save_article(article))
        logger.info(
            "article.ready id=%s blocks=%d state=%s",
            identity,
            len(article.blocks),
            article.content_state,
        )

    @staticmethod
    def _check_size(payload: dict) -> None:
        if len(json.dumps(payload, ensure_ascii=False).encode("utf-8")) > BODY_BUDGET:
            raise EngineError(ErrorCode.CONTENT_TOO_LARGE, "内容超出阅读上限，请查看原文")

    def mark_read(self, identity: object, read: bool) -> None:
        summary = self.summary(identity)
        self.repo.mark_read(summary.article_id, read)
