"""Bounded UTF-8 diagnostics, separate from the NDJSON and news data."""

from __future__ import annotations

import logging
import os
import sys
import tempfile
import threading
import traceback
from logging.handlers import RotatingFileHandler
from pathlib import Path

MAX_BYTES = 1024 * 1024
BACKUPS = 2
MAX_RECORD_BYTES = 8 * 1024


def log_directory() -> Path:
    override = os.environ.get("CHAOWEN_LOG_DIR")
    if override:
        return Path(override)
    return Path(os.environ.get("LOCALAPPDATA", tempfile.gettempdir())) / "rmrb-reader" / "logs"


class BoundedFormatter(logging.Formatter):
    def __init__(self, limit: int) -> None:
        super().__init__("%(asctime)s %(levelname)s %(name)s %(message)s")
        self.limit = min(limit, MAX_RECORD_BYTES)

    def format(self, record: logging.LogRecord) -> str:
        text = super().format(record)
        data = text.encode("utf-8")
        if len(data) > self.limit:
            return data[: max(0, self.limit - 4)].decode("utf-8", errors="ignore") + "..."
        return text


class ByteRotatingHandler(RotatingFileHandler):
    """The standard handler counts characters; UTF-8 needs a byte budget."""

    def _open(self):
        return open(
            self.baseFilename, self.mode, encoding=self.encoding, errors=self.errors, newline=""
        )

    def shouldRollover(self, record: logging.LogRecord) -> bool:
        if self.stream is None:
            self.stream = self._open()
        self.stream.seek(0, 2)
        size = len((self.format(record) + self.terminator).encode("utf-8"))
        return self.stream.tell() + size > self.maxBytes

    def emit(self, record: logging.LogRecord) -> None:
        # Multiple desktop instances share the same bounded file set.
        try:
            with open(Path(self.baseFilename).with_suffix(".lock"), "a+b") as lock:
                _lock(lock)
                try:
                    # Close between records, so another process may rotate on Windows.
                    if self.stream:
                        self.stream.close()
                        self.stream = None
                    super().emit(record)
                    if self.stream:
                        self.stream.close()
                        self.stream = None
                finally:
                    _unlock(lock)
        except OSError:
            # Failure to write diagnostics must not crash the application.
            return


def _lock(file) -> None:
    if sys.platform == "win32":
        import msvcrt

        file.seek(0)
        if not file.read(1):
            file.write(b"0")
            file.flush()
        file.seek(0)
        msvcrt.locking(file.fileno(), msvcrt.LK_NBLCK, 1)
    else:
        import fcntl

        fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)


def _unlock(file) -> None:
    if sys.platform == "win32":
        import msvcrt

        file.seek(0)
        msvcrt.locking(file.fileno(), msvcrt.LK_UNLCK, 1)
    else:
        import fcntl

        fcntl.flock(file, fcntl.LOCK_UN)


def configure_logging(
    directory: Path | None = None, *, max_bytes: int = MAX_BYTES, backup_count: int = BACKUPS
) -> logging.Logger:
    logger = logging.getLogger("rmrb_engine")
    for handler in logger.handlers[:]:
        handler.close()
        logger.removeHandler(handler)
    logger.propagate = False
    logger.setLevel(logging.INFO)
    try:
        directory = directory or log_directory()
        directory.mkdir(parents=True, exist_ok=True)
        handler = ByteRotatingHandler(
            directory / "engine.log",
            maxBytes=max_bytes,
            backupCount=backup_count,
            encoding="utf-8",
            delay=True,
        )
        handler.setFormatter(BoundedFormatter(max_bytes - 1))
        logger.addHandler(handler)
    except OSError:
        logger.addHandler(logging.NullHandler())
    return logger


def log_exception(event: str, error: BaseException, tb=None) -> None:
    # Never serialize exception payloads, request params, article bodies or locals.
    frames = traceback.extract_tb(tb or error.__traceback__)
    stack = "\n".join(f"  {frame.filename}:{frame.lineno} in {frame.name}" for frame in frames)
    logging.getLogger("rmrb_engine").error("%s type=%s\n%s", event, type(error).__name__, stack)


def install_exception_hooks() -> None:
    sys.excepthook = lambda kind, error, tb: log_exception("uncaught.main", error, tb)
    threading.excepthook = _thread_exception


def _thread_exception(args: threading.ExceptHookArgs) -> None:
    if args.exc_value is not None:
        log_exception("uncaught.thread", args.exc_value, args.exc_traceback)
