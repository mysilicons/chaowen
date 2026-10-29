"""错误码与统一异常。"""

from __future__ import annotations

from enum import StrEnum


class ErrorCode(StrEnum):
    NO_ISSUE = "NO_ISSUE"
    PARSE_ERROR = "PARSE_ERROR"
    HTTP_ERROR = "HTTP_ERROR"
    TIMEOUT = "TIMEOUT"
    BAD_RESPONSE = "BAD_RESPONSE"
    CORRUPT = "CORRUPT"
    DISK_ERROR = "DISK_ERROR"
    MERGE_FAILED = "MERGE_FAILED"
    CIRCUIT_OPEN = "CIRCUIT_OPEN"
    UNKNOWN_METHOD = "UNKNOWN_METHOD"
    BAD_REQUEST = "BAD_REQUEST"


class EngineError(Exception):
    """引擎内部统一异常，最终会被转成 IPC 错误信封。"""

    def __init__(self, code: ErrorCode, message: str, detail: str | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.detail = detail

    def to_envelope(self) -> dict[str, object]:
        payload: dict[str, object] = {"code": self.code.value, "message": self.message}
        if self.detail:
            payload["detail"] = self.detail
        return payload


class ParseError(EngineError):
    def __init__(self, message: str, detail: str | None = None) -> None:
        super().__init__(ErrorCode.PARSE_ERROR, message, detail)
