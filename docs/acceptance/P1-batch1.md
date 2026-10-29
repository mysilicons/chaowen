# P1 批次一验收记录 · E-01 / E-03 / E-04 / E-05

| 项 | 内容 |
| --- | --- |
| 日期 | 2026-10-29 |
| 范围 | 数据模型、正文解析、HTTP 客户端、下载器 |
| 前置 | E-02（版面解析）已通过，见 [E-02.md](E-02.md) |
| 结论 | **通过** |

---

## E-01 数据模型与错误码

| 检查 | 方法 | 实际 | 结论 |
| --- | --- | --- | --- |
| 模型可序列化 | `dump()` 输出 camelCase | `pageCount` / `pdfUrl` / `originalName` / `thumbUrl` / `mergedBytes` 全部正确，无 snake_case 泄漏 | ✅ |
| 双向兼容 | 构造与校验 | `Issue(page_count=2)` 与 `Issue.model_validate({"pageCount": 2})` 均可 | ✅ |
| 清单键名 | `Manifest.dump()` | 版本字段键为 `schema`（不是 `schemaVersion`），与 manifest.json 约定一致 | ✅ |
| 错误码穷举 | 枚举值集合比对 | 11 个码与 `docs/ipc.md §2.3` 完全一致 | ✅ |
| 错误信封 | `EngineError.to_envelope()` | `{code, message, detail}` 结构正确 | ✅ |

## E-03 正文解析

| 检查 | 方法 | 实际 | 结论 |
| --- | --- | --- | --- |
| 常规长文 | `content_30188305.html` | 标题含「更加清醒坚定」，**29 个段落块**，1686 字，全为 `p` | ✅ |
| 作者提取 | 同上 | `本报记者  张  洋`（**内部双空格保留**，有版式含义） | ✅ |
| 图片报道 | `content_30188309.html` | 首块 `img`（URL 绝对化到 `/rmrb/pc/pic/…`），后续 **3 个段落** | ✅ |
| 缩进已清理 | 全部段落 | 无以全角空格/半角空格开头，缩进交给前端 | ✅ |
| 缺 `enpcontent` | 删掉标记后解析 | 回退到 `div.article`，正文不丢 | ✅ |
| 缺元数据注释 | 改坏 `enpproperty` | `author=None`，不抛异常 | ✅ |
| 结构异常 | 空 HTML / 无标题 | 抛 `ParseError`，消息含「标题」 | ✅ |

CLI 实测：

```
$ uv run python -m rmrb_engine --article ..\_probe\content_30188305.html
title=“更加清醒坚定地推进反腐败斗争”（总书记的人民情怀）
author=本报记者  张  洋 blocks=29 images=0 chars=1686

$ uv run python -m rmrb_engine --article ..\_probe\content_30188309.html
title=图片报道
author=None blocks=4 images=1 chars=66
```

## E-04 HTTP 客户端

| 检查 | 方法 | 实际 | 结论 |
| --- | --- | --- | --- |
| 限速生效 | 令牌桶单测（注入时钟） | 突发 1 次后，第 2 次等待 1.00 s；rate=2 时第 3 次等待 0.50 s | ✅ |
| 5xx 重试 | respx 503→503→200 | 第 3 次成功，`call_count == 3` | ✅ |
| 重试耗尽 | 恒 500 | 恰好发 3 次后抛 `HTTP_ERROR` | ✅ |
| 404 只重试一次 | 恒 404 | `call_count == 2` 后抛错 | ✅ |
| 429 遵守 Retry-After | 429(Retry-After: 2) → 200 | 睡眠 2.00 s 后成功 | ✅ |
| 熔断 | 恒 500 连续请求 | 第 **8** 次请求时抛 `CIRCUIT_OPEN`，不再发请求 | ✅ |
| 失败计数重置 | 500,500,200,200 | 4 次调用全部完成，未误触熔断 | ✅ |
| UA 可识别 | 断言请求头 | 含 `RMReader` | ✅ |

## E-05 下载器

| 检查 | 方法 | 实际 | 结论 |
| --- | --- | --- | --- |
| 正常下载 | 200 全量 | 文件完整、无 `.part` 残留、`resumed=False` | ✅ |
| 断点续传 | 预置 2000 B `.part` + 206 | 请求头 `Range: bytes=2000-`，`resumed=True`，结果字节完全一致 | ✅ |
| 服务端忽略 Range | 200 全量 | 覆盖重下，`resumed=False` | ✅ |
| 非 PDF | 返回 HTML | 抛 `BAD_RESPONSE`，目标文件不存在，`.part` 被清理 | ✅ |
| 体积过小 | 返回 9 字节 | 抛 `BAD_RESPONSE`，目标文件不存在 | ✅ |
| 中途断流 | 流式响应抛 `ReadError` | 目标文件不存在，仅剩 `.part`（未落盘部分不计） | ✅ |

---

## 实施偏差（5 项，均已修正）

| # | 问题 | 处理 |
| --- | --- | --- |
| 1 | **正文页存在 2 个 `enpcontent` 区间**（内容重复的模板外壳），原先取首个非贪婪匹配，抓到的是较短的那个 | 改为取**最长**片段；实测两个片段同为 29 段，内容一致，取最长不会丢正文 |
| 2 | **重试次数差一**：`attempts=3` 实际发了 4 次请求 | 语义改为「总尝试次数」，条件改为 `attempt + 1 >= attempts`；熔断用例仍精确落在第 8 次 |
| 3 | **注入自定义 `httpx.Client` 时 UA 丢失**（UA 只设在默认客户端上） | 改为**逐请求合并**默认头，任何客户端都能带上 UA |
| 4 | `pytest` 系统临时目录 `%TEMP%\pytest-of-GW` 报 `PermissionError`（本机历史 ACL 问题） | `addopts` 增加 `--basetemp=.pytest-tmp`，改到仓库内；已加入 `.gitignore` |
| 5 | 原计划断言「正文 > 3000 字」**没有依据** | 实测 29 段 / 1686 字才是真实值；改为断言块数（更稳定，不会随标点统计漂移） |

## 测试汇总

```
$ uv run pytest -q
..........................................  [100%]  42 passed

$ uv run ruff check .
All checks passed!
```

| 文件 | 用例数 | 覆盖 |
| --- | --- | --- |
| `test_parser.py` | 12 | E-02 版面解析 |
| `test_models.py` | 8 | E-01 模型与错误码 |
| `test_article.py` | 7 | E-03 正文解析 |
| `test_client.py` | 9 | E-04 限速/重试/熔断 |
| `test_downloader.py` | 6 | E-05 续传/原子写/校验 |

## 对后续任务的影响

- **E-06/E-07 可直接复用** `HttpClient` + `download()`，编排层只需处理"逐版调用 + 事件上报"；
- `Issue.dump()` 已是协议格式，E-09 的方法实现可以直接返回，不需要额外转换；
- 正文 blocks 结构已定型（`p` / `img`），E-10 的缓存与 E-11 的版型判定都以它为准。
