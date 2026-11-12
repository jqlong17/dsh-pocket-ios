# 09 · 进入会话路径收口（按模块独立验证）

## 背景

从会话列表点进对话，按时间线做的事太多：一次同步的 `open()` 里塞了 15 件事，每次进入新开两条 WebSocket，
缓存快路因为顺序问题没生效。本 spec 把这条路径拆成 6 个互不依赖的小模块，
每个模块单独可执行、单独可验证，并给出量化标准。

## 总原则

1. **进入 = 切状态 + 显示**；订阅、采样、淘汰这些维护工作挪出热路径。
2. **一次进入只建一条连接**；不可见的内容不订阅。
3. **数据只有一个真相源**：运行状态来自 turn 事件，列表状态只用于首帧。
4. 每个模块都有：改动范围、独立验证命令、量化通过标准、回滚方式。

## 模块 M1 · 缓存快路生效（正确性）

**问题**：`open()` 里先关掉 loading 又无条件打开，`noteLoadFinished` 因为 `loadTimingPending` 还是 false 直接返回。
结果是「复用缓存」等于没做。

**改动范围**：`DSHKit/UI/ConversationOpenPlan.swift`（新）、`DSHKit/Tests/.../ConversationOpenPlanTests.swift`、
`DSHPocket/Session/ConnectionModel+Sessions.swift`（open 里的加载态设置）、`ConnectionModel+Live.swift`（startCoordinator 不再抢设 loading）。

**独立验证**
- `cd DSHKit && swift test --filter ConversationOpenPlanTests`
- 真机：进同一条会话两次，「更多 → 复制诊断信息」里第二次进出的 `source` 应为 `cache`。

**量化标准**
1. 有缓存时：`isLoadingConversation == false`，且 `lastLoadSource == "cache"`，`lastLoadMs` 有值（单测覆盖判定，真机看诊断）。
2. 无缓存时：`isLoadingConversation == true`，来源只能是 `snapshot` 或 `follow`。
3. 诊断「进出」记录里，第二次进入的「复用消息数」> 0 且来源为 cache。

**回滚**：单文件策略 + 两处调用点，`git revert` 该提交即可。

## 模块 M2 · 任务名单按需订阅

**问题**：进入会话就建一条 WebSocket 订阅 `job/list`，但用户多数时候不打开任务面板。

**改动范围**：`ConnectionModel+Sessions.swift`（open 里不再启动任务名单）、`ConnectionModel+Process.swift`（提供 `ensureJobRoster` / `stopJobRoster`）、
`Views/JobsSheet.swift`（出现时订阅、消失时取消）。

**独立验证**
- 真机：进会话，看诊断里是否还有「任务名单」相关连接记录；打开任务面板再关闭，确认订阅建立与撤销各一次。
- 抓包或看 Xcode Debug Navigator 的网络连接数（可选）。

**量化标准**
1. 进入会话时新建的 WebSocket 数量从 2 降到 **1**（只有协调器）。
2. 打开任务面板后 1 秒内出现任务数据；关闭后订阅被取消（诊断无残留）。
3. 任务面板打开期间长连接数不超过 2。

**回滚**：只影响订阅时机，行为等价，可直接 revert。

## 模块 M3 · open() 拆成切状态 + 起后台

**问题**：同步函数里混了发件箱清理、缓存淘汰、诊断采样、订阅启动，热路径上做维护工作。

**改动范围**：`ConnectionModel+Sessions.swift` 拆成 `switchTo(_:)`（纯状态）与 `startBackgroundFeeds(_:)`（订阅与维护），
`switchTo` 由 `open()` 在首帧同步调用，`startBackgroundFeeds` 放入 `Task { }` 延到下一个 runloop。

**独立验证**
- 单测：`switchTo` 前后状态断言（当前会话 id、messages 数量、loading 标记），不需要网络。
- 真机：进入耗时（诊断 `进入 NNN ms`）对比拆分前后。

