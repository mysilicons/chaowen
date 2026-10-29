"""文件名清洗。

站点提供的版名可能带全角冒号、书名号、斜杠等，直接做文件名会在 Windows 上炸。
"""

from __future__ import annotations

import re
from datetime import date as Date

# Windows 非法字符 + 控制字符
_INVALID = re.compile(r'[\\/:*?"<>|\x00-\x1f]')
_SPACES = re.compile(r"\s+")
MAX_LEN = 60


def safe_component(text: str, fallback: str = "") -> str:
    """清洗为可安全落盘的一段文件名。"""
    cleaned = _INVALID.sub("", text or "")
    cleaned = _SPACES.sub(" ", cleaned.replace("\u3000", " ")).strip()
    cleaned = cleaned.strip(". ")
    if len(cleaned) > MAX_LEN:
        cleaned = cleaned[:MAX_LEN].rstrip()
    return cleaned or fallback


def page_filename(page_no: int, title: str) -> str:
    """单版文件名：`01_要闻.pdf`，保证 ls 排序即版面顺序。"""
    name = safe_component(title, fallback=f"第{page_no:02d}版")
    return f"{page_no:02d}_{name}.pdf"


def merged_filename(d: Date) -> str:
    return f"人民日报_{d.isoformat()}.pdf"
