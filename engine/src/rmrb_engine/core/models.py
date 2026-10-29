"""数据模型：字段与 IPC 协议（camelCase）一一对应。

Python 侧用 snake_case 书写，序列化时通过 alias_generator 转成 camelCase，
保证 `model_dump(by_alias=True)` 的输出可以直接作为协议载荷。
"""

from __future__ import annotations

from datetime import date as Date
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field


def to_camel(name: str) -> str:
    first, *rest = name.split("_")
    return first + "".join(word.capitalize() for word in rest)


class CamelModel(BaseModel):
    """对外输出 camelCase 的基类。"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    def dump(self) -> dict[str, object]:
        """协议载荷：camelCase 键 + JSON 友好值（日期/枚举转字符串）。"""
        return self.model_dump(by_alias=True, mode="json")


class ArticleRef(BaseModel):
    """版面页上的"本版新闻"条目。"""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    title: str
    url: str


class Page(CamelModel):
    """一个版面（第 NN 版）。"""

    no: int
    title: str
    url: str
    pdf_url: str | None = None
    original_name: str | None = None
    thumb_url: str | None = None
    articles: list[ArticleRef] = Field(default_factory=list)


class Issue(CamelModel):
    """一期报纸。"""

    date: Date | None = None
    page_count: int = 0
    pages: list[Page] = Field(default_factory=list)
    source_url: str | None = None


class BlockType(StrEnum):
    PARAGRAPH = "p"
    IMAGE = "img"


class Block(CamelModel):
    """正文中的有序块：段落或图片。"""

    type: BlockType
    text: str | None = None
    src: str | None = None
    local: str | None = None
    caption: str | None = None

    @classmethod
    def paragraph(cls, text: str) -> Block:
        return cls(type=BlockType.PARAGRAPH, text=text)

    @classmethod
    def image(cls, src: str, caption: str | None = None) -> Block:
        return cls(type=BlockType.IMAGE, src=src, caption=caption)


class Article(CamelModel):
    """一篇正文。"""

    title: str
    url: str
    author: str | None = None
    subtitle: str | None = None
    blocks: list[Block] = Field(default_factory=list)


class PageKind(StrEnum):
    NORMAL = "normal"
    SINGLE = "single"
    IMAGE_ONLY = "image_only"
    EMPTY = "empty"
    FAILED = "failed"


class JobStatus(StrEnum):
    QUEUED = "queued"
    DOWNLOADING = "downloading"
    PAUSED = "paused"
    DONE = "done"
    FAILED = "failed"


class Job(CamelModel):
    """一个下载任务。"""

    id: str
    date: Date
    total: int
    done: int = 0
    status: JobStatus = JobStatus.QUEUED


class ManifestPage(CamelModel):
    """manifest.json 中单个版面的记录（单版删除后仍保留，用于重下）。"""

    page_no: int
    title: str
    original_name: str | None = None
    pdf_url: str | None = None
    bytes: int | None = None
    sha256: str | None = None
    etag: str | None = None


class Manifest(CamelModel):
    """随目录走的清单，保证脱离数据库也能自解释。"""

    schema_version: int = Field(default=1, alias="schema")
    date: Date
    page_count: int
    layout: str = "v2"
    source: str | None = None
    merged: str | None = None
    merged_bytes: int | None = None
    singles_deleted: bool = False
    pages: list[ManifestPage] = Field(default_factory=list)

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
    )
