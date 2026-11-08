# DSH Pocket iOS 架构评审（对比开源聊天客户端）

> 目的：对照成熟开源项目，找出我们反复出现（丢消息、顺序、串台、假死、滚动抢位、渲染错位）
> 背后的**架构性原因**，并给出渐进式演进方案。存档点：`checkpoint-2026-11-09`。

## 1. 现状

- 单体 target，`DSHPocket/DSHPocketApp.swift` **2590 行**、26 个顶层类型，混合了：
  App 入口、协议 RPC、WebSocket 同步、状态管理、全部视图、图片查看、二维码扫描、相机。
- 无本地 Swift Package、无协议/传输抽象、**0 个单元测试**。
- 状态表达：大量 Bool / Set / Task 拼装（`isSending`、`isTurnRunning`、`ackedSendRpcIds`、
  `failedSendRpcIds`、`conversationToken`、`turnStarts/turnEnds`、`scrollGeneration`…）。
- 同步模型：`session/follow`（WS snapshot+events）+ `session/page`（HTTP 轮询）+ 本地发件箱
  + rpcId 对账 + turn 区间排序，全部散落在 `ConnectionModel`。
- 列表：SwiftUI `VStack`，固定只取最近 30 条消息，无分页、无流式。

## 2. 参考项目怎么分层

| 维度 | 我们 | Element X iOS | stream-chat-swiftui | openclient-llm |
| --- | --- | --- | --- | --- |
| 模块/目录 | 单 target 单文件 | `Screens/ Services/ Other/ FlowCoordinators`，功能按 Screen 划分 | `ChatChannel/ ChatMessageList/ ChatComposer/ ViewFactory/` | `Shared/Core`（含 `APIClientProtocol`）+ `Features` |
| 协议/网络 | 内联在 `ConnectionModel.rpc()` | Rust Matrix SDK + `TimelineProxy` 协议 | SDK + 控制器 | `APIClientProtocol` 注入 |
| 状态管理 | 全局 `ConnectionModel` + 每会话 `ConversationState` 转发 | 每屏 ViewModel（**82 个**）+ timeline state publisher | ViewModel + ChannelController | Store/ViewModel |
| 消息身份 | rpcId + 文本兜底 | `TimelineItemIdentifier`：`uniqueID` + `eventID/transactionID` | `LocalMessageState` 枚举 + messageId | message id |
| 分页 | 固定 30 条 | `TimelinePaginationState`、`loadOlder` | `loadMore` | 有 |
| 流式 | 忽略 `assistant-stream` | typing/streaming | - | 流式回复 |
| 列表实现 | SwiftUI `VStack` | UIKit `UITableView` 包装（`TimelineTableViewController`） | `LazyVStack` + 稳定 id | LazyVStack |
| 可定制 | 硬编码视图 | 组件化 + previews | `ViewFactory` 可替换视图 | 各 Feature 视图 |
| 测试 | 0 | **196 个测试文件** | 大量测试 | 有测试 |

## 3. 根因（对应我们踩过的坑）

| 踩过的坑 | 直接原因 | 架构性根因 |
| --- | --- | --- |
| 丢消息/显示"发送中" | pending 按文本去重、requestId 不一致、发件箱 TTL | 没有**消息状态机**与稳定身份；
没有单一同步协调者 |
| 顺序错乱 | 排队消息 seq 在 turn 区间内、turn 区间排序补丁 | 排序规则散落在视图/model；没有"服务端顺序为唯一真相 +
本地 pending 固定末尾"的模型 |
| 串台 | 全局 selectedSession/messages + 迟到异步结果 | 之前没有 per-session 状态（已补 `ConversationState`），
但异步任务/订阅仍未由会话级协调者管理 |
| 连接假死 | WS 静默断，UI 仍显示已连接 | 没有连接状态机（已补）与统一同步协调者 |
| 滚动抢位 | 每个合并都请求贴底、补滚 9 次 | 滚动策略写在 View 里，状态源不唯一 |
| 渲染错位/重叠 | SwiftUI 动态高度 + LazyVStack/嵌套滚动 | 列表实现选型没有以"长历史/流式"为前提 |
| 修一次坏一次 | 规则散落、无测试 | 无协议/传输边界、0 单元测试 |

## 4. 目标架构

```
DSHPocket (App, SwiftUI)
├─ Features/SessionList   (ViewModel + Views)
├─ Features/Conversation  (ViewModel + Views; 未来可换 UIKit 列表)
└─ Shared/UI             (DesignTokens, L10n, 通用组件)

DSHKit (本地 Swift Package，可单测)
├─ Transport   (HTTP/WebSocket, auth cookie, 重连)
├─ Protocol    (RPC envelope, event 解码, session/page, assistant-stream)
├─ Sync        (SessionSyncCoordinator actor: snapshot + events + poll + gap 检测)
└─ Store       (SessionStore / MessageStore / 消息状态机 / outbox)
```

关键约定（对齐参考项目）：

1. **协议客户端边界**：`DSHClientProtocol`（openclient-llm 的 `APIClientProtocol` 模式）+ 可注入的
   Transport，业务/视图不直接拼 JSON。
2. **单一同步协调者**：`SessionSyncCoordinator`（actor）作为会话数据的唯一真相源，负责 snapshot、
   事件增量、断线重连、轮询兜底、分页；View 只读 store、只发意图。
3. **消息状态机**：`sending → accepted(steer/queue) → committed | failed`，身份 = `rpcId`（服务端回填
   `source.rpcId`），不使用文本去重。
4. **分页模型**：`loadOlder(hasMore)`，列表不再固定 30 条；长历史时把消息列表换成 UIKit 包装
   （Element X 的做法），为流式渲染留空间。
5. **ViewModel 化**：Conversation 的滚动/键盘/发送/分页逻辑移入 ViewModel；View 只做布局与事件转发。
6. **测试**：先用真实会话 JSON 做 fixture，覆盖 event 解码、排序、状态机、outbox 对账、分页。

## 5. 渐进式迁移（不中断发版）

- **Phase 0（1–2 天，无行为变化）**：抽 `DSHKit` 包，迁出 Models/事件解码/RPC；补解码与排序单测；
  把散落的 Bool/Set 收敛为 `MessageSendState` 枚举。
- **Phase 1（2–3 天）**：实现 `SessionSyncCoordinator`（actor），接管 follow/poll/outbox/分页；
  删除 `ConnectionModel` 里的同步启发式；加 `loadOlder`。
- **Phase 2（2–3 天）**：Conversation 拆 ViewModel + 子视图；评估 UIKit 列表；接 `assistant-stream`
  实现流式回复（可配合 microsoft/SwiftStreamingMarkdown）。
- **Phase 3**：L10n、DesignTokens、ViewFactory 式可替换组件、previews/mocks；把 `docs/` 与 skill
  同步更新。

原则：每一步都保持 App 可运行、可发版；不在一个 PR 里同时动协议层和 UI 层。
