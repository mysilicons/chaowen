"""Checksum used by the site's public China load-more client (Request bundle v2.1.2).

The inputs are the UTC clock, method, public path and pagination parameters.
No account, cookie, secret, subscription or private content is involved.
"""

from datetime import UTC, datetime

MASK = (1 << 64) - 1
C1 = 0x87C37B91114253D5
C2 = 0x4CF5AD432745937F


def _rotate(value: int, count: int) -> int:
    return ((value << count) | (value >> (64 - count))) & MASK


def _mix(value: int) -> int:
    value ^= value >> 33
    value = (value * 0xFF51AFD7ED558CCD) & MASK
    value ^= value >> 33
    value = (value * 0xC4CEB9FE1A85EC53) & MASK
    return value ^ (value >> 33)


def murmur128(text: str) -> str:
    data = text.encode("utf-8")
    h1 = h2 = 0
    end = len(data) // 16 * 16
    for offset in range(0, end, 16):
        k1 = int.from_bytes(data[offset : offset + 8], "little")
        k2 = int.from_bytes(data[offset + 8 : offset + 16], "little")
        h1 ^= (_rotate((k1 * C1) & MASK, 31) * C2) & MASK
        h1 = (_rotate(h1, 27) + h2) & MASK
        h1 = (h1 * 5 + 0x52DCE729) & MASK
        h2 ^= (_rotate((k2 * C2) & MASK, 33) * C1) & MASK
        h2 = (_rotate(h2, 31) + h1) & MASK
        h2 = (h2 * 5 + 0x38495AB5) & MASK
    tail = data[end:]
    if len(tail) > 8:
        k2 = int.from_bytes(tail[8:], "little")
        h2 ^= (_rotate((k2 * C2) & MASK, 33) * C1) & MASK
    if tail:
        k1 = int.from_bytes(tail[:8], "little")
        h1 ^= (_rotate((k1 * C1) & MASK, 31) * C2) & MASK
    h1 ^= len(data)
    h2 ^= len(data)
    h1 = (h1 + h2) & MASK
    h2 = (h2 + h1) & MASK
    h1, h2 = _mix(h1), _mix(h2)
    h1 = (h1 + h2) & MASK
    h2 = (h2 + h1) & MASK
    return f"{h1:016x}{h2:016x}"


def request_headers(page: int, at: datetime | None = None) -> dict[str, str]:
    at = (at or datetime.now(UTC)).astimezone(UTC).replace(microsecond=0)
    date = at.strftime("%Y-%m-%dT%H:%M:%SZ")
    stamp = str(int(at.timestamp()) * 1000)
    if at.day % 2:
        digits = stamp + "0" * (at.day % 5)
        key_input = "".join(str(ord(char)) for char in digits)
    else:
        key_input = "#".join(char for char in reversed(stamp) if char != "0")
    path = "%2Fmore%2Fsitemap%2F8"
    message = "\n".join([murmur128(key_input), date, "GET", path, f"pageNo={page}&pageSize=27"])
    return {"x-amz-date": date, "x-auth": murmur128(message)}
