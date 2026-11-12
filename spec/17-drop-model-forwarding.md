# 17 · 消除 ConnectionModel 的转发层


> **Status**: Accepted · 真机三条主链路通过
## 背景 / 问题

spec/13 批次 2 的设计决定是「5 个状态对象各自独立，`ConnectionModel` 保留转发」。
这个决定当时是对的——它让状态对象抽离可以分批进行，不必一次改完所有调用点。但它留下了尾巴：

`ConnectionModel` 现在有 **17 个纯转发属性**，它们的实现只是 `get { obj.x } set { obj.x = newValue }`：

| 目标对象 | 转发属性 |
| --- | --- |
| `connection` | `addressNeedsRescan` `errorMessage` `isConnected` `isConnecting` `pin` `serverAddress` |
| `outbox` | `offlineFlushInFlight` `offlineFlushNote` |
| `sessionStore` | `activeConversation` `archivedSessionIds` `conversations` `isLoadingSessions` `navigationPath` `pinnedSessionIds` `selectedSession` `sessionListRetryTask` `sessions` |

**为什么这是问题**：

1. **耦合没真正解除**。视图与业务代码写 `model.sessions`，看到的是 `ConnectionModel`（一个知道 11 个对象的门面）。
   真正要改会话列表时，改的是 `SessionStore`，但所有调用点看起来都在跟 `ConnectionModel` 说话。
2. **Binding 必须落在真实对象上**。批次 3 已经把视图改成 `@Bindable var connection: ConnectionState`，
   说明 `$model.pin` 这种转发绑定根本走不通——转发层在 SwiftUI 里不是免费的。
3. **它是「知道所有东西」的证据**。576 行里 17 个转发约占 90 行，删掉后才谈得上「只做编排」。

## 目标与非目标

**目标**
- 删除全部 17 个纯转发属性（`get`/`set` 仅转给单一对象、无附加逻辑）。
- 调用点改为直读：`model.connection.xxx` / `model.sessionStore.xxx` / `model.outbox.xxx`。
- `ConnectionModel` 只保留：对象引用、场景专属状态、**带副作用的访问器**、业务方法。
- 完成后 `ConnectionModel` 预期降至 **≤480 行**（当前 576）。

**非目标**
- 不删带副作用的访问器：`draft` / `draftImages`（写入要落盘 `DraftStore`）、
  `messages` / `steps`（转发到 `activeConversation` 且参与派生计算）。它们不是纯转发。
- 不改任何业务方法签名与行为。
- 不动 `activeConversation` 的**方法级**使用（它是会话场景的核心引用，保留在模型上；
  仅删除其属性转发时需评估：**保留此属性**，因为它不属于「纯转发给别人的字段」，见方案第 3 条）。

## 参考实现

- **SwiftUI `@Observable` 的既有实践**：`@Bindable` 需要可写引用，转发属性无法直接取绑定
  （本项目批次 3 已实测：`$model.connection.serverAddress` 报 `cannot assign to property: 'connection' is a 'let' constant`）。
  这说明「门面转发」在 SwiftUI 数据流里本就不成立，删它是让代码结构与框架语义一致。
- **Facade 反模式**：Martin Fowler 的 *Law of Demeter* 与 *Facade* 两说。
  Facade 适用于「子系统复杂、对外要简化」；这里是**单一模型对外提供全部字段**，
  属于把两个职责（编排 + 数据归属）压在一个类型上，不是 Facade 的适用场景。

## 方案

### 第 0 步：先定原理，再动手（本 spec 最重要的一条）

**原理**：删转发属性的本质是**字段所有权的可见性转移**——字段本来就属于某个状态对象，
`ConnectionModel` 只是把它「代理」出来。所以改动只应发生在**使用者侧**。

由此推出三条硬约束：

