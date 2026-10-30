"""Fixed-feed refresh and on-demand article extraction with offline storage."""

from __future__ import annotations

import hashlib
import json
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path

from ..core.errors import EngineError, ErrorCode
from ..core.zaobao_models import ZaobaoSummary
from ..net.zaobao import ZaobaoHttp, check_cancel
from ..site.zaobao import FEED_URL, more_url, parse_article, parse_feed, parse_more
from ..store.db import Database
from ..store.zaobao_repo import ZaobaoRepo
from .control import Cancelled

BODY_BUDGET = 700 * 1024
CACHE_BUDGET = 300 * 1024 * 1024


class ZaobaoService:
    def __init__(
        self,
        db: Database,
        cache: Path,
        *,
        http: ZaobaoHttp | None = None,
        media_http: ZaobaoHttp | None = None,
    ) -> None:
        self.db = db
        self.repo = ZaobaoRepo(db)
        self.cache = cache / "zaobao" / "media"
        self.http = http or ZaobaoHttp()
        self.media_http = media_http or http or ZaobaoHttp()
        self.emit = lambda _event, _data: None
        self._images = ThreadPoolExecutor(max_workers=1, thread_name_prefix="zaobao-images")
        self._image_jobs: dict[str, threading.Event] = {}
        self._mutation = threading.Lock()

    def close(self) -> None:
        with self._mutation:
            for cancel in self._image_jobs.values():
                cancel.set()
        self._images.shutdown(wait=True)
        if self.media_http is not self.http:
            self.media_http.close()
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
            raise EngineError(ErrorCode.BAD_REQUEST, "文章不在已发现的中国频道列表中")
        return summary

    def article(self, identity: object) -> dict:
        summary = self.summary(identity)
        article = self.repo.article(summary.article_id)
        return {"cached": article is not None, "article": article.dump() if article else None}

    def refresh_feed(self, cancel: threading.Event) -> None:
        with self._mutation:
            items = parse_feed(self.http.text(FEED_URL, cancel))
            check_cancel(cancel)
            payload = {"items": [item.dump() for item in items]}
            if len(json.dumps(payload, ensure_ascii=False).encode("utf-8")) > BODY_BUDGET:
                raise EngineError(ErrorCode.CONTENT_TOO_LARGE, "早报列表超出消息上限")
            self.repo.save_feed(items)

    def load_more(self, cancel: threading.Event) -> None:
        with self._mutation:
            state = self.repo.feed(limit=1)
            if not state["hasMore"]:
                return
            page = state["nextPage"]
            items, has_more = parse_more(self.http.json(more_url(page), cancel), page)
            check_cancel(cancel)
            self.repo.save_feed(items, append=True, next_page=page + 1, has_more=has_more)

    def fetch_article(
        self, identity: str, cancel: threading.Event, *, refresh: bool = False
    ) -> None:
        summary = self.summary(identity)
        with self._mutation:
            if not refresh and self.repo.article(identity) is not None:
                return
            article = parse_article(self.http.text(summary.url, cancel), summary.url)
            self._check_size(article.dump())
            article.fetched_at = datetime.now(UTC).isoformat(timespec="microseconds")
            # Commit readable text first. A cancellation or failed image must not lose it.
            check_cancel(cancel)
            self.repo.save_article(article)
            previous = self._image_jobs.get(identity)
            if previous:
                previous.set()
            media_cancel = threading.Event()
            self._image_jobs[identity] = media_cancel
            self._images.submit(self._enrich_images, article, media_cancel)

    def _enrich_images(self, article, cancel: threading.Event) -> None:
        try:
            for block in [b for b in article.blocks if b.type == "img"][:32]:
                check_cancel(cancel)
                source = block.src
                if source is None:
                    continue
                try:
                    block.local = self._local_image(source, cancel)
                except EngineError as exc:
                    article.warnings.append(exc.message)
                with self._mutation:
                    check_cancel(cancel)
                    self._check_size(article.dump())
                    if not self.repo.update_media(article):
                        return
                self.emit(
                    "zaobao.article.updated",
                    {"articleId": article.article_id, "fetchedAt": article.fetched_at},
                )
            with self._mutation:
                self._trim()
        except (Cancelled, EngineError, OSError):
            # Text is already committed; a media failure never fails the reading task.
            return
        finally:
            with self._mutation:
                if self._image_jobs.get(article.article_id) is cancel:
                    self._image_jobs.pop(article.article_id, None)
            self.db.close()

    @staticmethod
    def _check_size(payload: dict) -> None:
        if len(json.dumps(payload, ensure_ascii=False).encode("utf-8")) > BODY_BUDGET:
            raise EngineError(ErrorCode.CONTENT_TOO_LARGE, "文章超出阅读上限，请查看原文")

    def _local_image(self, url: str, cancel: threading.Event) -> str:
        digest = hashlib.sha256(url.encode()).hexdigest()
        target = self.cache / (digest + ".img")
        if target.is_file():
            return str(target)
        data, kind = self.media_http.request(url, cancel, max_bytes=10 * 1024 * 1024)
        if not _valid_image(data, kind):
            raise EngineError(ErrorCode.BAD_RESPONSE, "图片格式不受支持")
        try:
            with self._mutation:
                check_cancel(cancel)
                self.cache.mkdir(parents=True, exist_ok=True)
                temporary = target.with_suffix(".tmp")
                temporary.write_bytes(data)
                temporary.replace(target)
        except OSError as exc:
            raise EngineError(ErrorCode.DISK_ERROR, "图片缓存写入失败") from exc
        return str(target)

    def mark_read(self, identity: object, read: bool) -> None:
        summary = self.summary(identity)
        self.repo.mark_read(summary.article_id, read)

    def clear_cache(self) -> dict:
        if not self._mutation.acquire(timeout=0.25):
            raise EngineError(ErrorCode.BAD_REQUEST, "请先等待或取消早报任务，再清理缓存")
        try:
            for cancel in self._image_jobs.values():
                cancel.set()
            size = self.repo.clear()
            for path in self.cache.glob("*"):
                if path.is_file() and not path.is_symlink():
                    size += path.stat().st_size
                    path.unlink()
            return {"bytes": size}
        except OSError as exc:
            raise EngineError(ErrorCode.DISK_ERROR, "清理早报图片失败") from exc
        finally:
            self._mutation.release()

    def _trim(self) -> None:
        """Bound images first; retain metadata/read state and the current text snapshot."""
        files = sorted(self.cache.glob("*.img"), key=lambda p: p.stat().st_mtime)
        total = sum(p.stat().st_size for p in files)
        for path in files:
            if total <= CACHE_BUDGET:
                break
            total -= path.stat().st_size
            path.unlink(missing_ok=True)
        with self.db.conn as conn:
            sizes = conn.execute(
                "SELECT article_id,length(CAST(body AS BLOB)) AS size FROM zaobao_articles WHERE body IS NOT NULL ORDER BY accessed_at DESC"
            ).fetchall()
            for row in sizes:
                total += row["size"]
                if total > CACHE_BUDGET:
                    conn.execute(
                        "UPDATE zaobao_articles SET body=NULL WHERE article_id=?",
                        (row["article_id"],),
                    )


def _valid_image(data: bytes, kind: str) -> bool:
    if not kind.startswith("image/"):
        return False
    return data.startswith((b"\xff\xd8\xff", b"\x89PNG\r\n\x1a\n", b"GIF87a", b"GIF89a")) or (
        data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    )
