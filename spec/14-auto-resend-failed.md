# 14 · 联网后自动补发「发送失败」的消息

## 背景 / 问题

现在发件箱里有两类未送达条目：

| 状态 | 触发 | 联网后行为 |
| --- | --- | --- |
| `heldOffline` | 断网 | **自动**按顺序补发 |
| `sendFailed` | 其它失败（超时被误判、5xx、隧道抖动等） | 停在「重新发送」，**要用户手点** |

用户的实际感受：断网期间发了几条，恢复网络后有的自动发了、有的还挂在那儿显示「重新发送」，
得一条条点——「我建议自动发送之前没发送成功的信息，而不是手动重新发送」。

## 目标与非目标

**目标**
1. 连接恢复时，`sendFailed` 的条目也自动补发一次。
2. 不能变成重试风暴：同一条消息在一轮连接里只自动重试一次；永久性失败不会被反复重试。
3. 正文安全语义不变：失败仍保留正文，绝不删除（`OutboxRetentionPolicy` 不动）。

**非目标**
- 不改 `heldOffline` 的现有补发逻辑与顺序。
- 不做指数退避的长期重试（那是另一件事）。
- 不改服务端协议。

## 参考实现

| 参考 | 取什么 |
| --- | --- |
| 现有 `flushQueuedSends` | 串行补发、条间 250ms、进度提示、失败保留正文 |
| `SendFailurePolicy`（本仓） | 「什么错误值得重试」的判断已经统一，这里只判断「什么状态值得自动补发」 |
| iMessage / Telegram 的「重连后补发」 | 一次性重试，失败即停在可重试状态，不无限循环 |

不采用：不做后台常驻重试队列（耗电、且在没有后台任务授权时不可靠）。

## 方案

1. `OutboxEntry` 增加 `autoRetried: Bool`（旧数据解码为 false），记录「已经自动重试过一次」。
2. DSHKit 新增 `SendRetryPolicy.shouldAutoResend(heldOffline:sendFailed:accepted:autoRetried:)`：
   - `heldOffline` → true（原行为）；
   - `sendFailed && !accepted && !autoRetried` → true（首次自动重试）；
   - `accepted` 或已重试过 → false。
3. `flushQueuedSends` 的候选集改用该策略；对 `sendFailed` 条目在发送前先标 `autoRetried = true`，
   发送成功按 `accepted` 处理（等历史确认后移除），失败保持 `sendFailed`。
4. 进度提示区分两类：`正在补发 2/3` 不变，全部失败时提示「N 条仍失败，可手动重发」。

## 测试计划（先红后绿）

| 测试 | target |
| --- | --- |
| `SendRetryPolicyTests`：heldOffline 补、failed 首次补、failed 已重试不补、accepted 不补 | DSHKit |
| 回归：`OutboxRetentionPolicy` 用例不变（失败仍不删正文） | DSHKit |

量化标准：
- `sendFailed` 条目在连接恢复后**自动尝试一次**；
- 第二次连接恢复不再重复尝试（`autoRetried` 已置）；
- 失败后正文仍在发件箱（`grep` 发件箱记录 + 界面上仍可手点重发）。

## 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| 永久失败的消息被反复自动重试 | `autoRetried` 一次性标记；只有用户手点重发才会清掉 |
| 与 `heldOffline` 补发争抢 | 复用同一个 `offlineFlushInFlight` 闸门与串行循环 |
| 旧数据解码失败 | `autoRetried` 用 `decodeIfPresent ?? false` |

回滚：单次提交，`git revert` 即可；`autoRetried` 字段留着不影响旧逻辑。

## 预估工时

预估 **40 分钟**（策略 + 测试 15、接线 15、验证 10）。
