"""Remove the retired, narrowly scoped news image cache; never touch newspaper data."""

import logging
import shutil
from pathlib import Path


def purge_legacy_news(cache: Path) -> None:
    legacy = cache / "zaobao"
    if not legacy.exists():
        return
    if legacy.is_symlink() or legacy.is_junction():
        logging.getLogger("rmrb_engine").warning("legacy.news.cleanup refused_reparse_point")
        return
    root, target = cache.resolve(), legacy.resolve()
    if target.parent != root or target.name != "zaobao":
        raise ValueError("Invalid legacy news cache path")
    try:
        shutil.rmtree(target)
        logging.getLogger("rmrb_engine").info("legacy.news.cleanup completed")
    except OSError:
        logging.getLogger("rmrb_engine").warning("legacy.news.cleanup failed")
