"""命名与路径规划。"""

from __future__ import annotations

from datetime import date

from rmrb_engine.core.naming import merged_filename, page_filename, safe_component
from rmrb_engine.core.paths import LibraryPaths, layout_url


def test_safe_component_strips_windows_forbidden_chars():
    assert safe_component('要闻/评论: 特稿"') == "要闻评论 特稿"
    assert safe_component("第01版：要闻") == "第01版：要闻"  # 全角冒号合法


def test_safe_component_falls_back():
    assert safe_component("///", fallback="第09版") == "第09版"
    assert safe_component("   ") == ""


def test_safe_component_truncates():
    assert len(safe_component("评" * 100)) == 60


def test_page_filename_zero_pads():
    assert page_filename(1, "要闻") == "01_要闻.pdf"
    assert page_filename(20, "副刊") == "20_副刊.pdf"


def test_merged_filename():
    assert merged_filename(date(2026, 10, 29)) == "人民日报_2026-10-29.pdf"


def test_layout_url():
    assert (
        layout_url(date(2026, 10, 29))
        == "https://paper.people.com.cn/rmrb/pc/layout/202610/29/node_01.html"
    )


def test_library_paths_layout(tmp_path):
    paths = LibraryPaths(library=tmp_path / "lib", cache=tmp_path / "cache")
    d = date(2026, 10, 29)

    assert paths.issue_dir(d) == tmp_path / "lib" / "2026" / "2026-10-29"
    assert paths.merged_pdf(d).name == "人民日报_2026-10-29.pdf"
    assert paths.tmp_dir(d) == tmp_path / "cache" / "tmp" / "2026-10-29"
    assert paths.single_pdf(d, 3).name == "03.pdf"
