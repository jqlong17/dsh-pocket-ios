# 11 · 插件日志轮转、响应压缩与 push 去重

- 日期：2026-11-24
- 状态：实现中
- 预估：60 分钟

## 背景

排查手机 ↔ Mac 流量构成时发现三件事：

1. `~/.dsh/dsh-pocket-ios/tailscale.log` 已达 **41 MB / 699,486 行**，其中
   **692,431 行是同一句 `push registered (sandbox, 1 device)`**，集中在
   2026-11-21 04:00–08:00（约 38 次/秒）。日志没有任何轮转，会无限增长。
2. 插件自有的 JSON 响应**没有压缩**（`send()` 直接 `JSON.stringify` + `res.end`）。
3. `push.register` 每次调用都写一行日志，循环调用时把日志刷爆。

同时确认一个**边界**：手机拉会话历史走的是 **DSH 自己的 `/api/*`**，
插件只做 pipe 转发（`proxyRes.pipe(res)`）。所以：

- 流量大头（142 MB）**不是插件端点产生的**，而是 DSH 的会话 JSON；
- 在代理层加 gzip 需要缓冲区全部响应，会破坏 SSE 流式输出 → **本次不做**；
- 插件能负责的是**自有端点**的压缩（如 status/overview/telemetry 应答）。

## 目标

| 项 | 目标 |
| --- | --- |
| 日志轮转 | 单文件超过 10 MB 自动切分，保留 3 份 |
| push 去重 | 同一 token 10 秒内只记一次日志 |
| 响应压缩 | 自有端点 JSON ≥ 1 KB 时按 `Accept-Encoding` 返回 gzip |

## 方案

新增两个纯函数模块（可单测，不碰 I/O）：

- `lib/log-rotate.js`
  - `shouldRotate(size, limit)` → `boolean`
  - `rotateNames(base)` → `[base.1, base.2, ...]`
- `lib/json-encode.js`
  - `wantsGzip(header)` → `boolean`
  - `encodeJson(payload, acceptEncoding, { threshold })` → `{ body, headers }`

`index.js` 只做接线：

- `logLine()` 写之前 `stat` 一次，超限则重命名（`.1` 覆盖，`.2` 顺延，超过 3 份删除）。
- `send()` 走 `encodeJson`。
- `push.register` 用 `Map<token, lastLogMs>` 去重（只在写日志这一层，**不影响业务逻辑**）。

## 影响面

- 只影响插件自有端点与日志；**不改** DSH 代理路径、不改 SSE。
- 压缩对客户端透明（`URLSession` 自动解压）。
- 日志轮转后，排查时需看 `.1`（最新旧档）。

## 测试计划

`plugin/test/`（node:test）：

- `log-rotate.test.js`：阈值判断、轮转文件名顺序、超过 3 份的行为
- `json-encode.test.js`：有/无 `Accept-Encoding: gzip`、低于阈值不压、往返解压一致
- `push-dedupe.test.js`：10 秒内重复调用只记一次

## 回滚

删除新增模块 + 还原 `send`/`logLine`/`push.register` 三处接线即可；无数据迁移。
