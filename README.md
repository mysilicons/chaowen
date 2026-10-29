# 朝闻 · 人民日报阅报器

一个**个人使用**的《人民日报》桌面阅报器：像翻报纸一样浏览版面，像读网页一样读正文，需要留档时一键下载并合成整期 PDF。

> **合规声明（重要）**
> 本工具仅用于**个人学习与研究**的本地存档与阅读，默认以极低速率访问站点（1 并发、1 秒间隔），不提供任何分享、镜像或对外分发功能。
> 《人民日报》（电子版）版权声明明确：内容"仅供人民网读者阅读、学习研究使用"，未经授权不得用于商业目的、转载、镜像或制作数据库。
> 使用者应自行确保使用方式符合该声明及当地法律法规，**不得**将本工具用于批量分发或商业用途。

## 项目状态

**v0.1.0 已可交付**：书架 / 双模式阅读 / 单日与批量下载 / 打包为免安装目录。
进度以 [开发计划书](docs/人民日报阅报器-开发计划书.md) 为准：

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| P0 | 工程准备 | ✅ 已完成 |
| P1 | 引擎核心 | ✅ 已完成（78 单测 + G1 验收） |
| P2 | 链路打通 | ✅ 已完成（书架 + 下载中心） |
| P3 | 双模式阅读 | ✅ 已完成（PDF + 文字） |
| P4 | 打磨交付 | ✅ 已完成（便携目录 151 MB，含完整字库） |

## 架构

```
Flutter 应用（界面 + PDF 渲染 + 文字排版）
        ↕  NDJSON / stdio
Python 引擎（抓取 + 解析 + 合并 + SQLite）
```

详细设计见 [技术设计文档](docs/人民日报阅报器-需求分析与技术设计.md)，前后端协议见 [IPC 协议](docs/ipc.md)。

## 目录

```
app/        Flutter 桌面应用
engine/     Python 引擎（uv 管理）
docs/       设计文档、开发计划、协议、验收记录
fonts/      字体源文件与子集
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

> **Windows 必读**：必须开启「设置 → 系统 → 开发者选项 → 开发人员模式」。
> 否则任何含插件的 `flutter build windows` 都会失败并提示 `Building with plugins requires symlink support`。

## 安装

双击 `dist\朝闻-0.1.0-setup.exe`（Inno Setup 构建，54 MB）：

- 安装到 `%LOCALAPPDATA%\Programs\朝闻`（当前用户，不需要管理员，也可切换为全局安装）
- 可选是否创建桌面快捷方式，安装完可直接启动
- 控制面板 →「朝闻」可卸载，自带标准卸载器
- 卸载**不会**删除已下载的报纸和缓存

重新构建：`pwsh scripts/build_installer_inno.ps1`
（脚本会自动通过 npm 取 ISCC 编译器，本机未安装 Inno Setup 也能用）

## 快速开始

**用打包好的版本**：运行 `scripts/package.ps1`，产物在 `dist\人民日报阅报器\`，双击 `rmrb_reader.exe` 即可（不需要装 Python 或 Flutter）。

**从源码跑**：

```powershell
cd engine
uv sync

cd ..\app
flutter pub get
flutter run -d windows
```

**打包**：

```powershell
pwsh scripts/package.ps1
```

## 字体

`fonts/` 下是思源宋体可变字体源文件。应用打包的是**完整字库**的静态实例（各 33.9 MB / 6.5 万字），由脚本生成：

```powershell
uv run --with fonttools python scripts/build_fonts.py            # 完整字库（默认）
uv run --with fonttools python scripts/build_fonts.py --subset   # GB2312 子集（体积敏感时）
```

> 源字体是可变字体（`wght` 250–900，**默认 250**），直接使用会得到极细的字重，必须先实例化。
> 字体许可为 SIL OFL 1.1，`fonts/OFL.txt` 随发布包分发。

## 许可证

代码仅供个人学习使用。字体为思源宋体（SIL Open Font License 1.1）。
