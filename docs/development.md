# 开发说明

面向要改代码、重新构建或了解实现的人。普通使用请回到 [README](../README.md)。

## 架构

```
Flutter 应用（界面 + PDF 渲染 + 文字排版）
        ↕  NDJSON / stdio
Python 引擎（抓取 + 解析 + 合并 + SQLite）
```

界面和引擎是两个进程：Flutter 负责呈现，Python 负责联网、解析、落盘与合并，通过 stdin/stdout 上的 NDJSON 通信。引擎随安装包分发（PyInstaller onedir），用户机器上不需要装 Python。

详细设计见 [技术设计文档](人民日报阅报器-需求分析与技术设计.md)，协议见 [IPC 协议](ipc.md)。

## 目录

```
app/        Flutter 桌面应用
engine/     Python 引擎（uv 管理）
docs/       设计文档、开发计划、协议、验收记录
fonts/      字体源文件
scripts/    构建与工具脚本
_probe/     线上抓取的真实样本（测试夹具）
```

## 环境要求

| 依赖 | 版本 | 说明 |
| --- | --- | --- |
| Flutter | ≥ 3.47.0 | `pdfrx 2.10.1` 的下限 |
| Visual Studio | 2022/2026 + C++ 桌面开发 | Windows 构建必需 |
| Python | 3.12 | 由 uv 管理 |
| uv | ≥ 0.12 | `uv sync` 还原依赖 |
| Node.js | 18+ | 仅构建安装包时需要（取 ISCC 用） |

> **Windows 必读**：必须开启「设置 → 系统 → 开发者选项 → 开发人员模式」。
> 否则任何含插件的 `flutter build windows` 都会失败并提示 `Building with plugins requires symlink support`。

## 从源码运行

```powershell
cd engine
uv sync

cd ..\app
flutter pub get
flutter run -d windows
```

## 构建发布包

```powershell
# 1. 引擎（PyInstaller onedir）
cd engine
uv run pyinstaller --noconfirm --clean --onedir --name rmrb_engine --paths src `
  --distpath dist --workpath build packaging/entry.py

# 2. 应用
cd ..\app
flutter build windows --release

# 3. 把引擎塞进 Release 目录
Copy-Item -Recurse ..\engine\dist\rmrb_engine build\windows\x64\runner\Release\engine

# 4. 安装包（首次会自动通过 npm 取 ISCC 编译器）
pwsh ..\scripts\build_installer_inno.ps1
```

产物：`dist\Chaowen-<版本>-setup.exe`。

版本号需要一起改的地方：`scripts/installer.iss` 的 `AppVersion` 与 `VersionInfoVersion`、`app/pubspec.yaml` 的 `version`、`app/lib/views/settings_view.dart` 的版本文案、`app/lib/core/engine_client.dart` 的 client 标识、`engine/src/rmrb_engine/__init__.py` 与 `engine/pyproject.toml` 的版本，以及新增的 `docs/release-notes-<版本>.md`。

## 测试

```powershell
cd engine
uv run pytest -q --basetemp=.pytest-tmp

cd ..\app
flutter analyze
flutter test
```

> `--basetemp` 是必需的：默认临时目录在这台机器上会有 pytest 的 `PermissionError`。

## 字体

`fonts/` 下是思源宋体可变字体源文件。应用打包的是**完整字库**的静态实例（各 33.9 MB / 6.5 万字），由脚本生成：

```powershell
uv run --with fonttools python scripts/build_fonts.py            # 完整字库（默认）
uv run --with fonttools python scripts/build_fonts.py --subset   # GB2312 子集（体积敏感时）
```

> 源字体是可变字体（`wght` 250–900，**默认 250**），直接使用会得到极细的字重，必须先实例化。
> 字体许可为 SIL OFL 1.1，`fonts/OFL.txt` 随发布包分发。

## 项目状态

v0.2.0 已可交付：书架 / 双模式阅读 / 单日与批量下载 / 联合早报中国频道阅读 / 安装包（支持覆盖升级）。
进度以 [开发计划书](人民日报阅报器-开发计划书.md) 为准，验收记录在 `docs/acceptance/`。

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| P0 | 工程准备 | ✅ |
| P1 | 引擎核心 | ✅ |
| P2 | 链路打通 | ✅ |
| P3 | 双模式阅读 | ✅ |
| P4 | 打磨交付 | ✅ |
