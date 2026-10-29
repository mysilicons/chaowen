"""HTTP 客户端：限速、重试、熔断。

设计约束（见设计文档 §7.1）：
- 每次请求前必须通过令牌桶；
- 5xx/超时重试 3 次，退避 2/4/8 s + 抖动；
- 403/404 只重试 1 次（实测有效 URL 会偶发抖动）；
- 429 遵守 Retry-After；
- 连续 8 次失败熔断，避免把 IP 送进黑名单。
"""

from __future__ import annotations

import random
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from typing import Any

import httpx

from ..core.errors import EngineError, ErrorCode
from .limiter import TokenBucket

DEFAULT_UA = "RMReader/0.3 (personal reading; low-rate)"

RETRY_STATUSES = frozenset({500, 502, 503, 504})
FLAKY_STATUSES = frozenset({403, 404})


class HttpClient:
    def __init__(
        self,
        *,
        client: httpx.Client | None = None,
        limiter: TokenBucket | None = None,
        user_agent: str = DEFAULT_UA,
        attempts: int = 3,
        backoff: float = 2.0,
        jitter: float = 0.2,
        circuit_threshold: int = 8,
        retry_after_cap: float = 60.0,
        timeout: float = 20.0,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self._client = client or httpx.Client(
            timeout=httpx.Timeout(timeout, connect=10.0),
            follow_redirects=True,
        )
        self._own_client = client is None
        self._headers = {"User-Agent": user_agent}
        self._limiter = limiter or TokenBucket()
        self._attempts = attempts
        self._backoff = backoff
        self._jitter = jitter
        self._circuit_threshold = circuit_threshold
        self._retry_after_cap = retry_after_cap
        self._sleep = sleep
        self._failures = 0
        self.request_count = 0

    # ------------------------------------------------------------------ #
    # 公开接口
    # ------------------------------------------------------------------ #

    def get_text(self, url: str, headers: dict[str, str] | None = None) -> str:
        response = self._send("GET", url, headers=headers)
        response.encoding = "utf-8"
        return response.text

    @contextmanager
    def stream(
        self, url: str, headers: dict[str, str] | None = None
    ) -> Iterator[httpx.Response]:
        """流式下载用；不自动重试（由调用方按状态码处理）。"""
        self._guard_circuit()
        self._limiter.acquire()
        self.request_count += 1
        try:
            with self._client.stream("GET", url, headers=self._merged(headers)) as response:
                if response.status_code < 400:
                    self._failures = 0
                else:
                    self._failures += 1
                yield response
        except httpx.HTTPError as exc:
            self._failures += 1
            raise EngineError(ErrorCode.HTTP_ERROR, str(exc), detail=url) from exc

    def close(self) -> None:
        if self._own_client:
            self._client.close()

    def __enter__(self) -> HttpClient:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    # ------------------------------------------------------------------ #
    # 内部实现
    # ------------------------------------------------------------------ #

    def _send(
        self, method: str, url: str, headers: dict[str, str] | None = None
    ) -> httpx.Response:
        attempt = 0
        flaky_retried = False
        rate_limited = 0

        while True:
            self._guard_circuit()
            self._limiter.acquire()
            self.request_count += 1

            try:
                response = self._client.request(method, url, headers=self._merged(headers))
            except httpx.TimeoutException as exc:
                self._failures += 1
                if attempt + 1 >= self._attempts:
                    raise EngineError(ErrorCode.TIMEOUT, "请求超时", detail=url) from exc
                self._wait(attempt)
                attempt += 1
                continue
            except httpx.HTTPError as exc:
                self._failures += 1
                if attempt + 1 >= self._attempts:
                    raise EngineError(ErrorCode.HTTP_ERROR, str(exc), detail=url) from exc
                self._wait(attempt)
                attempt += 1
                continue

            status = response.status_code
            if status < 400:
                self._failures = 0
                return response

            self._failures += 1

            if status in FLAKY_STATUSES and not flaky_retried:
                flaky_retried = True
                self._wait(0, base=0.3)
                continue

            if status == 429 and rate_limited < 2:
                rate_limited += 1
                self._sleep(min(self._retry_after(response), self._retry_after_cap))
                continue

            if status in RETRY_STATUSES and attempt + 1 < self._attempts:
                self._wait(attempt)
                attempt += 1
                continue

            raise EngineError(ErrorCode.HTTP_ERROR, f"HTTP {status}", detail=url)

    def _merged(self, headers: dict[str, str] | None) -> dict[str, str]:
        return {**self._headers, **(headers or {})}

    def _guard_circuit(self) -> None:
        if self._failures >= self._circuit_threshold:
            raise EngineError(
                ErrorCode.CIRCUIT_OPEN,
                "连续失败过多，已熔断，建议稍后再试",
                detail=f"failures={self._failures}",
            )

    def _wait(self, attempt: int, base: float | None = None) -> None:
        delay = (base if base is not None else self._backoff) * (2**attempt)
        if self._jitter:
            delay *= 1 + random.uniform(-self._jitter, self._jitter)
        self._sleep(max(delay, 0.0))

    @staticmethod
    def _retry_after(response: httpx.Response) -> float:
        raw: Any = response.headers.get("Retry-After")
        try:
            return float(raw)
        except (TypeError, ValueError):
            return 2.0
