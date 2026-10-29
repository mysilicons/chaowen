"""IPC 方法实现。

方法表见 docs/ipc.md。除 `download.start` 外，所有方法都是"一问一答"；
`download.start` 先回 jobId，再推送事件。
"""

from __future__ import annotations

import os
import platform
import subprocess
import sys
from datetime import date as Date
from pathlib import Path
from typing import Any

from . import __version__
from .core.errors import EngineError, ErrorCode
from .core.models import Issue, Page
from .core.paths import LibraryPaths, layout_url
from .services.article_service import ArticleService
from .services.queue import DownloadService
from .store import settings
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
        self.articles = ArticleService(service.http, repo, service.paths)

    def bind_emitter(self, emit: Any) -> None:
        # 服务层的事件必须走同一条通道，否则下载进度到不了客户端
        self._emit = emit
        self.service.emit = emit
        self.articles.emit = emit

    @property
    def handlers(self) -> dict[str, Any]:
        return {
            "hello": self.hello,
            "issue.parse": self.issue_parse,
            "issue.status": self.issue_status,
            "library.month": self.library_month,
            "article.page": self.article_page,
            "issue.page": self.issue_page,
            "download.start": self.download_start,
            "batch.start": self.batch_start,
            "storage.reveal": self.storage_reveal,
            "settings.get": self.settings_get,
            "settings.set": self.settings_set,
        }

    # ------------------------------------------------------------------ #
    # 方法
    # ------------------------------------------------------------------ #

    def hello(self, params: dict[str, Any], ctx: Any) -> dict[str, Any]:
        return {
            "protocol": PROTOCOL_VERSION,
            "engine": __version__,
            "python": platform.python_version(),
            "library": str(self.service.paths.library),
            "cache": str(self.service.paths.cache),
        }

    def issue_parse(self, params: dict[str, Any], ctx: Any) -> dict[str, Any]:
        d = parse_date(params)

        # 历史日期的目录几乎不会变：库里已有就直接返回，切日期零网络。
        # 当天仍然走网络（报纸可能在白天更新版面）。
        if d < Date.today():
            cached = self._issue_from_db(d)
            if cached is not None:
                return cached

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
        # 把这次解析到的版面写进库，供下次直接命中
        for page in issue.pages:
            self.repo.save_page(
                d,
                page.no,
                status="parsed",
                title=page.title,
                pdf_url=page.pdf_url,
                thumb_url=page.thumb_url,
            )
        return issue.dump()

    def _issue_from_db(self, d: Date) -> dict[str, Any] | None:
        rows = self.repo.list_pages(d)
        if not rows or any(not row["title"] for row in rows):
            return None

        base = layout_url(d).replace("node_01.html", "")
        pages = [
            Page(
                no=row["page_no"],
                title=row["title"],
                url=f"{base}node_{row['page_no']:02d}.html",
                pdf_url=row["pdf_url"],
                thumb_url=row["thumb_url"],
            )
            for row in rows
        ]
        return Issue(date=d, page_count=len(pages), pages=pages, source_url=f"{base}node_01.html").dump()

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

    def batch_start(self, params: dict[str, Any], ctx: Any) -> None:
        start = parse_date({"date": params.get("from")})
        end = parse_date({"date": params.get("to")})
        if end < start:
            raise EngineError(ErrorCode.BAD_REQUEST, "结束日期早于开始日期")
        days = (end - start).days + 1
        if days > 366:
            raise EngineError(ErrorCode.BAD_REQUEST, "一次最多 366 天")

        self._job_seq += 1
        job_id = f"batch-{start:%Y%m%d}-{self._job_seq}"
        ctx.respond(
            {
                "jobId": job_id,
                "days": days,
                "estBytes": days * 63 * 1024 * 1024,
                "estSeconds": days * 45,
            }
        )

        cursor = start
        index = 0
        while cursor <= end:
            index += 1
            self._emit(
                "batch.progress",
                {
                    "jobId": job_id,
                    "date": cursor.isoformat(),
                    "index": index,
                    "total": days,
                },
            )
            try:
                self.service.run_issue(cursor, job_id=job_id)
            except EngineError as exc:
                self._emit(
                    "batch.day",
                    {"jobId": job_id, "date": cursor.isoformat(), "error": exc.code.value},
                )
            cursor = cursor.fromordinal(cursor.toordinal() + 1)

        self._emit("job.finished", {"jobId": job_id, "ok": True, "days": days})

    def settings_get(self, params: dict[str, Any], ctx: Any) -> dict[str, Any]:
        return {
            "downloadDir": str(self.service.paths.library),
            "cacheDir": str(self.service.paths.cache),
            "speedProfile": os.environ.get("RMRB_RATE", "2"),
        }

    def settings_set(self, params: dict[str, Any], ctx: Any) -> dict[str, Any]:
        raw = params.get("downloadDir")
        if not isinstance(raw, str) or not raw.strip():
            raise EngineError(ErrorCode.BAD_REQUEST, "缺少 downloadDir")
        target = Path(raw).expanduser()
        try:
            target.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise EngineError(
                ErrorCode.DISK_ERROR, "目录不可用", detail=str(exc)
            ) from exc
        if not target.is_dir():
            raise EngineError(ErrorCode.BAD_REQUEST, f"不是目录：{target}")

        settings.save({"download_dir": str(target)})
        self.apply_library(target)
        return self.settings_get(params, ctx)

    def apply_library(self, path: Path) -> None:
        """切换下载目录：只换 LibraryPaths，不迁移文件。"""
        new_paths = LibraryPaths(library=path, cache=self.service.paths.cache)
        self.service.paths = new_paths
        self.articles.paths = new_paths

    def storage_reveal(self, params: dict[str, Any], ctx: Any) -> dict[str, Any]:
        """在系统文件管理器里定位下载目录（或某个文件）。"""
        raw = params.get("path")
        if not isinstance(raw, str) or not raw.strip():
            raise EngineError(ErrorCode.BAD_REQUEST, "缺少 path")
        target = Path(raw)
        if not target.exists():
            raise EngineError(ErrorCode.BAD_REQUEST, f"路径不存在：{raw}")

        if sys.platform == "win32":
            if target.is_dir():
                subprocess.Popen(["explorer", str(target)])  # noqa: S603
            else:
                subprocess.Popen(["explorer", "/select,", str(target)])  # noqa: S603
        elif sys.platform == "darwin":
            subprocess.Popen(["open", "-R" if target.is_file() else "", str(target)])  # noqa: S603
        else:
            subprocess.Popen(["xdg-open", str(target if target.is_dir() else target.parent)])  # noqa: S603

        return {"ok": True, "path": str(target)}

    def issue_page(self, params: dict[str, Any], ctx: Any) -> dict[str, Any]:
        """单版详情：缩略图、PDF 直链、本版文章。

        未下载的日期，版面列表里只有第 01 版带图；界面按需对每一版调这个方法，
        解析结果会写进 pages 表，第二次打开零请求。
        """
        d = parse_date(params)
        report = params.get("pageNo")
        if not isinstance(report, int) or not 1 <= report <= 40:
            raise EngineError(ErrorCode.BAD_REQUEST, "pageNo 非法")

        record = self.repo.get_page(d, report)
        if record and record["thumb_url"]:
            return {
                "no": report,
                "title": record["title"],
                "thumbUrl": record["thumb_url"],
                "pdfUrl": record["pdf_url"],
                "articles": [],
            }

        from .core.paths import layout_url
        from .site.parser import parse_page_detail

        node_url = layout_url(d).replace("node_01.html", f"node_{report:02d}.html")
        html = self.service.http.get_text(node_url)
        page = parse_page_detail(html, node_url, no=report)

        self.repo.save_page(
            d,
            report,
            status="parsed",
            title=page.title,
            pdf_url=page.pdf_url,
            thumb_url=page.thumb_url,
        )
        return {
            "no": page.no,
            "title": page.title,
            "thumbUrl": page.thumb_url,
            "pdfUrl": page.pdf_url,
            "articles": [a.model_dump(by_alias=True) for a in page.articles],
        }

    def article_page(self, params: dict[str, Any], ctx: Any) -> dict[str, Any]:
        d = parse_date(params)
        raw_no = params.get("pageNo")
        if not isinstance(raw_no, int) or not 1 <= raw_no <= 40:
            raise EngineError(ErrorCode.BAD_REQUEST, "pageNo 非法")
        refresh = bool(params.get("refresh"))
        return self.articles.fetch_page(d, raw_no, refresh=refresh)

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
