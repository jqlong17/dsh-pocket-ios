# 01 · DSHKit：Transport + Protocol


> **Status**: Superseded (historical) · 写在模板定稿前，多为 2–3 段；不补写，理由见 README
## 背景

当前 RPC/WebSocket/JSON 解码全部内联在 `DSHPocket/DSHPocketApp.swift` 的 `ConnectionModel`
（`rpc()`、`follow()`、`PocketMessage.init(record:)`、`PocketSession.init(json:)` 等），
无法单测，且协议变更时风险高。

## 目标 / 非目标

- 目标：抽出本地 Swift Package `DSHKit`，提供 `DSHClientProtocol` + `URLSessionTransport`，
  负责 RPC envelope、WebSocket frame、事件解码、错误映射；无 UI 依赖、可单测。
- 非目标：不同步策略（模块 02）、消息展示（模块 04）。

## 现状代码路径

- `DSHPocket/DSHPocketApp.swift`
  - `ConnectionModel.rpc()`（约 1350 行区域）、`webSocketURL(from:path:)`
  - `PocketMessage.init(event:)` / `init(record:)`（约 1495–1570）
  - `PocketSession.init(json:)`、归档过滤（`fetchSessions`）
  - `ConnectionError`、登录重定向 `LoginRedirectRecorder`
- 需迁移/替换为 `DSHKit` 内的 `DSHClient`。

## 参考实现

- `github-references/openclient-llm/openclient-llm/Shared/Core/Networking/APIClientProtocol.swift`
- `github-references/element-x-ios/.../Services/Timeline/TimelineProxyProtocol.swift`
- `github-references/element-x-ios/.../Services/Timeline/TimelineItemIdentifier.swift`（稳定身份）

## 测试用例（先写，全部应失败）

### 协议编码/传输（Unit）
| ID | Given | When | Then |
| --- | --- | --- | --- |
| P01 | 客户端地址 `http://host:3081` | 构造 WebSocket URL | `ws://host:3081/api/remote.mux`（path 带前导 `/`） |
| P02 | 地址无 scheme | 规范化 | 补 `http://`，去零宽字符 |
| P03 | 任意 RPC 调用 | 编码请求体 | 含 `type=client-request`、`rpcId`、`method`、`payload.args` |
| P04 | `session/follow` 打开 | 编码 open frame | `type=open`、`streamId`、`endpoint=session/follow`、args 带 sessionId 与 maxMessages |
| P05 | 32KB+ 事件帧 | 解析 item frame | 只接受匹配 `streamId` 且 `type=item` 的帧，其余忽略 |

### 登录（Unit）
| ID | Given | When | Then |
| --- | --- | --- | --- |
| P10 | 正确 PIN | 登录响应 302 + cookie | 成功 |
| P11 | 错误 PIN | 200 + 登录页 | 失败且提示密码错误 |
| P12 | 频繁尝试 | 429 | 失败且提示稍后重试 |
| P13 | 会话失效 | RPC 返回 401 | 抛出 `unauthorized`，触发重新登录提示 |

### 事件解码（Unit，fixture 来自真实会话 JSON）
| ID | Given | When | Then |
| --- | --- | --- | --- |
| P20 | `user/message`（source.kind=user） | 解码 | 得到用户消息，含 `rpcId`（若服务端回填） |
| P21 | 注入上下文 `user/message`（source.kind=runtime-context） | 解码 | 返回 nil（不进聊天流） |
| P22 | `assistant/message`（data.message.content） | 解码 | 得到助手消息 |
| P23 | `tool/call` + `tool/result` | 解码 | 得到步骤：name/detail/result/isError |
| P24 | `turn/start` + `turn/end` | 解码 | 得到 turn 边界 seq |
| P25 | `assistant-stream` chunk（text-delta） | 解码 | 得到增量文本 |
| P26 | 带图片附件的事件 | 解码 | 得到 attachmentId/mediaType |
| P27 | 未知事件类型 | 解码 | 忽略且不崩溃 |

### 会话列表（Unit）
| ID | Given | When | Then |
| --- | --- | --- | --- |
| P30 | 含归档会话 | 解码 + 过滤 | 归档不出现 |
| P31 | 含 subagent（origin/parentSessionId） | 过滤 | 不出现 |
| P32 | 空会话（blank/标题空） | 过滤 | 不出现 |
| P33 | 标题/运行状态 | 解码 | 与投影字段一致 |

### 分页（Unit）
| ID | Given | When | Then |
| --- | --- | --- | --- |
| P40 | `session/page` 响应 | 解码 | records 顺序、`hasMore` 保留 |

## 预计改动（文件）

- 新增 `DSHKit/Package.swift`
- 新增 `DSHKit/Sources/DSHKit/Transport/{Transport.swift,URLSessionTransport.swift,WebSocket.swift}`
- 新增 `DSHKit/Sources/DSHKit/Protocol/{RPC.swift,Events.swift,SessionModels.swift,Decoding.swift}`
- 新增 `DSHKit/Tests/Fixtures/*.json`（从真实会话导出并脱敏）
- 新增 `DSHKit/Tests/ProtocolTests.swift`
- 修改 `DSHPocket.xcodeproj/project.pbxproj`（引入本地包）
- 逐步替换 `DSHPocketApp.swift` 中内联网络/解码代码

## 实施步骤

1. 建包 + `DSHClientProtocol` 空壳 + fixture 目录；
2. 先写 P01–P40 测试（Red）；
3. 实现 Transport/协议编码（Green）；
4. 迁移 `ConnectionModel` 的 `rpc`/`webSocketURL`/解码调用到 DSHKit；
5. 覆盖率 ≥85%，提交 `module-01-accepted`。

## 验收结果（2026-11-09）

- ✅ P01–P40（实际 49 条，含补充分支）全绿：`cd DSHKit && swift test`
- ✅ 行覆盖率 **91.6%**（`DSHKit/scripts/coverage.sh 85` → PASS）
- ⏭ App 接入（替换 `ConnectionModel` 内联 URL/RPC/解码）随模块 02 的 sync coordinator 一起完成

## 验收标准

- [x] P01–P40 全绿；
- [x] DSHKit 行覆盖率 91.6% ≥85%（不含 UI）；
- [ ] App 仍可登录/收发（E2E，模块 02 接入后验证）；
- [ ] spec 与实现一致，偏差已更新。
