"""路径规划：下载目录（成品）与缓存目录（中间产物、文字缓存）分离。"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date as Date
from pathlib import Path

DEFAULT_BASE = "https://paper.people.com.cn/rmrb"


def layout_url(d: Date, base: str = DEFAULT_BASE) -> str:
    """某期第 01 版的版面页地址。"""
    return f"{base}/pc/layout/{d:%Y%m}/{d:%d}/node_01.html"


@dataclass(frozen=True, slots=True)
class LibraryPaths:
    """下载目录只放成品；缓存目录放单版临时文件与文字缓存。"""

    library: Path
    cache: Path

    # ---- 下载目录（成品） ----
    def issue_dir(self, d: Date) -> Path:
        return self.library / f"{d.year}" / d.isoformat()

    def merged_pdf(self, d: Date) -> Path:
        return self.issue_dir(d) / f"人民日报_{d.isoformat()}.pdf"

    def manifest(self, d: Date) -> Path:
        return self.issue_dir(d) / "manifest.json"

    # ---- 缓存目录（临时） ----
    def tmp_dir(self, d: Date) -> Path:
        return self.cache / "tmp" / d.isoformat()

    def single_pdf(self, d: Date, page_no: int) -> Path:
        return self.tmp_dir(d) / f"{page_no:02d}.pdf"
