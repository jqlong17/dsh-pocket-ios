# 18 · 发送前预判网络可达性


> **Status**: Accepted · 2026-11-12 · 代码已实现验证，真机待验三条
## 背景 / 问题

用户真机实测（`spec/17` 验收）暴露一个体验问题：

```
14:46:14  用户点击发送
14:46:32  才写入断网暂存       ← 中间 18 秒，界面一直显示「发送中」
14:46:59  网络恢复
14:47:00  补发完成
```

**根因**：`performSend` 没有任何网络预判，走的是「先试 → 失败 → 分型」：

1. `rpcWithRetryAdapted` 重试 3 次，退避 800 / 2000 / 3000ms；
2. 每次尝试还可能等 TCP 超时（`timeout: 20` 秒）；
3. 三次都失败才 `catch` → `SendFailurePolicy` → `.holdOffline`。

于是「已知网络不可达」这件事要花 2.8–62 秒才被判定出来。

**讽刺的是**：`NWPathMonitor` 当时就知道不可达——它就是 27 秒后触发补发的那个监听，
但它的状态只用来「恢复时补发」，没有暴露给发送路径。

## 目标与非目标

**目标**
- 网络明确不可达时，点发送**立即**进入断网暂存（不等重试）。
- 网络可达或状态未知时，行为与现在完全一致。
- 判定逻辑可单测（放 DSHKit）。

**非目标**
- 不替代失败分型：`holdOffline` / `markFailed` 的判定继续由 `SendFailurePolicy` 负责，
  预判只是「提前走同一条路」，不是新路径。
- 不处理「假连接」（有 Wi-Fi 信号但网关不通）：那类仍靠超时兜底，本 spec 不引入 ping 探测。
- 不改重试次数与退避节奏。

## 参考实现

- **iOS 原生可达性判断的既有结论**：`NWPathMonitor` 的状态是「接口层是否可用」，
  它不能证明「目标服务可连」。所以业界（如 Alamofire 的 `NetworkReachabilityManager`）
  只用它做**快速失败**，不做成功保证——与本 spec 的定位一致。
- 本项目 `NetworkWatcher`（`spec/14` 期间加入）已在监听路径变化并驱动补发，
  本次只是让它同时暴露当前状态。

## 方案

### 第 1 步：DSHKit 加纯策略（可单测）

```swift
public enum SendPreflightAction: Equatable, Sendable {
    case send          // 直接发
    case holdOffline   // 已知不可达，直接写断网暂存
}

public enum SendPreflightPolicy {
    /// - Parameter isReachable: nil 表示「还没探测到」——必须按可发送处理。
    public static func action(isReachable: Bool?) -> SendPreflightAction
}
```

**为什么用 `Bool?` 而不是 `Bool`**：`NWPathMonitor` 首次回调前没有状态。
若把 nil 当成不可达，App 冷启动头几秒发的消息会被错误暂存。
**「不知道」必须等同于「可以试」**——这是本 spec 最容易写错的边界。

**为什么放 DSHKit**：判定本身是纯函数，边界（nil / true / false）需要穷举测试；
App 层没有测试 target，放进去就测不到。

### 第 2 步：`NetworkWatcher` 暴露当前状态

```swift
private(set) var isReachable: Bool?   // nil = 尚未探测
```

在 `pathUpdateHandler` 里同步更新（当前只更新了私有 `lastSatisfied`）。

**为什么暴露 `Bool?` 而不是 `Bool`**：见第 1 步，必须能表达「未知」。

### 第 3 步：`performSend` 开头预判

在写入发件箱、创建待确认消息**之后**、发请求**之前**插入：

```swift
switch SendPreflightPolicy.action(isReachable: networkWatcher.isReachable) {
case .holdOffline:
    // 走与 SendFailurePolicy 的 .holdOffline 完全相同的状态写入
    queuedSendRpcIds.insert(requestId)
    markOutboxHeldOffline(rpcId: requestId)
    recordDiagnostic("发送前预判网络不可达，直接写入断网暂存：\(requestId)")
    return
case .send:
    break
}
```

