"""令牌桶限速。

低速是产品约束，不是可选项：默认 1 req/s，硬上限 2 req/s。
时钟与 sleep 可注入，便于测试（不真的睡）。
"""

from __future__ import annotations

import time
from collections.abc import Callable


class TokenBucket:
    def __init__(
        self,
        rate: float = 1.0,
        burst: float = 1.0,
        *,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if rate <= 0:
            raise ValueError("rate 必须大于 0")
        self._rate = float(rate)
        self._burst = max(float(burst), 1.0)
        self._clock = clock
        self._sleep = sleep
        self._tokens = self._burst
        self._last = clock()

    @property
    def rate(self) -> float:
        return self._rate

    def acquire(self, tokens: float = 1.0) -> float:
        """取得令牌，必要时阻塞；返回实际等待秒数。"""
        waited = 0.0
        while True:
            now = self._clock()
            elapsed = max(0.0, now - self._last)
            self._tokens = min(self._burst, self._tokens + elapsed * self._rate)
            self._last = now

            if self._tokens >= tokens:
                self._tokens -= tokens
                return waited

            need = (tokens - self._tokens) / self._rate
            self._sleep(need)
            waited += need
