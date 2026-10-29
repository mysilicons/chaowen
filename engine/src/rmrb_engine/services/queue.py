"""单期下载编排：解析 → 逐版下载 → 校验 → 合并 → 删单版 → 写清单。

低速是硬约束：默认串行、每版之间不并发，节流由 HttpClient 的令牌桶负责。
"""

from __future__ import annotations

import hashlib
import json
import shutil
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import date as Date
from pathlib import Path

from ..core.errors import EngineError, ErrorCode
from ..core.models import Issue, Manifest, ManifestPage, Page
from ..core.paths import LibraryPaths, layout_url
from ..net.client import HttpClient
from ..net.downloader import download
from ..site.parser import parse_layout, parse_page_detail
from ..store.repo import Repo
from .merge import merge_issue

Emitter = Callable[[str, dict], None]


@dataclass(slots=True)
class PageOutcome:
    no: int
    title: str
    status: str  # done | skipped | failed | planned
    size: int = 0
    error: str | None = None


@dataclass(slots=True)
class IssueResult:
    date: Date
    total: int
    done: int = 0
    skipped: int = 0
    failed: int = 0
    size: int = 0
    status: str = "pending"
    merged: Path | None = None
    merged_bytes: int = 0
    pages: list[PageOutcome] = field(default_factory=list)


