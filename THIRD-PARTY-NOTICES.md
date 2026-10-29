# 第三方组件声明

朝闻（ChaoWen）以二进制形式分发时包含下列第三方组件。各组件的完整许可证文本见其官方仓库或 `engine/.venv`、`app/pubspec.lock` 中记录的版本。

## 运行时与框架

| 组件 | 许可证 | 用途 |
| --- | --- | --- |
| Python 3.12 | PSF License 2.0 | 引擎运行时 |
| PyInstaller（bootloader） | GPL-2.0 **附 bootloader 例外条款** | 打包引擎为独立可执行文件 |

> PyInstaller 的 bootloader 例外明确允许将打包产物以任意许可证分发，因此不影响本项目的 MIT 许可。

## Python 依赖（引擎）

| 包 | 许可证 | 用途 |
| --- | --- | --- |
| httpx | BSD-3-Clause | HTTP 客户端 |
| selectolax | MIT | HTML 解析 |
| PyYAML | MIT | 规则配置 |
| pypdf | BSD-3-Clause | PDF 合并与书签 |
| pydantic | MIT | 数据模型与校验 |
| pydantic-settings | MIT | 配置加载 |
| platformdirs | MIT | 跨平台目录 |

## Flutter 依赖（界面）

| 包 | 许可证 | 用途 |
| --- | --- | --- |
| flutter_riverpod | MIT | 状态管理 |
| pdfrx | MIT | PDF 渲染 |
| file_selector | BSD-3-Clause | 目录选择对话框 |
| window_manager | MIT | 窗口控制 |
| path / intl | BSD-3-Clause | 路径与本地化 |

完整依赖树可通过 `flutter pub deps` 与 `uv pip list` 导出。Flutter 自身的许可证信息在应用内「About」对话框可查看。

## 字体

| 字体 | 许可证 | 说明 |
| --- | --- | --- |
| 思源宋体（Source Han Serif） | SIL Open Font License 1.1 | 见 `fonts/OFL.txt` |

**关于保留字体名（Reserved Font Name）**：思源宋体的 OFL 声明了保留字体名。本项目分发的字体是经**静态实例化**处理的修改版，因此已按 OFL 第 3 条要求，将字体内部名称更改为 `ChaoWen Serif`，不再使用原保留字体名。原版权声明与 OFL 许可证文本一并保留。

## 无关联声明

上述组件的作者与本项目无任何关联，也未对本项目提供背书。本项目亦不包含、不分发任何报纸内容。