| 约束 | 理由 | 不遵守的后果（实测） |
| --- | --- | --- |
| **不改定义者**：`ConnectionState` / `SessionStore` / `OutboxCoordinator` 等文件一行都不动 | 它们的字段定义就是所有权本身 | 我用全局正则把 `var serverAddress` 改成了 `connection.serverAddress`，状态对象自己被写坏，连续 8 轮编译失败 |
| **按 `self` 类型决定写法**：在 `extension ConnectionModel` 内是 `connection.x`；在视图里是 `model.connection.x`；闭包里是 `self?.connection.x` | 改写形态取决于使用者的上下文，不是文本长相 | 批量替换时 `self.pin` / `model.pin` / `$model.pin` 三种形态各漏一轮 |
| **靠编译器逐处确认**，不做「全局替换 → 报错 → 再替换」的循环 | 编译器知道 `self` 是 `ConnectionModel` 还是 `ConnectionState`，正则不知道 | 8 轮编译往返，每轮 30–60 秒，且每次修完又冒出新的误伤 |

**被否决的替代方案**：
- ❌「全局正则一次替换完」——看起来快，实际因无法区分定义/使用而反复损坏源码（已实测）。
- ❌「保留转发但改成显式 `connection.` 前缀的属性」——等于把转发层换个名字，没有解决«视图不知道在跟谁说话»的问题。

### 第 1 步：分类 17 个属性（先分类，再动手，不靠猜）

| 类别 | 属性 | 处理 |
| --- | --- | --- |
| A 纯转发（12 个） | `pin` `serverAddress` `isConnected` `isConnecting` `errorMessage` `addressNeedsRescan` `sessions` `archivedSessionIds` `pinnedSessionIds` `isLoadingSessions` `selectedSession` `navigationPath` `offlineFlushNote` `offlineFlushInFlight` | **删除**，调用点改直读 |
| B 零引用（2 个） | `conversations`（0 处）、`sessionListRetryTask`（0 处） | **直接删除**，无调用点需改 |
| C 场景核心（3 个） | `activeConversation` | **保留**：它是「当前打开哪个会话」这一场景状态，不是别人家的字段 |

> 说明：`activeConversation` 虽在 `sessionStore` 里，但它是本场景（会话编辑）的核心句柄，
> 且被 `messages`/`steps`/`draft` 等访问器依赖。删它会导致模型不再持有当前会话，属于改行为，超出本 spec。

### 第 2 步：按文件批量替换调用点（约 110 处）

| 文件 | 预计处数 | 说明 |
| --- | --- | --- |
| `DSHPocket/Session/ConnectionModel+Connect.swift` | ~20 | `serverAddress` `pin` `errorMessage` `isConnected` |
| `DSHPocket/Session/ConnectionModel+Sessions.swift` | ~25 | `sessions` `pinnedSessionIds` `selectedSession` |
| `DSHPocket/Session/ConnectionModel+Live.swift` | ~15 | `isConnected` `errorMessage` `activeConversation` |
| `DSHPocket/Session/ConnectionModel+Outbox.swift` | ~10 | `offlineFlushNote` `offlineFlushInFlight` |
| `DSHPocket/Session/ConnectionModel+Send.swift` | ~8 | `selectedSession` `conversationError` |
| `DSHPocket/Session/ConnectionModel+History.swift` | ~10 | `sessions` `selectedSession` |
| `DSHPocket/Session/ConnectionModel+Endpoints.swift` | ~8 | `serverAddress` `pin` |
| `DSHPocket/Session/NotificationBridge.swift` 装配段 | ~6 | 闭包里的 `self?.pin` 等 |
| `DSHPocket/Session/LiveStreamRunner` 装配段 | ~5 | 同上 |
| `DSHPocket/Views/*` | ~5 | 视图已直读，剩余少量 |

**做法**：一次改一个文件 → 编译 → 修错误 → 下一个。不要批量替换后一次性编译
（`pin` 这类短名容易误伤，例如 `pinnedSessionIds`、`pin.slash` 图标名）。

### 第 3 步：编译驱动的补齐

删掉转发后，编译器会指出所有遗漏点。按错误逐个改，**不猜**。

### 第 4 步：护栏

新增机器判据 `pure-forwarding-smell`：`ConnectionModel.swift` 里出现
`get { <对象>.<字段> }` 形状的纯转发即违规。写入 `scripts/architecture-facts.sh`，
防止以后又长回来。

## 测试计划（先红后绿）

本次是纯结构改动，不改行为。可测的部分都在 DSHKit 之外，因此：

