"""Fixed-feed refresh and on-demand article extraction with offline storage."""

from __future__ import annotations

import hashlib
import json
import threading
from pathlib import Path

from ..core.errors import EngineError, ErrorCode
from ..core.zaobao_models import ZaobaoSummary
from ..net.zaobao import ZaobaoHttp, check_cancel
from ..site.zaobao import FEED_URL, parse_article, parse_feed
from ..store.db import Database
from ..store.zaobao_repo import ZaobaoRepo, now

BODY_BUDGET = 700 * 1024
CACHE_BUDGET = 300 * 1024 * 1024


class ZaobaoService:
    def __init__(self, db: Database, cache: Path, *, http: ZaobaoHttp | None = None) -> None:
        self.db = db
        self.repo = ZaobaoRepo(db)
        self.cache = cache / "zaobao" / "media"
        self.http = http or ZaobaoHttp()
        self._mutation = threading.Lock()

    def close(self) -> None:
        self.http.close()

    def feed(self) -> dict:
        return self.repo.feed()

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

    def fetch_article(
        self, identity: str, cancel: threading.Event, *, refresh: bool = False
    ) -> None:
        summary = self.summary(identity)
        with self._mutation:
            if not refresh and self.repo.article(identity) is not None:
                return
            article = parse_article(self.http.text(summary.url, cancel), summary.url)
            self._check_size(article.dump())
            article.fetched_at = now()
            # Commit readable text first. A cancellation or failed image must not lose it.
            check_cancel(cancel)
            self.repo.save_article(article)
            for block in [b for b in article.blocks if b.type == "img"][:32]:
                check_cancel(cancel)
                source = block.src
                if source is None:
                    continue
                try:
                    block.local = self._local_image(source, cancel)
                except EngineError as exc:
                    article.warnings.append(exc.message)
            self._check_size(article.dump())
            self.repo.save_article(article)
            self._trim()

    @staticmethod
    def _check_size(payload: dict) -> None:
        if len(json.dumps(payload, ensure_ascii=False).encode("utf-8")) > BODY_BUDGET:
            raise EngineError(ErrorCode.CONTENT_TOO_LARGE, "文章超出阅读上限，请查看原文")

    def _local_image(self, url: str, cancel: threading.Event) -> str:
        digest = hashlib.sha256(url.encode()).hexdigest()
        target = self.cache / (digest + ".img")
        if target.is_file():
            return str(target)
        data, kind = self.http.request(url, cancel, max_bytes=10 * 1024 * 1024)
        if not _valid_image(data, kind):
            raise EngineError(ErrorCode.BAD_RESPONSE, "图片格式不受支持")
        try:
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
        if not self._mutation.acquire(blocking=False):
            raise EngineError(ErrorCode.BAD_REQUEST, "请先等待或取消早报任务，再清理缓存")
        try:
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
