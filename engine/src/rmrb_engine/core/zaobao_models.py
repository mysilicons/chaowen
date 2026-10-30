"""The fixed China feed and independently readable articles."""

from typing import Literal

from pydantic import Field

from .models import Block, CamelModel


class ZaobaoSummary(CamelModel):
    article_id: str
    title: str
    url: str
    author: str | None = None
    published_at: str | None = None
    updated_at: str | None = None
    time_label: str | None = None
    thumbnail: str | None = None
    excerpt: str | None = None


class ZaobaoArticle(ZaobaoSummary):
    blocks: list[Block] = Field(default_factory=list)
    access: Literal["public", "subscriber", "login_required", "unknown"] = "unknown"
    content_state: Literal["full", "preview", "unknown", "unsupported"] = "unknown"
    parser_version: str = "zaobao-com/1"
    fetched_at: str | None = None
    warnings: list[str] = Field(default_factory=list)
