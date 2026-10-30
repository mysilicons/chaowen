# 前后端 IPC 协议 v1

Flutter 应用（客户端）与 Python 引擎（服务端）之间的本地通信协议。**本文件是冻结版本**，两侧实现必须严格遵循。

---

## 1. 传输

| 项 | 约定 |
| --- | --- |
| 通道 | 引擎子进程的 `stdin` / `stdout` |
| 编码 | UTF-8，**无 BOM** |
| 分帧 | 一行一条 JSON（NDJSON），`\n` 结尾 |
| stderr | **仅供日志**，不参与协议 |
| 生命周期 | 由应用 `Process.start` 拉起，应用退出时终止 |

### 1.1 三条硬性规则

1. **stdout 只允许出现协议 JSON**。任何 `print()` 都是缺陷 —— 会污染流并使客户端 `jsonDecode` 失败。
2. **一条消息必须在一行内完成**。禁止把 JSON 格式化成多行输出。
3. **单条消息上限 1 MB**。超限消息双方都应丢弃并报错，防止内存被拖垮。

> Windows 上还必须在引擎启动时 `sys.stdout.reconfigure(encoding="utf-8")`，
> 否则默认代码页会写出非 UTF-8 字节，中文与全角标点直接损坏。

---

## 2. 信封

### 2.1 请求（客户端 → 引擎）

