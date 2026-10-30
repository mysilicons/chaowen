"""Public load-more request checksum; no user credential or subscriber access."""

from datetime import UTC, datetime

from rmrb_engine.net.zaobao_signing import murmur128, request_headers


def test_murmur_x64_reference_vectors():
    assert murmur128("") == "0" * 32
    assert murmur128("hello") == "cbd8a7b341bd9b025b1e906a48ae1d19"
    assert murmur128("foo") == "e271865701f545617eaf87e42bba7d87"


def test_signing_is_stable_for_same_public_request_and_changes_per_page():
    now = datetime(2026, 10, 30, 3, 0, 0, tzinfo=UTC)
    first = request_headers(2, now)
    assert first["x-amz-date"] == "2026-10-30T03:00:00Z"
    assert len(first["x-auth"]) == 32
    assert first == request_headers(2, now)
    assert first["x-auth"] != request_headers(3, now)["x-auth"]
    odd_day = datetime(2026, 10, 31, 3, 0, 0, tzinfo=UTC)
    assert len(request_headers(2, odd_day)["x-auth"]) == 32
    assert first["x-auth"] != request_headers(2, odd_day)["x-auth"]
