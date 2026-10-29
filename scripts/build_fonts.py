"""从可变字体生成应用用的字体文件。

两种模式：
- 默认（full）：完整字库，实例化 400/700 两个字重，**不做裁剪**。
  单文件约 34 MB，覆盖 6.5 万字形；应用因此不依赖系统字体兜底。
- `--subset`：只保留 GB2312 + ASCII + 常用标点（约 5.5 MB/字重），
  用于体积敏感的场景（旧版打包方式）。

源字体是可变字体（fvar 轴 wght 250–900，默认 250），必须实例化：
直接使用会让正文变成极细的 Light 字重，而且 57 MB 无法接受。

用法：
    uv run --with fonttools python scripts/build_fonts.py
    uv run --with fonttools python scripts/build_fonts.py --subset
"""

from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path

from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "fonts" / "SourceHanSerifSC-VF.ttf"
OUT_DIR = ROOT / "fonts" / "app"
APP_ASSETS = ROOT / "app" / "assets" / "fonts"

WEIGHTS = {400: "Regular", 700: "Bold"}

EXTRA = "—…“”‘’《》〈〉【】、。，；：？！（）·￥　％＃＆＊＋－／"


def gb2312_charset() -> set[str]:
    chars = {chr(c) for c in range(0x20, 0x7F)}
    for hi in range(0xA1, 0xFF):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                continue
    chars.update(EXTRA)
    return chars


def build(weight: int, style: str, *, subset: bool) -> Path:
    started = time.time()
    font = TTFont(SRC)

    if subset:
        opts = Options()
        opts.name_IDs = ["*"]
        opts.name_legacy = True
        opts.name_languages = ["*"]
        opts.notdef_outline = True
        opts.recalc_bounds = True
        opts.drop_tables += ["BASE", "VORG", "vhea", "vmtx"]

        subsetter = Subsetter(options=opts)
        subsetter.populate(unicodes=[ord(c) for c in gb2312_charset()])
        subsetter.subset(font)

    instantiateVariableFont(font, {"wght": weight}, inplace=True)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"SourceHanSerifSC-{style}.ttf"
    font.save(out)
    print(
        f"  {out.name}: {out.stat().st_size / 1024 / 1024:.1f} MB, "
        f"字形={font['maxp'].numGlyphs}, 耗时={time.time() - started:.0f}s"
    )
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--subset", action="store_true", help="裁剪为 GB2312 子集")
    parser.add_argument("--no-copy", action="store_true", help="只生成，不复制进应用资源")
    args = parser.parse_args()

    if not SRC.exists():
        print(f"缺少源字体：{SRC}", file=sys.stderr)
        return 1

    mode = "GB2312 子集" if args.subset else "完整字库"
    print(f"生成{mode}（源 {SRC.stat().st_size / 1024 / 1024:.1f} MB）")

    outputs = [build(weight, style, subset=args.subset) for weight, style in WEIGHTS.items()]

    if not args.no_copy:
        APP_ASSETS.mkdir(parents=True, exist_ok=True)
        for path in outputs:
            shutil.copy2(path, APP_ASSETS / path.name)
        print(f"已复制到 {APP_ASSETS}")

    total = sum(path.stat().st_size for path in outputs) / 1024 / 1024
    print(f"合计：{total:.1f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