```json
{"id": 1, "method": "issue.parse", "params": {"date": "2026-10-29"}}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | int | 是 | 正整数，客户端自增；响应必须回填同一值 |
| `method` | string | 是 | 见 §3 |
| `params` | object | 否 | 缺省视为 `{}` |

### 2.2 成功响应（引擎 → 客户端）

```json
{"id": 1, "ok": true, "result": {"date": "2026-10-29", "pageCount": 20, "pages": []}}
```

### 2.3 失败响应

```json
{"id": 1, "ok": false, "error": {"code": "PARSE_ERROR", "message": "未找到版面列表", "detail": "selector=div.swiper-slide a[id=\"pageLink\"] matched 0"}}
```

| `code` | 含义 |
| --- | --- |
| `NO_ISSUE` | 该日期无报纸（404/403 重试后仍失败） |
| `PARSE_ERROR` | 页面结构变化，选择器未命中 |
| `HTTP_ERROR` | 4xx/5xx 重试耗尽 |
| `TIMEOUT` | 超时 |
| `BAD_RESPONSE` | 返回内容不是 PDF / 非预期类型 |
| `CORRUPT` | 文件校验不通过 |
| `DISK_ERROR` | 磁盘或权限问题 |
| `MERGE_FAILED` | 合并或合并后校验失败 |
| `CIRCUIT_OPEN` | 连续失败触发熔断 |
| `UNKNOWN_METHOD` | 方法不存在 |
| `BAD_REQUEST` | 参数非法 |

### 2.4 事件（引擎 → 客户端，无 `id`）

```json
{"event": "download.progress", "data": {"jobId": "20261029-1", "date": "2026-10-29", "pageNo": 17, "done": 16, "total": 20}}
```

客户端按 `event` 字段路由；无法识别的事件必须**忽略**而不是报错（向前兼容）。

---

## 3. 方法表

状态列：**P1** = 引擎核心阶段实现，**P3/P4** = 后续阶段。

| method | 参数 | 返回 | 阶段 |
| --- | --- | --- | --- |
| `hello` | `{"protocol": 1, "client": "rmrb-reader/0.1.0"}` | `{"protocol": 1, "engine": "0.1.0", "python": "3.12.14"}` | P1 |
| `issue.parse` | `{"date": "YYYY-MM-DD"}` | `Issue` | P1 |
| `issue.status` | `{"date": "YYYY-MM-DD"}` | `{"status": "archived", "pageCount": 20, "mergedPath": "…", "bytes": 23489152}` | P1 |
| `download.start` | `{"date": "YYYY-MM-DD", "pages": [1,2] \| null}` | `{"jobId": "20261029-1"}` | P1 |
| `download.pause` | `{"jobId": "…"}` | `{"ok": true}` | P2 |
| `download.resume` | `{"jobId": "…"}` | `{"ok": true}` | P2 |
| `download.cancel` | `{"jobId": "…"}` | `{"ok": true}` | P2 |
| `batch.start` | `{"from": "…", "to": "…", "skipExisting": true}` | `{"jobId": "…", "days": 29, "estBytes": 566231040, "estSeconds": 2290}` | P4 |
| `library.month` | `{"year": 2026, "month": 10}` | `[{"date": "…", "status": "archived", "bytes": 23489152}]` | P2 |
| `article.page` | `{"date": "…", "pageNo": 1, "refresh": false}` | `ArticlePage` | P3 |
| `merge.retry` | `{"date": "…"}` | `{"ok": true, "path": "…"}` | P4 |
| `settings.get` | `{}` | `Settings` | P4 |
| `settings.set` | `{"patch": {"speedProfile": "saver"}}` | `Settings` | P4 |
| `storage.stats` | `{}` | `{"bytes": 6657199309, "byYear": [{"year": 2026, "bytes": 123}]}` | P4 |
| `reveal` | `{"path": "…"}` | `{"ok": true}` | P4 |

### 3.1 数据结构

**Issue**

```json
{
  "date": "2026-10-29",
  "pageCount": 20,
  "sourceUrl": "https://paper.people.com.cn/rmrb/pc/layout/202610/29/node_01.html",
  "pages": [
    {
      "no": 1,
      "title": "要闻",
      "url": "…/node_01.html",
      "pdfUrl": "…/attachement/202610/29/<uuid>.pdf",
      "originalName": "rmrb2026102901.pdf",
      "thumbUrl": "…/pic/202610/29/<uuid>.jpg.2",
      "articles": [{"title": "…", "url": "…/content_30188305.html"}]
    }
  ]
}
```

**ArticlePage**

```json
{
  "date": "2026-10-29",
  "pageNo": 1,
  "title": "要闻",
  "kind": "normal",
  "articles": [
    {
      "title": "…",
      "author": "本报记者  张  洋",
      "subtitle": null,
      "url": "…",
      "blocks": [
        {"type": "p", "text": "在纪念中国工农红军长征胜利90周年大会上…"},
        {"type": "img", "src": "https://…/pic/…jpg", "local": "C:/…/cache/img/ab12.jpg", "caption": "图为…"}
      ]
    }
  ]
}
```

`kind` 取值：`normal` | `single` | `image_only` | `empty` | `failed`。

**Settings**

```json
{
  "downloadDir": "D:/Newspaper/人民日报",
  "autoMerge": true,
  "deleteSinglesAfterMerge": true,
  "speedProfile": "standard",
  "theme": "light",
  "fontSize": 17
}
```

---

## 4. 事件表

| event | 载荷 | 触发时机 |
| --- | --- | --- |
| `download.progress` | `{jobId, date, pageNo, done, total, bytesPerSec}` | 每完成一版 |
| `download.page` | `{jobId, date, pageNo, status, error?}` | 单版状态变化 |
| `article.progress` | `{date, pageNo, done, total}` | 文字模式抓取中 |
| `issue.archived` | `{date, path, bytes, singlesDeleted}` | 合并成功且单版已删 |
| `job.finished` | `{jobId, ok, error?}` | 任务结束（成功或失败） |

---

## 5. 时序示例

### 5.1 握手

```
→ {"id":0,"method":"hello","params":{"protocol":1,"client":"rmrb-reader/0.1.0"}}
← {"id":0,"ok":true,"result":{"protocol":1,"engine":"0.1.0","python":"3.12.14"}}
```

协议号不一致时，客户端必须提示"引擎版本不匹配"并停止调用，而不是带病运行。

### 5.2 下载一期

```
→ {"id":5,"method":"download.start","params":{"date":"2026-10-29"}}
← {"id":5,"ok":true,"result":{"jobId":"20261029-1"}}
← {"event":"download.progress","data":{"jobId":"20261029-1","date":"2026-10-29","pageNo":1,"done":1,"total":20,"bytesPerSec":1172447}}
← {"event":"download.page","data":{"jobId":"20261029-1","date":"2026-10-29","pageNo":12,"status":"failed","error":"HTTP_ERROR"}}
← {"event":"download.progress","data":{"jobId":"20261029-1","date":"2026-10-29","pageNo":20,"done":20,"total":20,"bytesPerSec":1100000}}
← {"event":"issue.archived","data":{"date":"2026-10-29","path":"…/人民日报_2026-10-29.pdf","bytes":23489152,"singlesDeleted":true}}
← {"event":"job.finished","data":{"jobId":"20261029-1","ok":true}}
```

注意：`download.start` **先返回 `jobId` 再推送事件**，客户端不应阻塞等待任务完成。

---

## 6. 版本演进

- 协议号写在 `hello` 里；**破坏性变更必须递增协议号**（1 → 2）；
- 新增方法、新增事件、新增返回字段属于**兼容变更**，不递增；
- 客户端遇到未知事件忽略；遇到未知字段忽略。

## 7. 校验文件

`docs/ipc.schema.json` 提供信封与主要结构的 JSON Schema，用于两侧的契约测试。

## 8. 联合早报扩展（2026-10-30）

本节为兼容新增能力，信封与协议号仍为 v1。`hello.result.features.zaobaoReaderV1=true` 表示支持；旧引擎无此字段时不调用新方法。唯一发现入口为 `https://www.zaobao.com/news/china`，文章只能来自已登记的中国频道主列表及其官网分页，不接收任意 URL。

