# 16 · 断网与登录失效判定：一次修清楚

## 背景 / 问题

用户连续报了三个现象，根因都在「错误类型被层层改造后，判定依据丢失」：

1. **飞行模式下发消息显示「服务器返回了无法识别的响应」+「发送失败」**，而不是「断网暂存，联网后自动发送」——联网后也不会补发。
2. **电脑端显示消息「排队」**（带 `↑` 标记，要 Cmd+Enter 插话），手机端却以为发出去了。
3. **DSH 重启后手机每 2 秒刷一次「密码不正确」**，永远不提示重新配对。

## 目标与非目标

**目标**
- 断网发出的消息必须进「断网暂存」，恢复网络后自动补发。
- 登录失效（401）必须触发重新配对流程，而不是无限重试。
- 状态文案必须反映真实情况：已确认的消息不能显示「现在断网」。

**非目标**
- 不改发送协议（`session/prompt` 的 envelope 形状）。
- 不改 DSH 端的 cookie 有效期策略。

## 参考实现

- `URLError.Code`（`.notConnectedToInternet` / `.timedOut` / `.networkConnectionLost`）是 iOS 判断「瞬时网络故障」的唯一可靠依据。
- 业界惯例：传输层不应把系统错误包装成自定义类型，否则上层无法基于错误码做重试决策（参见 `URLSession` 与 `Alamofire` 的错误分层）。

## 方案

三处根因、三处修复：

**① 传输层保留 `URLError`**（`DSHKit/Transport/Transport.swift`）

原先 `catch { throw DSHError.transport(error.localizedDescription) }` 丢掉了错误码，导致 `DSHNetworkErrorPolicy.isTransient` 恒为 false，`SendFailurePolicy` 走 `.markFailed` 而不是 `.holdOffline`。

改为：`catch let error as URLError { throw error }`，并让 `isTransient` 兜底识别 `DSHError.transport`。

**② 发送模式：在跑就 steer**（`PromptPolicy.liveMode`）

原先要求「见过实时 turn 事件」才用 `steer`，而 `liveTurnEventsSeen` 常为 false，导致生成中发的消息全走 `queue`（电脑端显示排队）。排队要等整轮跑完，体感损失远大于误打断，改为只看 `isRunning`。

**③ 401 判定统一**（`ConnectionError.isUnauthorized`）

适配层把 401 映射成 `.invalidPin`（文案更准），但所有 `case .server(401)` 判断因此失效，`handleAuthExpired` 从未被调用。新增 `isUnauthorized` 覆盖 `.invalidPin` 与 `.server(401/403)`，替换全部 6 处判断点。

**附带**：`PendingSendStatePriority` 明确优先级「失败 > 已确认 > 断网 > 发送中」，避免残留的断网标记让已受理的消息显示「现在断网」。

## 测试计划（先红后绿）

| 用例 | target | 断言 |
| --- | --- | --- |
| 传输层保留错误码 | DSHKit `TransportTests` | 抛出的仍是 `URLError`，`code` 可读 |
| 断网判定 | DSHKit `TransientNetworkTests` | `.notConnectedToInternet` → `isTransient`；飞行模式 → `holdOffline` |
| 业务错误不判瞬时 | 同上 | `unauthorized` / `server(400)` → false |
| 发送模式 | DSHKit `PromptPolicyTests` | `isRunning == true` → `.steer` |
| 状态优先级 | DSHKit `PendingSendStatePriorityTests` | 已确认压过断网标记 |

> 注意：`testURLSessionHTTPTransportWrapsTransportError` 原先**锁定了错误行为**（断言「应该包装成 transport」），已改为断言「必须保留 URLError」。测试也会保护 bug。

## 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| 传输层不再包装 → 上层文案变化 | `ConnectionError.from` 仍负责展示适配 |
| steer 恢复可能误打断空闲会话 | `isRunning` 已由 turn 事件驱动；误打断最多多问一句 |
| 优先级调整影响 UI 文案 | 只改显示，不改发送行为 |

## 预估工时

三处修复各 20 分钟 + 测试 30 分钟，合计 **90 分钟**。实际约 100 分钟（含真机三轮验证）。

## 复查记录

- 2026-11-12 用户真机确认：飞行模式 → 「现在断网，等联网时将一并发送」；恢复网络 1–2 秒内自动发出。
- 2026-11-12 用户真机确认：生成中发消息直接插进当前轮，电脑端不再显示排队。
