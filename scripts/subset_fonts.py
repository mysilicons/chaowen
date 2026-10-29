"""生成应用用的宋体子集：可变字体 → 静态字重 + GB2312 子集。

源字体是可变字体（fvar 轴 wght 250–900，默认值 250 = Light），
直接打包会有两个问题：
  1. 55–60 MB 的完整 CJK 字库，安装包无法接受；
  2. 默认字重是 250，不指定 variation 时正文会变得极细。

所以：先按 GB2312 + ASCII + 常用标点做子集，再实例化出 400/700 两个静态字重。

用法：
    uv run --with fonttools python scripts/subset_fonts.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "fonts" / "SourceHanSerifSC-VF.ttf"
OUT_DIR = ROOT / "fonts" / "subset"

WEIGHTS = {400: "Regular", 700: "Bold"}

EXTRA = "—…“”‘’《》〈〉【】、。，；：？！（）·￥　％＃＆＊＋－／"


def gb2312_charset() -> set[str]:
    """GB2312 可编码的全部字符 + ASCII + 常用标点。"""
    chars = {chr(c) for c in range(0x20, 0x7F)}
    for hi in range(0xA1, 0xFF):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                continue
    chars.update(EXTRA)
    return chars


def subset_and_instance(src: Path, out: Path, weight: int, chars: set[str]) -> None:
    font = TTFont(src)

    opts = Options()
    opts.name_IDs = ["*"]
    opts.name_legacy = True
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.drop_tables += ["BASE", "VORG", "vhea", "vmtx"]  # 纯横排应用用不到竖排表

    subsetter = Subsetter(options=opts)
    subsetter.populate(unicodes=[ord(c) for c in chars])
    subsetter.subset(font)

    if weight is not None:
        instantiateVariableFont(font, {"wght": weight}, inplace=True)

    out.parent.mkdir(parents=True, exist_ok=True)
    font.save(out)
    print(f"{out.name}: {out.stat().st_size / 1024 / 1024:.2f} MB, glyphs={font['maxp'].numGlyphs}")


def main() -> int:
    if not SRC.exists():
        print(f"缺少源字体：{SRC}", file=sys.stderr)
        return 1

    chars = gb2312_charset()
    print(f"目标字符集：{len(chars)} 个字符")

    for weight, style in WEIGHTS.items():
        out = OUT_DIR / f"SourceHanSerifSC-{style}.ttf"
        subset_and_instance(SRC, out, weight, chars)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