| method | params | result |
| --- | --- | --- |
| `zaobao.feed.get` | `{offset?:0,limit?:60}` | `{items:[ZaobaoSummary + {read,cached}],fetchedAt,total,nextOffset,nextPage,hasMore}`；只读当前会话内存，limit 1–100 |
| `zaobao.feed.refresh` | `{}` | `{jobId}`；后台刷新固定入口 |
| `zaobao.feed.more` | `{}` | `{jobId}`；追加中国频道官网下滑使用的下一页；游标由引擎管理 |
| `zaobao.article.get` | `{articleId}` | `{cached:boolean,article:ZaobaoArticle|null}`；只读当前会话内存 |
| `zaobao.article.fetch` | `{articleId,refresh?:boolean}` | `{jobId}`；正文提交内存即完成；图片由客户端直接请求，不落盘 |
| `zaobao.task.get` | `{jobId}` | `{jobId,kind,articleId,state,error}`；kind 为 feed/more/article |
| `zaobao.task.cancel` | `{jobId}` | `{ok:true}`；下一请求或读取块处中断 |
| `zaobao.read.set` | `{articleId,read:boolean}` | `{ok:true}`；仅在当前会话内保留已读状态 |
| `zaobao.session.reset` | `{}` | `{session:number}`；取消旧任务，清空列表、正文、页码与已读内存，切换会话代次 |
| `zaobao.original.open` | `{articleId}` | `{ok:boolean}`；用户点击时用系统浏览器打开已登记原文 |

`ZaobaoSummary` 字段：`articleId,title,url,author?,publishedAt?,updatedAt?,timeLabel?,thumbnail?`。当前频道页面只给相对时间时保留为 timeLabel，不假造发布时间；不接收或返回标题下的摘要。

`ZaobaoArticle` 在摘要基础上增加 `blocks,access,contentState,parserVersion,fetchedAt,warnings`。块格式与现有 Block 一致；`access=public|subscriber|login_required|unknown`，`contentState=full|preview|unknown|unsupported`。full 由已核验的 `.com` 正文模板与 NewsArticle 元数据共同判定；明显受限标记优先判 preview。模板变化时不能把 JSON-LD 的摘要当作正文。

事件 `zaobao.task.changed` 与 task.get 返回相同快照。state 为 `queued|running|succeeded|failed|cancelled`。主线程先返回 jobId，再提交后台任务，后台只发事件。相同目标的未完成任务合并；终态约保留 10 分钟，应用退出不保证续抓。客户端轮询 task.get 可恢复漏收的事件。

新增错误码：`RATE_LIMITED`（429，保留 Retry-After 等待）、`ACCESS_DENIED`（401/403）、`NOT_FOUND`（404）、`CONTENT_TOO_LARGE`（页面／正文超限）。其余沿用已有错误。正文预算 700 KiB，不静默截断；图片走本地文件，不进入 NDJSON。任务等待不占用普通 RPC 的 30 秒调用时限。

早报数据全部驻留内存，不创建早报数据库表、文件或图片缓存。`cached` 仅表示本会话内已提取正文，并不表示磁盘缓存或可跨进程恢复。客户端进入、离开来源和手动刷新时调用 `zaobao.session.reset`；重新进入必定请求首页。旧会话中的在途结果不可提交到新会话。删除旧版 `zaobao.article.updated` 媒体事件；正文图片使用 `src`，`local=null`。

中国频道的 LoadMoreArticle 前端公开使用 `https://zbapi.zbstatic5.com/more/sitemap/8?pageNo=N&pageSize=27`，从第 2 页开始。引擎只允许此固定 endpoint 和合法页码，不接受调用方输入 API URL。失败不推进游标，空页或明确总数末尾结束；本地页通过 offset 分段返回，避免单条 NDJSON 随无限滚动膨胀。schema v3 为旧 feed_state 增加 next_page/has_more，升级前以 SQLite backup API 备份。

分页请求按官网公开 Request 客户端协议生成 x-amz-date / x-auth 校验头，仅覆盖固定的公开中国频道分页接口；不使用账号、Cookie 或订阅凭据。校验算法和测试位于 `net/zaobao_signing.py` 与 `tests/test_zaobao_signing.py`。

## 9. 诊断日志（2026-10-30）

`hello` 新增 `logDir`。stdout 仍严格使用 NDJSON；日志独立写入 `logs/app.log`、`engine.log`、`native.log`，不混入协议。记录事件、错误类型、代码位置、HTTP 状态与耗时，不输出新闻正文或请求凭据。轮转预算与异常捕获边界见《联合早报-无持久化与诊断日志》。
