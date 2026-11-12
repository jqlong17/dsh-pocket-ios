# 08 · RPC 收成一套（TDD，待批准后执行）

## 背景

同一件事有两份实现：

| 位置 | 实现 | 现状 |
| --- | --- | --- |
| `DSHKit/DSHClient.rpc(method:args:)` | 用 `RPCRequest` 编码，走可注入的 `DSHHTTPTransport`，错误抛 `DSHError` | 会话列表、快照、聊天分页在用 |
| `ConnectionModel.rpc(_:args:timeout:)` | 手拼同一份 envelope，走 `URLSession.shared`，错误抛 `ConnectionError` | 其余 20 处调用点在用 |

两份都在拼 `{type: client-request, rpcId, method, payload:{args}}`，协议知识重复；改一处容易漏另一处。
这正是架构评审里「App 和 DSHKit 各有一套 RPC 客户端」那条。

## 目标

1. 协议实现只剩 DSHKit 一份，App 只调用、不再拼 envelope。
2. 超时、重试、错误分型集中在一处，且**可单测**（`DSHClient` 已支持注入 `DSHHTTPTransport`）。
3. 删除 App 的 `ConnectionModel.rpc` 与 `rpcWithRetry`，20 处调用点全部改到 DSHKit。
4. 行为不变：发送仍然按同一 rpcId 重试、仍然只在瞬时错误上重试。

## 非目标

- 不改 UI 文案（连接失败分类已经做完）。
- 不合并实时流的两条路径（协调器 / follow 兜底）。
- 不改服务端协议，不改 envelope 结构。

## 参考实现

**第一手：本机现有代码（行为基线，改完必须与它等价）**

| 位置 | 现在的行为 | 我们取什么 |
| --- | --- | --- |
| `DSHKit/DSHClient.rpc(method:args:)` | `RPCRequest.encoded()` 编码 envelope；按状态码 `DSHError.from`；返回 `result.value` | envelope 编码与状态码映射原样保留 |
| `DSHPocket/Session/ConnectionModel+Live.rpc(_:args:timeout:)` | 手拼同一份 envelope；`timeoutInterval` 默认 20 秒；`httpShouldHandleCookies`；抛 `ConnectionError` | **超时 20 秒**这条语义搬进 DSHKit |
| `ConnectionModel.rpcWithRetry` | `attempts = 3`；只对 `DSHNetworkErrorPolicy.isTransient` 重试；退避 800 ms / 2000 ms；失败不重发不同请求 | 重试次数、仅瞬时、退避节奏原样保留 |
| `DSHKit/Tests/DSHKitTests/MockTransports.swift` | `MockHTTPTransport` 可注入、记录每个 `URLRequest` | 测试全部走它，不起真实网络 |

**第二手：开源项目的做法（只取思想，不引依赖）**

- 依赖注入以便测试：`pointfreeco/swift-dependencies` 的思路——把网络、时钟、随机数做成可替换依赖。
  我们的 `DSHHTTPTransport` 已经是这个形态，本轮只是把「超时」也做成可注入参数。
- 幂等重试：业界通用做法是「同一 requestId 重试，服务端去重」（Alamofire 的 `RequestRetrier` 概念）。
  **采用其思想**（同一 `rpcId` 贯穿重试），**不采用其实现**（不引入第三方网络库）。

**采用 / 不采用清单**

| 决策 | 采用 | 不采用 | 原因 |
| --- | --- | --- | --- |
| 超时 | 搬进 DSHKit，默认 20 秒，可显式传 | 交给每个调用点自己设 | 调用点自己设必然不一致（现状就是 App 20 秒、DSHKit 无限） |
| 重试 | 纯函数 `RPCRetryPolicy` + `rpcWithRetry` | 内联 while 循环 | 策略要能被穷举测试，内联无法单测 |
| 错误 | 统一 `DSHError` | 保留两套错误类型 | 两套类型是这次收口的根因 |
| 退避 | 沿用 800 ms / 2000 ms | 改指数退避 | 非目标；改了要重新验证发送体验 |

## 设计

### DSHKit 新增（加法式）

```swift
// 超时与重试都在这里，调用方不再关心
public func rpc(method: String, args: [String: Any], timeout: TimeInterval = 20) async throws -> [String: Any]

/// 同一个 rpcId 重试；仅瞬时错误重试（服务端按 rpcId 去重，不会重复执行）
public func rpcWithRetry(method: String, args: [String: Any],
                         attempts: Int = 3, timeout: TimeInterval = 20) async throws -> [String: Any]
```

### 错误统一

- `RPCRequest.value(from:)` 需要同时认两种失败形状：顶层 `error`，以及 `result.ok == false`（App 现在只认后者）。
- `DSHError` 增加到「连接失败分型」所需的信息：`unauthorized` / `rateLimited` / `server(status:)` / `transport` / `invalidPayload` 已够用。
- App 侧保留 `ConnectionError`，但只作为 `DSHError` 的适配层（`ConnectionError.from(DSHError)`），不再承载协议判断。

### 重试策略抽成纯函数

```swift
public enum RPCRetryPolicy {
    public static func shouldRetry(_ error: Error, attempt: Int, maxAttempts: Int) -> Bool
}
```

