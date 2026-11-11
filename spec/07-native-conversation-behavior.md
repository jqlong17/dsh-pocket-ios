# 07 · 对话行为按原生收口（TDD）

## 背景

对话页的滚动跟随、回到底部、进会话定位，经过几轮改动后出现了三次回退（上滑被吸回、
收起淡出压住下一条、进会话无法上滑）。根因一致：判定写在 View 里、没有测试兜着。

本 spec 把这些判定全部落成 DSHKit 里的纯策略，先写测试再改界面；界面只负责把状态喂给策略。

## 原则（对齐系统 App 的消息类交互）

1. **只有真正贴底才自动跟随**，离底一点点就停止。
2. **手指在屏上时，位移归用户**，任何程序化滚动都不做，连"强制"也不做。
3. **离开底部就出现「回到底部」**，有未读时带上条数；不需要等未读攒够。
4. **进入会话定位一次就停**，没有稳定期反复补贴底。
5. **内存里只留最近几条会话**，其余淘汰；草稿不受影响。
6. **协议知识只在 DSHKit 出现一次**，App 只消费类型化结果。
7. **暂时性失败和永久性失败长得不一样**。

## 需求与测试（先红后绿）

### R1 跟随判定

- 测试：`ScrollFollowPolicyTests`
  - 离底 0、8 点算贴底；8.5、48 点不算。
  - 贴底 → `.follow`（恢复跟随、清未读）。
  - 拖动中离开底部 → `.stopFollow`。
  - 非拖动 + 跟随中 + 内容变高 → `.pinToBottom`。
  - 非拖动 + 未跟随 → `.keep`。
- 验收：`ConversationView` 的几何回调只调用 `ScrollFollowPolicy.action`，不再自己写 if。

状态：**已实现**（测试 6 条）。

### R2 拖动期禁止贴底

- 测试：`ScrollFollowPolicyTests.testAutoScrollForbiddenWhileDraggingEvenIfForced`
- 验收：`scrollToBottom` 首行调用 `ScrollFollowPolicy.canAutoScroll`。

状态：**已实现**。

### R3 回到底部按钮

- 测试：`BackToBottomPolicyTests`（新增）
  - 贴底（≤8 点）→ 不显示。
  - 离开底部 → 显示。
  - 未读 0 → 标签只有箭头；未读 7 → 带 `7`；未读 120 → 显示 `99+`。
  - 出现延迟常量 = 0.25 秒。
- 验收：`ConversationView` 的按钮显示条件、标签、延迟全部来自策略。

状态：**待做**。

### R4 进会话定位一次

- 测试：无独立单测（依赖 SwiftUI 布局），以真机验收代替：
  - 进会话停在最新一条；
  - 1 秒内不出现二次跳动；
  - 立刻上滑可停住。
- 验收：`onAppear` 只调一次 `scrollToBottom(force: true)`，代码里不再有稳定期定时器。

状态：**已实现**（`isSettlingScroll` 已删除）。

### R5 会话缓存上限

- 测试：`ConversationCachePolicyTests`（4 条）
  - 未超限不淘汰；超限淘汰最旧；当前会话即使最旧也不淘汰。
- 验收：`trimRetainedConversations` 只调用策略。

状态：**已实现**。

### R6 有缓存不走 HTTP 基线

- 测试：`SessionOpenPolicyTests`（2 条）
- 验收：`startCoordinator` 的 `fetchHTTPBaseline` 来自策略。

状态：**已实现**。

### R7 任务名单解析

- 测试：`JobRosterTests`（8 条）
- 验收：App 侧不再手工拆 `job/list` 帧。

状态：**已实现**。

### R8 过程事件 / 分页记录 / 附件解析收口

- 测试：`DSHStepParsingTests`（由并行任务补充）
  - 单条记录 → `DSHStepEvent`：tool/call、tool/result、turn/start、turn/end 各一条。
  - 缺 callId / 缺 name / 未知类型 → 丢弃，不崩。
  - `session/page` records → 事件数组：正常、含坏行、空集合。
  - 附件字典 → 图片引用：正常、缺 attachmentId。
- 验收：`ConnectionModel+Process.applyStepEvent` 不再手工取 `data["message"]`、`block["attachment"]`；App 层 `as? [String: Any]` 数量明显下降。

状态：**进行中**（并行任务 task-1）。

### R9 连接失败分型

- 测试：`ConnectFailureMessageTests`（App 侧，由并行任务决定放置位置）
  - 超时 / 断连 / 无网络 / DNS → 暂时性，文案表达「稍后重试」。
  - 401 / 403 / 配对码失效 → 认证失效，文案表达「重新扫码或重新输入配对码」。
  - host 为空 / URL 解析失败 → 地址无效。
  - 其余 → 未知，不吞掉原始错误描述。
- 验收：连接页不再对四类错误显示同一句话。

状态：**进行中**（并行任务 task-2）。

## 非目标

- 不做 `ConversationViewModel` 大拆分（另立 spec）。
- 不动发送路径的 RPC 合并（风险高，单独一轮）。
- 不新增依赖。

## 验收方式

1. `cd DSHKit && swift test` 全绿；
2. `xcodebuild build` 成功；
3. 装真机走一遍：进会话 → 上滑 → 新消息到达 → 回到底部 → 退出再进；
4. 记录到本文件末尾的验收表。

## 真机验收表

| 场景 | 预期 | 结果 |
| --- | --- | --- |
| 进入会话 | 停在最新一条，无二次跳动 | 待验 |
| 上滑 30 点后松手 | 位置保持，不被吸回 | 待验 |
| 上滑状态下有新消息 | 位置不动，出现「回到底部」 | 待验 |
| 点回到底部 | 回到最新，按钮消失 | 待验 |
| 退出再进同一条 | 内容立刻在，无转圈 | 待验 |
| 进过 4 条以上会话 | 内存不随会话数线性上涨 | 待验 |
