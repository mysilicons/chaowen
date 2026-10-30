"""NDJSON 协议服务端。

三条硬性规则（见 docs/ipc.md §1.1）：
1. stdout 只允许协议 JSON；
2. 一条消息一行；
3. 单条消息上限 1 MB。
"""

from __future__ import annotations

import json
import logging
import threading
import time
from typing import Any, TextIO

from .core.errors import EngineError, ErrorCode
from .diagnostics import log_exception

MAX_LINE_BYTES = 1024 * 1024


class RequestContext:
    """给处理器用的回执/事件通道。"""

    def __init__(self, server: RpcServer, request_id: Any) -> None:
        self._server = server
        self.request_id = request_id

    def respond(self, result: Any) -> None:
        self._server.write_ok(self.request_id, result)

    def emit(self, event: str, data: dict[str, Any]) -> None:
        self._server.write_event(event, data)


class RpcServer:
    def __init__(self, engine: Any, inp: TextIO, out: TextIO) -> None:
        self.engine = engine
        self.inp = inp
        self.out = out
        self.engine.bind_emitter(self.write_event)
        self._responded = False
        self._write_lock = threading.Lock()

    # ---- 输出 ----

    def write(self, payload: dict[str, Any]) -> None:
        # 下载跑在工作线程里，事件和响应会并发写，必须串行化
        with self._write_lock:
            self.out.write(json.dumps(payload, ensure_ascii=False) + "\n")
            self.out.flush()

    def write_ok(self, request_id: Any, result: Any) -> None:
        self._responded = True
        self.write({"id": request_id, "ok": True, "result": result})

    def write_error(self, request_id: Any, error: EngineError) -> None:
        self._responded = True
        self.write({"id": request_id, "ok": False, "error": error.to_envelope()})

    def write_event(self, event: str, data: dict[str, Any]) -> None:
        self.write({"event": event, "data": data})

    # ---- 主循环 ----

    def run(self) -> None:
        for raw in self.inp:
            line = raw.strip()
            if not line:
                continue
            self.handle(line)

    def handle(self, line: str) -> None:
        if len(line.encode("utf-8")) > MAX_LINE_BYTES:
            self.write(
                {
                    "id": None,
                    "ok": False,
                    "error": {"code": "BAD_REQUEST", "message": "消息过大"},
                }
            )
            return

        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            self.write(
                {
                    "id": None,
                    "ok": False,
                    "error": {
                        "code": "BAD_REQUEST",
                        "message": "JSON 解析失败",
                        "detail": str(exc),
                    },
                }
            )
            return

        if not isinstance(request, dict):
            self.write(
                {
                    "id": None,
                    "ok": False,
                    "error": {"code": "BAD_REQUEST", "message": "请求必须是对象"},
                }
            )
            return

        request_id = request.get("id")
        method = request.get("method")
        params = request.get("params") or {}
        if not isinstance(params, dict):
            self.write_error(request_id, EngineError(ErrorCode.BAD_REQUEST, "params 必须是对象"))
            return

        handler = self.engine.handlers.get(method) if isinstance(method, str) else None
        if handler is None:
            self.write_error(
                request_id,
                EngineError(ErrorCode.UNKNOWN_METHOD, f"未知方法：{method}"),
            )
            return

        self._responded = False
        ctx = RequestContext(self, request_id)
        started = time.monotonic()
        try:
            result = handler(params, ctx)
        except EngineError as exc:
            logging.getLogger("rmrb_engine.rpc").warning(
                "rpc.failed method=%s id=%s code=%s", method, request_id, exc.code.value
            )
            if not self._responded:
                self.write_error(request_id, exc)
            return
        except Exception as exc:  # noqa: BLE001 - 任何异常都不能让进程退出
            log_exception(f"rpc.exception method={method} id={request_id}", exc)
            if not self._responded:
                self.write_error(
                    request_id,
                    EngineError(ErrorCode.BAD_REQUEST, "内部错误", detail=repr(exc)),
                )
            return

        if not self._responded:
            self.write_ok(request_id, result)
        if method != "zaobao.task.get":
            logging.getLogger("rmrb_engine.rpc").info(
                "rpc.done method=%s id=%s elapsedMs=%.1f",
                method,
                request_id,
                (time.monotonic() - started) * 1000,
            )