## 测试（先红后绿）

| 测试类 | 用例 |
| --- | --- |
| `RPCValueParsingTests` | 顶层 `error` → `DSHError.server`；`result.ok == false` → 带消息的 server 错误；缺 `result.value` → invalidPayload；非法 JSON → invalidPayload；正常返回 value |
| `RPCRequestShapeTests` | 编码出的 envelope 字段与 rpcId 稳定；同一 `RPCRequest` 重试时 rpcId 不变 |
| `DSHClientRPCTests`（MockTransport） | 请求打到 `api/<method>`、方法为 POST、body 是 envelope；401→unauthorized；429→rateLimited；5xx→server；成功取 `result.value` |
| `DSHClientTimeoutTests`（MockTransport 记录 URLRequest） | 默认 20 秒；显式传入时生效 |
| `DSHClientRetryTests`（MockTransport 计数） | 瞬时错误重试到 `attempts` 次后抛出；永久错误（401）第一次就抛；重试期间 rpcId 与 args 不变 |
| `RPCRetryPolicyTests` | 瞬时/永久/次数上限边界 |
| ~~`ConnectErrorAdapterTests`~~ | **不可落地**：App 层没有单元测试 target（只有 XCUITests），适配器类测试无处可放。改为在 T1 迁移时用「连接页四类失败手工走查」验证，并在 spec 记一条待办：若后续加 App 单测 target 再补。 |

## 迁移批次（每批独立可回滚）

| 批次 | 内容 | 验证 |
| --- | --- | --- |
| 1 | 只读接口：`session/page`（3 处）、`session/list`、`session/modelCatalog`、`session/attachment` | 测试 + 进会话、展开过程、加载图片 |
| 2 | 写接口（不含发送）：`session/rename`、`session/selectModel`、`session/create`、`session/cancel`、`workspace/*`（3 处）、`userQuestions/answer` | 测试 + 重命名/新建/归档/回答确认卡 |
| 3 | `push.register`、`push.unregister` | 测试 + 冷启动看诊断里 APNs 注册结果 |
| 4 | 发送路径：`session/prompt`（走 `rpcWithRetry`） | 测试 + 断网排队、恢复补发、网络抖动重试 |
| 5 | 删除 App 的 `rpc` / `rpcWithRetry`，全量测试与真机走查 | `grep -rn "func rpc"` 只剩 DSHKit 一处 |

每批完成后：`swift test` 全绿 → `xcodebuild build` 成功 → 装机验该批涉及的功能。

## 风险与回滚

- **风险最高的是批次 4（发送）**：错误类型从 `ConnectionError` 换成 `DSHError` 后，排队/失败判定可能走偏。
  对策：先加适配层让两条类型并存，等批次 4 通过了再删旧类型；`flushQueuedSends` 的判定要有测试覆盖（已有 outbox 测试可扩展）。
- 每批都是独立提交，出问题直接 revert 那一批，不影响前面的批次。
- 全程在分支 `feature/single-rpc` 上做，`main` 不动；批准前不合入。

## 验收标准

1. `grep -rn "func rpc" DSHKit DSHPocket` 只有 DSHKit 一处定义。
2. App 层 `[String: Any]` 手工拆解再降一批（当前 26 处）。
3. `swift test` 全绿且新增用例 ≥ 15 条（预计 196 → 210+）。
4. 真机走查：连接、进会话、展开过程、发文字、发图片、断网排队、重连补发、重命名、归档、确认卡回答。
5. 分支合入前给你看 diff 摘要与测试结果。

## 批准点

**本文件提交后停下，等你 approve 再执行第 1 批。**

## 执行记录

### T0（DSHKit 侧基础能力）— 已完成

提交 `d023904`；检查点见 `git-checkpoints.jsonl`（baseline `90d6ea0` / result `d023904`）。

交付：
- `DSHClient.rpc(method:args:timeout:)`，超时默认 20 秒；
- `DSHClient.rpcWithRetry(...)`，同一 rpcId 贯穿重试；
- `RPCRetryPolicy`（仅瞬时错误、退避 800/2000/3000ms）；
- `RPCRequest.value(from:)` 识别 `result.ok == false`；
- `DSHClient` 支持注入 `retrySleep`，测试无需真实等待。

验证：`swift test` 242 → **254 全绿**；`xcodebuild build` 成功（App 未接线，行为不变）。

量化标准自查：
- 新增测试 12 条（目标 ≥15 中已用 12，剩余由 T1–T4 迁移测试补齐）；
- `grep -rn "func rpc"` 目前仍是**两处**（T5 才删）——符合分阶段预期，不是遗漏。

### 未做（T1–T5）

按设计里的迁移批次，App 侧 20 处调用点尚未迁移；App 的 `ConnectionModel.rpc` / `rpcWithRetry` 仍在服役。
完成标志：全仓 `func rpc` 只剩 DSHKit 一处。

### 执行中发现的 spec 问题（已修正）

1. 原 spec 缺「参考实现」段 → 已补（本机行为基线 + 开源思想 + 采用/不采用清单）。
2. `ConnectErrorAdapterTests` 不可落地（App 层无单测 target）→ 已标注，改为 T1 时手工走查。
