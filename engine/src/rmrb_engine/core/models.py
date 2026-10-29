"""数据模型：与 IPC 协议字段一一对应。"""

from __future__ import annotations

from datetime import date as Date

from pydantic import BaseModel, Field


class ArticleRef(BaseModel):
    """版面页上的"本版新闻"条目。"""

    title: str
    url: str


class Page(BaseModel):
    """一个版面（第 NN 版）。"""

    no: int
    title: str
    url: str
    pdf_url: str | None = None
    original_name: str | None = None
    thumb_url: str | None = None
    articles: list[ArticleRef] = Field(default_factory=list)


class Issue(BaseModel):
    """一期报纸。"""

    date: Date | None = None
    page_count: int = 0
    pages: list[Page] = Field(default_factory=list)
    source_url: str | None = None
