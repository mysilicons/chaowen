"""版型判定：决定文字模式怎么渲染这一版。

实测站点存在几种极端版型：
- 常规版：6–8 篇文字稿；
- 单篇版：整版只有 1 篇（常见于广告版）；
- 图片版：整版是一张图（图片报道、整版广告），没有可读正文；
- 空版：列表为空。
"""

from __future__ import annotations

from collections.abc import Sequence

from ..core.models import Article, BlockType, PageKind

# 正文少于这个字数，基本可以判定为"图为主"
MIN_TEXT_CHARS = 60


def classify(articles: Sequence[Article]) -> PageKind:
    if not articles:
        return PageKind.EMPTY

    text_chars = sum(
        len(block.text or "")
        for article in articles
        for block in article.blocks
        if block.type == BlockType.PARAGRAPH
    )
    sum(
        1
        for article in articles
        for block in article.blocks
        if block.type == BlockType.IMAGE
    )

    if text_chars < MIN_TEXT_CHARS:
        return PageKind.IMAGE_ONLY
    if len(articles) == 1:
        return PageKind.SINGLE
    return PageKind.NORMAL