| 用例 | target | 断言 |
| --- | --- | --- |
| 转发层归零 | `scripts/check-architecture.sh` | `pure-forwarding-smell` 违规 0 |
| 模型行数 | 同上（`fact.json`） | `ConnectionModel.swift` ≤480 行 |
| 行为不变（回归） | `cd DSHKit && swift test` | 345 绿，无新增失败 |
| 构建 | `xcodebuild` 模拟器 | BUILD SUCCEEDED |
| 三页链路 | 手工（模拟器） | 连接页可输入地址/密码 → 演示模式列表 → 对话页 |
| 真机 | 手工 | 连接、发消息、断网补发、DSH 重启免扫码 各一次 |

## 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| `pin` 等短名替换误伤（`pinnedSessionIds`、`pin.slash`） | 用词边界正则 `\bmodel\.pin\b`；一次只改一个文件并编译 |
| 漏改导致编译不过，越改越乱 | 每个文件改完立刻编译，错误当次修掉，不堆积 |
| `activeConversation` 误删导致会话打不开 | 本 spec 明确保留（C 类），不删 |
| 行为意外变化 | 无逻辑改动；真机走查连接/发送/补发三条主链路 |
| 改动过大难以回滚 | 每个文件一个提交，或整批一个提交 + 明确 revert 点；检查点先记 baseline |

**回滚**：单批提交，`git revert <sha>` 即恢复转发层；状态对象本身未动，功能不受影响。

## 预估工时

**估算方法**：不凭总时长直觉，按最小验证单元累加（依据 `scripts/estimate-from-history.sh`：
「逐点重构」类历史实际中位 45 分钟/次；「文件拆分」38 分钟/次）。

| 单元 | 数量 | 单耗依据 | 小计 |
| --- | --- | --- | --- |
| 分类 + spec 定稿（已完成） | 1 | 实测 20 | 20 分钟 |
| 删除 1 个转发属性（含调用点定位） | 17 | 实测约 1.5/个 | 25 分钟 |
| 调用点替换（逐文件，编译驱动） | ~110 处 | 20–30 分/百行 | 30 分钟 |
| 编译往返（每轮约 1.5 分钟） | 4–5 轮 | 实测 | 7 分钟 |
| 护栏脚本 `pure-forwarding-smell` | 1 | 类比 duplicate-attribute 约 12 | 12 分钟 |
| swift test + 模拟器三页 | 1 | 实测 15 | 15 分钟 |
| 真机走查 | 1 | 实测 20 | 20 分钟 |
| **合计** | | | **129 分钟** |

**为什么不是 180 分钟**：初版是按「直觉总量」拍的。检查点数据显示
预估/实际倍率在各规模档位都稳定在 0.61–0.63，说明偏差来自估算模型本身而非规模——
真正的成本驱动是「需要判断的地方」，不是行数。本次改为按单元累加。

已消耗（截至当前进度）：约 15 分钟（删 6 个 connection 转发 + 修 5 处内部调用 + 1 轮编译）。
**剩余预期约 110 分钟。**

---

## 真机验收记录（2026-11-12，用户实测通过）

| 用例 | 结果 | 日志证据 |
| --- | --- | --- |
| 连接页输入地址 → 连接 | ✅ | 「已保存长期设备凭证（下次 DSH 重启免扫码）」 |
| 进会话 → 发消息 | ✅ | 「用户点击发送：2 字」→「服务端已确认发送，耗时 22 毫秒」 |
| 断网发消息 → 恢复 → 自动补发 | ✅ | 「网络不可达，已写入断网暂存」→「网络恢复（路径监听），立即补发」→「断网暂存已送达」 |

结论：删除 16 个转发属性、约 110 处调用点改直读之后，连接 / 发送 / 断网补发三条主链路行为未变。

### 顺带发现：断网到「暂存」之间隔了 18 秒

日志显示 `14:46:14 点击发送` → `14:46:32 写入断网暂存`，期间用户看到的是「发送中」。

原因：发送时**没有网络预判**，完全靠请求失败后分型。`rpcWithRetry` 会重试 3 次
（退避 800/2000/3000ms），若每次还要等 TCP 超时（20 秒），最坏可到 60 秒。

`NWPathMonitor` 已经知道网络不可达（它就是后来触发补发的那个监听），但没有把
「当前是否可达」暴露给发送路径。改进方向：发送前预判，不可达直接 `holdOffline`。
已记录为后续优化项，不在本 spec 范围。