**量化标准**
1. `switchTo` 不含任何网络调用（代码审查 + 单测中不可注入 client 也能跑通）。
2. 首帧同步工作量下降：进入耗时（诊断里的「进入」）**不高于拆分前的 80%**。
3. 拆分后所有既有行为不变：进会话、上滑、新消息、退出再进四条路径手工回归通过。

**回滚**：两个函数可并存，保留旧 `open()` 作为回退路径一个版本后再删。

## 模块 M4 · 消除进入错帧

**问题**：视图先渲染上一会话的数据，`open()` 在 `.task` 里才切过去。

**改动范围**：`Views/ConversationView.swift`（内容从传入 session 派生，或在切换完成前显示骨架）、
`ConnectionModel.visibleSessionId` 的读写归口。

**独立验证**
- 真机：在会话 A 里发多张图片，返回列表，进会话 B，观察是否闪现 A 的内容。
- 诊断：进入瞬间 `messages` 条数应与目标会话一致。

**量化标准**：从 A 进 B，B 首帧渲染的消息条数 == B 的缓存条数（诊断断言），**不得等于 A 的条数**；视觉上无内容闪现。

**回滚**：视图层改动，独立 revert。

## 模块 M5 · 运行状态单一真相

**问题**：列表的 running 可能滞后，进入后 4 秒再核实一次，等于两个状态源。

**改动范围**：`ConnectionModel+Sessions.swift` 去掉 4 秒定时核实；`refreshRunningState` 仅在收到 turn 事件时更新。

**独立验证**
- 真机：打开一个正在跑的会话，进入后 1 秒内应显示运行标记；跑完后标记在收到 turn/end 后消失。
- 回归：列表里 `running=true` 但已结束的会话，进入后不出现长时间「正在运行」。

**量化标准**
1. 代码中没有 4 秒定时器（`grep -n "seconds: 4"` 无命中）。
2. 运行中会话进入后 **≤1 秒**出现运行标记。
3. 结束后 **≤1 秒**标记消失（由 turn/end 驱动）。

**回滚**：恢复定时核实即可。

## 模块 M6 · visibleSessionId 归模型

**问题**：视图在 `.task` 里写 `model.visibleSessionId`，通知直达会话的入口容易漏设。

**改动范围**：`ConnectionModel+Sessions.swift`（open/leave 维护）、`Views/ConnectedView.swift` 去掉视图写入。

**独立验证**
- 单测：`switchTo` 后 `visibleSessionId == session.sessionId`，`leave` 后为 nil。
- 真机：从通知点进会话，回到底部按钮与未读计数行为正常。

**量化标准**：`grep -rn "visibleSessionId =" DSHPocket/Views` 无命中；通知入口单测覆盖。

**回滚**：视图与模型各一处，独立 revert。

## 执行顺序与提交策略

M1 → M2 → M3 → M4 → M5 → M6。每个模块一个提交，提交信息带模块号；
每个模块完成后必须：`swift test` 全绿 + `xcodebuild build` 成功 + 该项的量化标准自查，再进入下一个。
任何模块未达标就停下来报告，不继续。

## 验收汇总表

| 模块 | 通过标准 | 状态 |
| --- | --- | --- |
| M1 | 二次进入 source=cache、loading 不再打开 | 已实现（3 条单测 + 真机待验） |
| M2 | 进入只建 1 条 WS，任务面板按需订阅 | 已实现（进入不再建 job/list） |
| M3 | 进入耗时不高于拆分前 80%，switchTo 无网络 | 已实现（open 同步路径已无网络与清理） |
| M4 | 首帧不渲染上一会话内容 | 已实现（entries 按 activeSessionId 门闸） |
| M5 | 无 4 秒定时核实，运行标记 ≤1 秒 | 已实现（运行状态只由 turn 事件决定） |
| M6 | 视图不再写 visibleSessionId | 已实现（open/leave 维护） |
