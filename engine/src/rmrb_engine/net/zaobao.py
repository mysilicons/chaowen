"""Bounded, cancellable requests for the fixed .com source; never switches domains."""

from __future__ import annotations

import json
import logging
import threading
import time
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from urllib.parse import parse_qs, urljoin, urlsplit

import httpx

from ..core.errors import EngineError, ErrorCode
from ..services.control import Cancelled
from ..site.zaobao import FEED_URL, MORE_BASE, article_url, media_url, more_url
from .zaobao_signing import request_headers


def check_cancel(cancel: threading.Event) -> None:
    if cancel.is_set():
        raise Cancelled()


def _check_url(url: str) -> None:
    if url.startswith(MORE_BASE + "?"):
        query = parse_qs(urlsplit(url).query)
        try:
            page = int(query["pageNo"][0])
            if url == more_url(page):
                return
        except (KeyError, ValueError, EngineError):
            pass
        raise EngineError(ErrorCode.BAD_REQUEST, "不支持的早报分页地址")
    if url != FEED_URL and media_url(url) is None:
        article_url(url)


class ZaobaoHttp:
    def __init__(self, *, client: httpx.Client | None = None, interval: float = 0.5) -> None:
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

    def json(self, url: str, cancel: threading.Event) -> object:
        _check_url(url)
        page = int(parse_qs(urlsplit(url).query)["pageNo"][0])
        data, kind = self.request(
            url,
            cancel,
            max_bytes=5 * 1024 * 1024,
            headers={
                **request_headers(page),
                "Accept": "application/json",
                "Origin": "https://www.zaobao.com",
                "Referer": FEED_URL,
            },
        )
        if "application/json" not in kind:
            raise EngineError(ErrorCode.BAD_RESPONSE, "早报分页返回的不是 JSON")
        try:
            return json.loads(data)
        except (ValueError, UnicodeDecodeError) as exc:
            raise EngineError(ErrorCode.BAD_RESPONSE, "早报分页返回无效 JSON") from exc

    def request(
        self,
        url: str,
        cancel: threading.Event,
        *,
        max_bytes: int,
        headers: dict[str, str] | None = None,
    ) -> tuple[bytes, str]:
        _check_url(url)
        started = time.perf_counter()
        try:
            with self._lock:
                result = self._request(url, cancel, max_bytes, headers)
            logging.getLogger("rmrb_engine.http").info(
                "http.done host=%s path=%s elapsedMs=%.1f bytes=%d",
                urlsplit(url).netloc,
                urlsplit(url).path,
                (time.perf_counter() - started) * 1000,
                len(result[0]),
            )
            return result
        except EngineError as exc:
            logging.getLogger("rmrb_engine.http").warning(
                "http.failed host=%s path=%s code=%s",
                urlsplit(url).netloc,
                urlsplit(url).path,
                exc.code.value,
            )
            raise

    def _wait(self, cancel: threading.Event) -> None:
        if cancel.wait(max(0, self._next_request - time.monotonic())):
            raise Cancelled()
        check_cancel(cancel)
        self._next_request = time.monotonic() + self.interval

    def _request(
        self, url: str, cancel: threading.Event, maximum: int, headers: dict[str, str] | None = None
    ) -> tuple[bytes, str]:
        redirects = 0
        for attempt in range(3):
            try:
                while True:
                    self._wait(cancel)
                    with self.client.stream(
                        "GET", url, follow_redirects=False, headers=headers
                    ) as response:
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
