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
