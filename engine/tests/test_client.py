"""E-04 验收：限速、重试、熔断。"""

from __future__ import annotations

import httpx
import pytest
import respx

from rmrb_engine.core.errors import EngineError, ErrorCode
from rmrb_engine.net.client import HttpClient
from rmrb_engine.net.limiter import TokenBucket

URL = "https://example.test/a"


def make_client(**kwargs) -> tuple[HttpClient, list[float]]:
    sleeps: list[float] = []
    limiter = TokenBucket(rate=1000, burst=1000, sleep=sleeps.append)
    client = HttpClient(
        client=httpx.Client(),
        limiter=limiter,
        jitter=0.0,
        sleep=sleeps.append,
        **kwargs,
    )
    return client, sleeps


def test_token_bucket_waits():
    now = [0.0]
    waits: list[float] = []

    def sleep(seconds: float) -> None:
        waits.append(seconds)
        now[0] += seconds

    bucket = TokenBucket(rate=1.0, burst=1.0, clock=lambda: now[0], sleep=sleep)

    assert bucket.acquire() == 0.0
    waited = bucket.acquire()
    assert waited == pytest.approx(1.0, abs=0.01)
    assert waits and waits[-1] == pytest.approx(1.0, abs=0.01)


def test_token_bucket_allows_burst_then_throttles():
    now = [0.0]
    bucket = TokenBucket(rate=2.0, burst=2.0, clock=lambda: now[0], sleep=lambda s: now.__setitem__(0, now[0] + s))

    assert bucket.acquire() == 0.0
    assert bucket.acquire() == 0.0
    assert bucket.acquire() == pytest.approx(0.5, abs=0.01)


def test_user_agent_is_identifiable():
    with respx.mock:
        route = respx.get(URL).mock(return_value=httpx.Response(200, text="ok"))
        client, _ = make_client()
        client.get_text(URL)

    assert "RMReader" in route.calls[0].request.headers["user-agent"]


def test_retry_on_5xx():
    with respx.mock:
        route = respx.get(URL).mock(
            side_effect=[
                httpx.Response(503),
                httpx.Response(503),
                httpx.Response(200, text="ok"),
            ]
        )
        client, _ = make_client()
        assert client.get_text(URL) == "ok"

    assert route.call_count == 3


def test_5xx_exhausts_retries():
    with respx.mock:
        route = respx.get(URL).mock(return_value=httpx.Response(500))
        client, _ = make_client()

        with pytest.raises(EngineError) as exc:
            client.get_text(URL)

    assert exc.value.code == ErrorCode.HTTP_ERROR
    assert route.call_count == 3


def test_404_is_retried_only_once():
    """实测有效 URL 会偶发 404，所以给一次机会；但不能无限重试。"""
    with respx.mock:
        route = respx.get(URL).mock(return_value=httpx.Response(404))
        client, _ = make_client()

        with pytest.raises(EngineError):
            client.get_text(URL)

    assert route.call_count == 2


def test_429_honours_retry_after():
    with respx.mock:
        route = respx.get(URL).mock(
            side_effect=[
                httpx.Response(429, headers={"Retry-After": "2"}),
                httpx.Response(200, text="ok"),
            ]
        )
        client, sleeps = make_client()
        assert client.get_text(URL) == "ok"

    assert route.call_count == 2
    assert any(abs(delay - 2.0) < 0.01 for delay in sleeps)


def test_circuit_opens_after_repeated_failures():
    with respx.mock:
        route = respx.get(URL).mock(return_value=httpx.Response(500))
        client, _ = make_client()

        with pytest.raises(EngineError):
            client.get_text(URL)
        with pytest.raises(EngineError):
            client.get_text(URL)

        with pytest.raises(EngineError) as exc:
            client.get_text(URL)

    assert exc.value.code == ErrorCode.CIRCUIT_OPEN
    assert route.call_count == 8


def test_success_resets_failure_counter():
    with respx.mock:
        route = respx.get(URL).mock(
            side_effect=[
                httpx.Response(500),
                httpx.Response(500),
                httpx.Response(200, text="ok"),
                httpx.Response(200, text="ok"),
            ]
        )
        client, _ = make_client()
        assert client.get_text(URL) == "ok"
        assert client.get_text(URL) == "ok"

    assert route.call_count == 4