class DownloadService:
    def __init__(
        self,
        http: HttpClient,
        repo: Repo,
        paths: LibraryPaths,
        *,
        emit: Emitter | None = None,
        min_bytes: int = 50 * 1024,
    ) -> None:
        self.http = http
        self.repo = repo
        self.paths = paths
        self.emit = emit or (lambda _event, _data: None)
        self.min_bytes = min_bytes

    # ------------------------------------------------------------------ #
    # 公开接口
    # ------------------------------------------------------------------ #

    def fetch_issue(self, d: Date) -> Issue:
        url = layout_url(d)
        html = self.http.get_text(url)
        return parse_layout(html, url)

    def run_issue(
        self,
        d: Date,
        *,
        pages: Sequence[int] | None = None,
        dry_run: bool = False,
        job_id: str = "local",
        merge: bool = True,
        delete_singles: bool = True,
    ) -> IssueResult:
        issue = self.fetch_issue(d)
        targets = [p for p in issue.pages if pages is None or p.no in pages]
        result = IssueResult(date=d, total=len(targets))

        if self._already_archived(d):
            result.status = "archived"
            result.skipped = len(targets)
            result.pages = [
                PageOutcome(no=p.no, title=p.title, status="skipped") for p in targets
            ]
            result.merged = self.paths.merged_pdf(d)
            self.emit("job.finished", {"jobId": job_id, "ok": True, "skipped": True})
            return result

        self.repo.save_issue(d, page_count=issue.page_count, status="downloading")

        if dry_run:
            result.pages = [
                PageOutcome(no=p.no, title=p.title, status="planned") for p in targets
            ]
            result.status = "planned"
            return result

        for index, page in enumerate(targets, start=1):
            outcome = self._process_page(d, page)
            result.pages.append(outcome)
            if outcome.status == "done":
                result.done += 1
                result.size += outcome.size
            elif outcome.status == "skipped":
                result.skipped += 1
                result.size += outcome.size
            else:
                result.failed += 1

            self.emit(
                "download.progress",
                {
                    "jobId": job_id,
                    "date": d.isoformat(),
                    "pageNo": page.no,
                    "done": index,
                    "total": len(targets),
                },
            )

        can_merge = result.failed == 0 and merge and len(targets) == issue.page_count
        if can_merge:
            result.merged, result.merged_bytes = self._finalize(
                d, issue, targets, delete_singles=delete_singles
            )
            result.status = "archived"
            self.emit(
                "issue.archived",
                {
                    "jobId": job_id,
                    "date": d.isoformat(),
                    "path": str(result.merged),
                    "bytes": result.merged_bytes,
                    "singlesDeleted": delete_singles,
                },
            )
        else:
            self.repo.save_issue(d, page_count=issue.page_count, status="partial")
            result.status = "partial"

        self.emit(
            "job.finished",
            {"jobId": job_id, "ok": result.failed == 0, "failed": result.failed},
        )
        return result

    # ------------------------------------------------------------------ #
    # 内部
    # ------------------------------------------------------------------ #

    def _already_archived(self, d: Date) -> bool:
        issue = self.repo.get_issue(d)
        if not issue or issue["status"] != "archived":
            return False
        merged = issue["merged_path"]
        return bool(merged) and Path(merged).exists()

    def _process_page(self, d: Date, page: Page) -> PageOutcome:
        dest = self.paths.single_pdf(d, page.no)
        record = self.repo.get_page(d, page.no)

        if record and record["status"] == "done" and dest.exists():
            return PageOutcome(
                no=page.no, title=page.title, status="skipped", size=dest.stat().st_size
            )

        try:
            if not page.pdf_url:
                self._fill_detail(page)
            if not page.pdf_url:
                raise EngineError(
                    ErrorCode.PARSE_ERROR, "未找到该版 PDF 链接", detail=page.url
                )
            result = download(self.http, page.pdf_url, dest, min_bytes=self.min_bytes)
            self.repo.save_page(
                d,
                page.no,
                status="done",
                title=page.title,
                pdf_url=page.pdf_url,
                thumb_url=page.thumb_url,
                file=dest.name,
                size=result.bytes,
                sha256=_sha256(dest),
            )
            self._cache_thumb(d, page)
            self.emit(
                "download.page",
                {
                    "date": d.isoformat(),
                    "pageNo": page.no,
                    "status": "done",
                    "bytes": result.bytes,
                },
            )
            return PageOutcome(no=page.no, title=page.title, status="done", size=result.bytes)
        except EngineError as exc:
            self.repo.save_page(
                d,
                page.no,
                status="failed",
                error_code=exc.code.value,
                bump_attempts=True,
            )
            self._cache_thumb(d, page)
            self.emit(
                "download.page",
                {
                    "date": d.isoformat(),
                    "pageNo": page.no,
                    "status": "failed",
                    "error": exc.code.value,
                },
            )
            return PageOutcome(
                no=page.no, title=page.title, status="failed", error=exc.code.value
            )

    def _cache_thumb(self, d: Date, page: Page) -> None:
        """顺手把版面缩略图存到本地，书架就不必再逐张联网。"""
        if not page.thumb_url:
            return
        target = self.paths.thumb_file(d, page.no)
        if target.exists() and target.stat().st_size > 1024:
            page.thumb_local = str(target)
            return
        try:
            data = self.http.get_bytes(page.thumb_url)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            page.thumb_local = str(target)
        except Exception:  # noqa: BLE001 - 缩略图是装饰性的，失败不能影响整期
            page.thumb_local = None

    def _fill_detail(self, page: Page) -> None:
        """版面列表只给目录，其余版的 PDF 直链要抓它自己的页面。"""
        html = self.http.get_text(page.url)
        detail = parse_page_detail(html, page.url, no=page.no)
        page.pdf_url = detail.pdf_url
        page.original_name = detail.original_name
        page.thumb_url = detail.thumb_url or page.thumb_url
        page.articles = detail.articles or page.articles
        if detail.title:
            page.title = detail.title

    def _finalize(
        self,
        d: Date,
        issue: Issue,
        targets: list[Page],
        *,
        delete_singles: bool,
    ) -> tuple[Path, int]:
        singles = [self.paths.single_pdf(d, page.no) for page in targets]
        titles = [page.title for page in targets]
        out = self.paths.merged_pdf(d)

        merged = merge_issue(singles, titles, out, issue_date=d)

        manifest_pages: list[ManifestPage] = []
        for page in targets:
            record = self.repo.get_page(d, page.no) or {}
            manifest_pages.append(
                ManifestPage(
                    page_no=page.no,
                    title=page.title,
                    original_name=page.original_name,
                    pdf_url=page.pdf_url,
                    bytes=record.get("bytes"),
                    sha256=record.get("sha256"),
                )
            )

        manifest = Manifest(
            date=d,
            page_count=issue.page_count,
            source=issue.source_url,
            merged=out.name,
            merged_bytes=merged.bytes,
            singles_deleted=delete_singles,
            pages=manifest_pages,
        )
        self.paths.manifest(d).write_text(
            json.dumps(manifest.dump(), ensure_ascii=False, indent=2), encoding="utf-8"
        )

        if delete_singles:
            shutil.rmtree(self.paths.tmp_dir(d), ignore_errors=True)

        self.repo.save_issue(
            d,
            page_count=issue.page_count,
            status="archived",
            merged_path=str(out),
            size=merged.bytes,
            singles_deleted=delete_singles,
        )
        return out, merged.bytes


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
