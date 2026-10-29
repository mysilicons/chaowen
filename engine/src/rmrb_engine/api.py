"""IPC 方法实现。

方法表见 docs/ipc.md。除 `download.start` 外，所有方法都是"一问一答"；
`download.start` 先回 jobId，再推送事件。
"""

from __future__ import annotations

import platform
from datetime import date as Date
from typing import Any

from . import __version__
from .core.errors import EngineError, ErrorCode
from .services.queue import DownloadService
from .store.repo import Repo

PROTOCOL_VERSION = 1


def parse_date(params: dict[str, Any]) -> Date:
    raw = params.get("date")
    if not raw or not isinstance(raw, str):
        raise EngineError(ErrorCode.BAD_REQUEST, "缺少参数 date")
    try:
        return Date.fromisoformat(raw)
    except ValueError as exc:
        raise EngineError(ErrorCode.BAD_REQUEST, f"日期格式错误：{raw}") from exc


class Engine:
    """把服务层能力暴露成协议方法。"""

    def __init__(self, service: DownloadService, repo: Repo) -> None:
        self.service = service
        self.repo = repo
        self._emit = lambda _event, _data: None
        self._job_seq = 0

    def bind_emitter(self, emit: Any) -> None:
        # 服务层的事件必须走同一条通道，否则下载进度到不了客户端
        self._emit = emit
        self.service.emit = emit

    @property
    def handlers(self) -> dict[str, Any]:
        return {
            "hello": self.hello,
            "issue.parse": self.issue_parse,
            "issue.status": self.issue_status,
            "library.month": self.library_month,
            "download.start": self.download_start,
        }

    # ------------------------------------------------------------------ #
    # 方法
    # ------------------------------------------------------------------ #

    def hello(self, params: dict[str, Any], ctx: Any) -> dict[str, Any]:
        return {
            "protocol": PROTOCOL_VERSION,
            "engine": __version__,
            "python": platform.python_version(),
        }

    def issue_parse(self, params: dict[str, Any], ctx: Any) -> dict[str, Any]:
        d = parse_date(params)
        issue = self.service.fetch_issue(d)
        # 版面列表只给当前页的图与直链；其余版用库里已解析过的结果补齐，
        # 避免为了 20 张缩略图再打 20 个请求（低速约束下的关键优化）。
        for page in issue.pages:
            record = self.repo.get_page(d, page.no)
            if not record:
                continue
            page.thumb_url = page.thumb_url or record["thumb_url"]
            page.pdf_url = page.pdf_url or record["pdf_url"]
            page.title = page.title or record["title"]
        return issue.dump()

    def issue_status(self, params: dict[str, Any], ctx: Any) -> dict[str, Any]:
        d = parse_date(params)
        record = self.repo.get_issue(d)
        if record is None:
            return {"date": d.isoformat(), "status": "absent", "pageCount": 0}
        return {
            "date": d.isoformat(),
            "status": record["status"],
            "pageCount": record["page_count"],
            "mergedPath": record["merged_path"],
            "bytes": record["bytes"],
            "singlesDeleted": bool(record["singles_deleted"]),
        }

    def library_month(self, params: dict[str, Any], ctx: Any) -> list[dict[str, Any]]:
        year = params.get("year")
        month = params.get("month")
        if not isinstance(year, int) or not isinstance(month, int):
            raise EngineError(ErrorCode.BAD_REQUEST, "year/month 必须是整数")
        if not 1 <= month <= 12:
            raise EngineError(ErrorCode.BAD_REQUEST, f"月份非法：{month}")

        return [
            {
                "date": row["date"],
                "status": row["status"],
                "bytes": row["bytes"],
                "pageCount": row["page_count"],
            }
            for row in self.repo.list_month(year, month)
        ]

    def download_start(self, params: dict[str, Any], ctx: Any) -> None:
        d = parse_date(params)
        pages = params.get("pages")
        self._job_seq += 1
        job_id = f"{d:%Y%m%d}-{self._job_seq}"

        # 先回执，再推事件：客户端不应阻塞等待任务完成
        ctx.respond({"jobId": job_id})

        try:
            # 成功路径的 job.finished 由服务层发出，这里不重复
            self.service.run_issue(d, pages=pages, job_id=job_id)
        except EngineError as exc:
            self._emit(
                "job.finished", {"jobId": job_id, "ok": False, "error": exc.to_envelope()}
            )
