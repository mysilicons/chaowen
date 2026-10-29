"""用户配置：目前只有下载目录。

配置文件放在 platformdirs 的 user_config_dir 下，与状态库分开：
状态库可以随便删（重新扫描会重建），配置是用户意图，不能丢。
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from platformdirs import user_config_dir

_CONFIG_PATH = Path(user_config_dir("rmrb-reader")) / "settings.json"


def config_path() -> Path:
    return _CONFIG_PATH


def load() -> dict[str, Any]:
    try:
        return json.loads(_CONFIG_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save(patch: dict[str, Any]) -> dict[str, Any]:
    data = load()
    data.update(patch)
    _CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    _CONFIG_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return data


def download_dir() -> Path | None:
    raw = load().get("download_dir")
    return Path(raw) if raw else None