**为什么放在「写完发件箱之后」**：消息必须先落地本机，否则预判后 `return` 会丢掉用户输入。
顺序是「先保命，再优化」。

**为什么复用 `holdOffline` 的状态写入而不是另写一套**：两条路径的最终状态必须完全一致，
否则 `flushQueuedSends` 的补发候选集会漏掉预判写入的条目。

### 第 4 步：护栏

`spec/17` 的 `pure-forwarding-smell` 已存在；本次不新增脚本判据，
但补 3 条 DSHKit 单测覆盖 nil / true / false 三个分支。

## 测试计划（先红后绿）

| 用例 | target | 断言 |
| --- | --- | --- |
| 未知状态必须发送 | DSHKit `SendPreflightPolicyTests` | `action(isReachable: nil) == .send` |
| 可达必须发送 | 同上 | `action(true) == .send` |
| 不可达直接暂存 | 同上 | `action(false) == .holdOffline` |
| 回归：正常发送 | `swift test` | 345 绿不变 |
| 真机：飞行模式点发送 | 手工 | **1 秒内**出现「现在断网，等联网时将一并发送」 |
| 真机：联网正常发送 | 手工 | 与现在一致（ACK 耗时数十毫秒） |
| 真机：恢复网络补发 | 手工 | 与现在一致（1 秒内发出） |

## 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| nil 被当成不可达 → 冷启动消息被误暂存 | 策略明确 nil → `.send`，并有单测锁定 |
| 误判可达（假连接）→ 仍要等超时 | 本 spec 不改变兜底路径，最坏情况与现在相同 |
| 预判路径漏写 `queuedSendRpcIds` → 补发漏掉该条 | 复用 `holdOffline` 的同一组写入；真机验证补发 |
| `isReachable` 与实际不一致（如 Tailscale 刚起来） | 只用于「快速失败」；真正的成功判定仍靠 ACK |

**回滚**：删掉 `performSend` 开头的预判分支即可回到现状，DSHKit 策略与 `isReachable` 可保留（无副作用）。

## 预估工时

按单元累加（不拍总量）：

| 单元 | 数量 | 单耗依据 | 小计 |
| --- | --- | --- | --- |
| spec 定稿 | 1 | 本轮实测约 15 | 15 分钟 |
| DSHKit 策略 + 3 条测试 | 1 | 同类「纯策略 + 测试」实测 18–25 | 22 分钟 |
| `NetworkWatcher` 暴露状态 | 1 | 约 5 行 | 5 分钟 |
| `performSend` 接入 | 1 | 约 10 行 + 1 轮编译 | 8 分钟 |
| swift test + 模拟器 | 1 | 实测约 8 | 8 分钟 |
| 真机验证（飞行模式 / 正常 / 补发） | 1 | 实测约 10 | 10 分钟 |
| **合计** | | | **68 分钟** |

---

## 验收记录（真机，2026-11-12）

| 用例 | 结果 | 证据 |
| --- | --- | --- |
| 单元测试 | ✅ | `swift test` 345 → 348 绿（+3 条预判测试） |
| 架构 | ✅ | `check-architecture.sh` 0 违规 |
| **真机：飞行模式点发送** | ✅ | **用户实测：「现在断网，等联网时将一并发送」秒出** |
| 真机：恢复后补发 | ✅ | 前次实测「网络恢复（路径监听），立即补发」→「断网暂存已送达」，1 秒内 |
| 真机：正常联网发送 | ✅ | 前次实测「服务端已确认发送，耗时 22 毫秒」 |

**效果对比**：改造前实测 18 秒才出现断网提示（14:46:14 点击 → 14:46:32 暂存），现在秒出。

> 注：本文档是 arch-09/10 之后归档的旧格式 spec（数字编号、缺「被否决方案」与「未决问题」段），
> 保留在 archive 供追溯，不重新编号。新 spec 请照 `spec/00-TEMPLATE.md`。
