"""Short RPC handlers and one cancellable worker, separate from newspaper downloads."""

from __future__ import annotations

import copy
import threading
import time
import uuid
import webbrowser
from concurrent.futures import ThreadPoolExecutor
from typing import Any

from .core.errors import EngineError, ErrorCode
from .services.control import Cancelled
from .services.zaobao_service import ZaobaoService

TERMINAL = {"succeeded", "failed", "cancelled"}


class ZaobaoAPI:
    def __init__(self, service: ZaobaoService) -> None:
        self.service = service
        self.emit = lambda _event, _data: None
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="zaobao")
        self._lock = threading.Lock()
        self._tasks: dict[str, dict] = {}
        self._cancel: dict[str, threading.Event] = {}

    @property
    def handlers(self) -> dict:
        return {
            "zaobao.feed.get": lambda p, c: self.service.feed(),
            "zaobao.feed.refresh": lambda p, c: self.start("feed", None, False, c),
            "zaobao.article.get": lambda p, c: self.service.article(p.get("articleId")),
            "zaobao.article.fetch": self.fetch,
            "zaobao.task.get": lambda p, c: self.task(p.get("jobId")),
            "zaobao.task.cancel": self.cancel,
            "zaobao.cache.clear": lambda p, c: self.service.clear_cache(),
            "zaobao.read.set": self.mark_read,
            "zaobao.original.open": self.open_original,
        }

    def fetch(self, params: dict, ctx: Any) -> None:
        identity = self.service.summary(params.get("articleId")).article_id
        refresh = params.get("refresh", False)
        if not isinstance(refresh, bool):
            raise EngineError(ErrorCode.BAD_REQUEST, "refresh 必须是布尔值")
        self.start("article", identity, refresh, ctx)

    def start(self, kind: str, identity: str | None, refresh: bool, ctx: Any) -> None:
        with self._lock:
            self._prune()
            existing = next(
                (
                    t
                    for t in self._tasks.values()
                    if t["kind"] == kind
                    and t["articleId"] == identity
                    and t["state"] not in TERMINAL
                    and not self._cancel[t["jobId"]].is_set()
                ),
                None,
            )
            if existing:
                ctx.respond({"jobId": existing["jobId"]})
                return
            job = "zaobao-" + uuid.uuid4().hex[:16]
            self._tasks[job] = {
                "jobId": job,
                "kind": kind,
                "articleId": identity,
                "state": "queued",
                "error": None,
                "updated": time.monotonic(),
            }
            self._cancel[job] = threading.Event()
        ctx.respond({"jobId": job})
        try:
            self._executor.submit(self._work, job, refresh)
        except RuntimeError:
            self._change(
                job, "failed", EngineError(ErrorCode.HTTP_ERROR, "早报工作线程已停止").to_envelope()
            )

    def _work(self, job: str, refresh: bool) -> None:
        self._change(job, "running")
        task = self.task(job)
        with self._lock:
            cancel = self._cancel[job]
        try:
            if task["kind"] == "feed":
                self.service.refresh_feed(cancel)
            else:
                self.service.fetch_article(task["articleId"], cancel, refresh=refresh)
            self._change(job, "succeeded")
        except Cancelled:
            self._change(job, "cancelled")
        except EngineError as exc:
            self._change(job, "failed", exc.to_envelope())
        except Exception as exc:
            self._change(
                job,
                "failed",
                EngineError(ErrorCode.DISK_ERROR, "早报处理失败", detail=str(exc)).to_envelope(),
            )
        finally:
            self.service.db.close()

    def _change(self, job: str, state: str, error: dict | None = None) -> None:
        with self._lock:
            self._tasks[job].update(state=state, error=error, updated=time.monotonic())
            payload = self._snapshot(job)
        self.emit("zaobao.task.changed", payload)

    def _snapshot(self, job: str) -> dict:
        return copy.deepcopy({k: v for k, v in self._tasks[job].items() if k != "updated"})

    def task(self, job: object) -> dict:
        with self._lock:
            if not isinstance(job, str) or job not in self._tasks:
                raise EngineError(ErrorCode.BAD_REQUEST, "早报任务不存在或已过期")
            return self._snapshot(job)

    def cancel(self, params: dict, ctx: Any) -> dict:
        job = self.task(params.get("jobId"))["jobId"]
        with self._lock:
            self._cancel[job].set()
        return {"ok": True}

    def mark_read(self, params: dict, ctx: Any) -> dict:
        read = params.get("read")
        if not isinstance(read, bool):
            raise EngineError(ErrorCode.BAD_REQUEST, "read 必须是布尔值")
        self.service.mark_read(params.get("articleId"), read)
        return {"ok": True}

    def open_original(self, params: dict, ctx: Any) -> dict:
        url = self.service.summary(params.get("articleId")).url
        return {"ok": bool(webbrowser.open(url))}

    def _prune(self) -> None:
        expired = [
            key
            for key, task in self._tasks.items()
            if task["state"] in TERMINAL and time.monotonic() - task["updated"] > 600
        ]
        for key in expired:
            self._tasks.pop(key)
            self._cancel.pop(key)

    def close(self) -> None:
        with self._lock:
            for task in self._tasks.values():
                if task["state"] not in TERMINAL:
                    self._cancel[task["jobId"]].set()
        self._executor.shutdown(wait=True)
        self.service.close()
