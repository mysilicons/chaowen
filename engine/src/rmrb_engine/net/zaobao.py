"""Bounded, cancellable requests for the fixed .com source; never switches domains."""

from __future__ import annotations

import threading
import time
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from urllib.parse import urljoin

import httpx

from ..core.errors import EngineError, ErrorCode
from ..services.control import Cancelled
from ..site.zaobao import FEED_URL, article_url, media_url


def check_cancel(cancel: threading.Event) -> None:
    if cancel.is_set():
        raise Cancelled()


def _check_url(url: str) -> None:
    if url != FEED_URL and media_url(url) is None:
        article_url(url)


class ZaobaoHttp:
    def __init__(self, *, client: httpx.Client | None = None, interval: float = 10) -> None:
        self.client = client or httpx.Client(
            timeout=httpx.Timeout(20, connect=10),
            follow_redirects=False,
            headers={"User-Agent": "ChaoWen/0.2 (personal reader; low-rate)"},
        )
        self.interval = interval
        self._next_request = 0.0
        self._lock = threading.Lock()

    def close(self) -> None:
        self.client.close()

    def text(self, url: str, cancel: threading.Event) -> str:
        data, kind = self.request(url, cancel, max_bytes=5 * 1024 * 1024)
        if "text/html" not in kind:
            raise EngineError(ErrorCode.BAD_RESPONSE, "早报返回的不是 HTML 页面")
        try:
            return data.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise EngineError(ErrorCode.BAD_RESPONSE, "早报页面不是有效 UTF-8") from exc

    def request(self, url: str, cancel: threading.Event, *, max_bytes: int) -> tuple[bytes, str]:
        _check_url(url)
        with self._lock:
            return self._request(url, cancel, max_bytes)

    def _wait(self, cancel: threading.Event) -> None:
        if cancel.wait(max(0, self._next_request - time.monotonic())):
            raise Cancelled()
        check_cancel(cancel)
        self._next_request = time.monotonic() + self.interval

    def _request(self, url: str, cancel: threading.Event, maximum: int) -> tuple[bytes, str]:
        redirects = 0
        for attempt in range(3):
            try:
                while True:
                    self._wait(cancel)
                    with self.client.stream("GET", url, follow_redirects=False) as response:
                        if response.is_redirect:
                            url = urljoin(url, response.headers.get("location", ""))
                            _check_url(url)
                            redirects += 1
                            if redirects > 3:
                                raise EngineError(ErrorCode.BAD_RESPONSE, "早报重定向次数过多")
                            continue
                        self._status(response)
                        return self._read(response, cancel, maximum)
            except (httpx.TimeoutException, httpx.NetworkError) as exc:
                if attempt == 2:
                    raise EngineError(ErrorCode.TIMEOUT, "早报网络请求失败，请稍后重试") from exc
            except httpx.HTTPStatusError as exc:
                if exc.response.status_code < 500 or attempt == 2:
                    raise EngineError(
                        ErrorCode.HTTP_ERROR, f"早报 HTTP {exc.response.status_code}"
                    ) from exc
            if cancel.wait(2 ** (attempt + 1)):
                raise Cancelled()
        raise EngineError(ErrorCode.HTTP_ERROR, "早报请求失败")

    def _status(self, response: httpx.Response) -> None:
        if response.status_code == 429:
            seconds = _retry_seconds(response.headers.get("retry-after", "60"))
            self._next_request = max(self._next_request, time.monotonic() + seconds)
            raise EngineError(
                ErrorCode.RATE_LIMITED, f"访问频率受限，请至少 {seconds:.0f} 秒后重试"
            )
        if response.status_code in {401, 403}:
            raise EngineError(ErrorCode.ACCESS_DENIED, "早报限制访问，请在官网查看")
        if response.status_code == 404:
            raise EngineError(ErrorCode.NOT_FOUND, "该早报文章已不可用")
        response.raise_for_status()

    @staticmethod
    def _read(response: httpx.Response, cancel: threading.Event, maximum: int) -> tuple[bytes, str]:
        data = bytearray()
        for chunk in response.iter_bytes():
            check_cancel(cancel)
            data.extend(chunk)
            if len(data) > maximum:
                raise EngineError(ErrorCode.CONTENT_TOO_LARGE, "早报内容超出读取上限")
        return bytes(data), response.headers.get("content-type", "").lower()


def _retry_seconds(raw: str) -> float:
    try:
        return max(0, float(raw))
    except ValueError:
        try:
            return max(0, (parsedate_to_datetime(raw) - datetime.now(UTC)).total_seconds())
        except (TypeError, ValueError, OverflowError):
            return 60
