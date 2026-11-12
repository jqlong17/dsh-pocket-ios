# 把无状态流程类型合并回 extension

> **Status**: Accepted · 2026-11-12
> **起始日期**：2026-11-12
> **预估工时**：115 分钟（单元累加）
> **对应提交**：`cac6ae0` → `5c804f9` → `3f2eb24` → `b5f0539`（分四步）
> **前置**：`spec/2026-11-12-2257-architecture-self-review.md`（结论来源）

## 背景 / 问题

架构自审量化 11 个对象后发现：**扇出 >10 的四个类型，自有状态字段全是 0**。

| 类型 | 扇出 | 自有状态 | 测试利用 |
| --- | --- | --- | --- |
| `LiveFrameApplier` | 19 | 0 | 否 |
| `NotificationBridge` | 17 | 0 | 否 |
| `LiveStreamRunner` | 17 | 0 | 否 |
| `SessionActions` | 13 | 0 | 否 |

「没有自己的数据」+「要注入 17 个闭包才能工作」= **它不是独立单元，是 `ConnectionModel` 的流程片段**。

给无状态的东西注入 17 个闭包，等于用依赖注入模拟「我是那个类的一部分」——纯增加间接层。
三个指标同时指向同一结论：扇出大、测试利用 0（App 层没有测试 target，注入没换来可测性）、自有状态 0。

**这些类型是 `spec/17` 之后我为凑文件行数额外抽出来的，属于返工对象。**

## 目标与非目标

**目标**
- 四个类型合并为 `extension ConnectionModel`，方法体直接访问模型状态。
- 删除全部 `Providers` 结构与装配代码（共约 66 个闭包参数）。
- **文件仍然分开**（控制行数），只是不再有独立类型。
- `stateless-type-smell` 违规归 0。

**非目标**
- 不动 `ConnectionState` / `SessionStore` / `OutboxCoordinator` / `QuestionInbox` /
  `JobRoster` / `Diagnostics` / `SessionAPI`——它们有自有状态，拆得对。
- 不动 DSHKit 里的纯逻辑（`LiveFrameRouter` / `PromptPolicy` 等）——
  它们扇出 0、可单测，抽出来是正确的。
- 不改任何业务行为。

## 参考实现（Prior art）

- **Swift 的 `extension` 语义**：同一模块内 extension 可直接访问宿主的所有成员（含 private），
  无需依赖注入。这正是「流程片段」的正确表达方式。
- **《A Philosophy of Software Design》的「深模块」**：模块接口越窄越好。
  19 个闭包是 19 个参数的自由函数，比 `extension` 直接访问状态**接口更宽**——
  表面看是解耦，实际接口宽度反而变大。
  → **采用**「接口宽度」作为判据。
- **依赖注入的适用边界**：DI 的价值是**替换实现便于测试**。本项目 App 层无测试 target，
  四个类型的测试利用均为 0 → 注入没有换来可测性 → 不适用。
  → **不采用**「为了可测而保留注入」这个常见理由。

## 方案

### 第 0 步：先定原理

**判据不是「能不能编译」，而是「这个方法属于谁」**：

- 方法读写的全部是 `ConnectionModel` 的状态 → 属于 `ConnectionModel`（用 extension）
- 方法有自己的数据要保护 → 独立类型

四个类型的方法全部满足前者。所以合并它们不是「回退」，是**恢复正确的归属**。

**顺序很重要**：按扇出从少到多做（13 → 17 → 17 → 19），每个做完立刻编译 + 测试，
不要四个一起改。理由：`LiveStreamRunner` 含并发与取消逻辑，一次改四个会让错误无法归因。

### 第 1 步：`SessionActions`（13 闭包）→ `ConnectionModel+SessionActions.swift`

- 做什么：`Providers` 的 13 个闭包替换为 `self.xxx` 直访；删 `installSessionActionProviders()`。
- **为什么先做它**：扇出最小，用于验证「合并模式」是否正确，成本最低。
- 改动范围：`SessionActions.swift` → 重命名为 `ConnectionModel+SessionActions.swift`；
  `ConnectionModel.swift` 去掉 `let sessionActions`；`RootView` 去掉装配调用。

### 第 2 步：`NotificationBridge`（17）→ `ConnectionModel+Notify.swift`

- 做什么：同上。三个方法（`syncPushRegistration` / `sendReply` / `openSessionFromNotification`）
  直接搬进 extension。`UIApplication.beginBackgroundTask` 等 UIKit 调用原样保留。
- **为什么保留这三个方法在 App 层**：它们需要 `UIApplication` 与 `PinKeychain`，
  不属于 DSHKit（纯逻辑层不得依赖 UIKit）。
- 改动范围：`NotificationBridge.swift` → `ConnectionModel+Notify.swift`。

### 第 3 步：`LiveStreamRunner`（17）→ 并入 `ConnectionModel+Live.swift`

- 做什么：`run(sessionId:)` 变成 `extension ConnectionModel` 的方法；`Providers` 全删。
  `receiveFrame` / `sendPing` 作为 `private static` 留在同文件。
- **为什么这步小心**：含 Task 取消、心跳、假死检测。合并时**只换依赖访问方式，
  不改任何时序与并发结构**——循环、`Task.sleep`、`withThrowingTaskGroup` 一律原样。
- 改动范围：`LiveStreamRunner.swift` 删除（内容并入 `+Live.swift`），`+Live.swift` 预计 532 → ~560 行
  （仍在 600 阈值内）。

### 第 4 步：`LiveFrameApplier`（19）→ 并入 `ConnectionModel+Live.swift`

- 做什么：`accept(_:sessionId:)` 变成 extension 方法。帧分类继续用 DSHKit 的 `LiveFrameRouter`（纯逻辑，保留）。
- 改动范围：`LiveFrameApplier.swift` 删除。

### 第 5 步：机器判据与文档

- `stateless-type-smell` 应归 0（脚本已存在）。
- 架构规范补一条判据：**有自有状态 → 独立类型；无自有状态 → extension**，
  并写明「文件行数超阈值只拆文件，不拆类型」。

## 被否决的方案

| 方案 | 否决理由 | 否决依据 |
| --- | --- | --- |
| 保留现状（4 个类型 + 66 个闭包） | 扇出 17–19、测试利用 0、自有状态 0，三个指标同时否定 | 自审数据 |
| 改成持有 `ConnectionModel` 弱引用 | 形成循环引用风险（模型持有它们，它们又持有模型），且仍是两个类型互相知道 | 弱引用会引入 `Optional` 拆包噪音 |
| 把注入改小（聚合成 5 个「能力」结构） | 接口宽度只从 19 降到 5，仍要做一层无收益的适配 | Ousterhout：接口宽度没降到 0 就没有本质改善 |
| 把闭包改成协议 | 协议仍要 19 个方法，只是从闭包换成协议声明，多一层样板 | 同上 |
| **什么都不做** | 代价：每加一个功能都要在 19 个闭包里挑几个传；新人读不懂哪些依赖是真需要 | 本轮自审耗时本身就是征兆 |

## 代价与风险

**代价**（确定会付）
- 115 分钟返工，不产生新功能。
- `+Live.swift` 会变长（532 → 约 560 行），因为并入两个类型的方法体。
- 失去「Providers 结构显式列出依赖」这个优点——但这个优点在没有测试替身时是虚的。

**风险**（可能发生）
| 风险 | 缓解 |
| --- | --- |
| 合并 `LiveStreamRunner` 时改坏并发/取消 | 只换依赖访问方式，时序结构一行不动；每步编译 + 345 测试 |
| `+Live.swift` 超 600 行阈值 | 超过就把 `follow` 相关再拆一个文件（仍不拆类型） |
| 行为回归（发送/实时流） | 真机走查：发消息、生成中 steer、断网补发 |

**为什么不该做这件事**（Drawbacks，诚实写反面）
- 当前代码能跑、真机验证通过、指标全绿。从交付角度，这 115 分钟完全可以用来做功能。
- 合并后单文件变长，读 `+Live.swift` 的人会看到 560 行——虽然类型少了，但**单文件的信息密度上升**。
- 「无状态就该是 extension」不是绝对真理：如果一个流程复杂到需要独立测试，独立类型仍然更合理。
  本项目之所以适合合并，前提是**App 层没有测试 target**；将来若加了 UI 测试，结论应重估。

## 未决问题（Unresolved Questions）

- 合并后 `+Live.swift` 预计 560 行，接近 600 阈值。若后续再长，是拆文件还是重新评估阈值？
  暂定拆文件（写进架构规范）。
- `SessionActions` 合并后，「会话操作」会散在 `+Sessions.swift` 与 `+SessionActions.swift` 两个文件，
  是否该合并成一个文件？取决于行数，本轮先不动。

## 测试计划（先红后绿）

| 用例 | target | 断言 |
| --- | --- | --- |
| 编译 | `xcodebuild` | 每步单独 BUILD SUCCEEDED |
| 逻辑回归 | `DSHKit` | 348 绿（本轮不改 DSHKit） |
| 无状态类型归零 | `check-architecture.sh` | `stateless-type-smell` 违规 0 |
| 文件行数 | 同上 | 无 `file-max` 违规 |
| 真机：发消息 / steer / 断网补发 | 手工 | 三条与合并前一致 |

## 预估工时

| 单元 | 数量 | 单耗依据 | 小计 |
| --- | --- | --- | --- |
| spec 定稿 | 1 | 约 20 | 20 分钟 |
| `SessionActions`（13 闭包） | 1 | 扇出最少，作试点 | 25 分钟 |
| `NotificationBridge`（17） | 1 | 同类 | 25 分钟 |
| `LiveStreamRunner`（17，含并发） | 1 | 时序不能动，需细看 | 35 分钟 |
| `LiveFrameApplier`（19） | 1 | 同类 | 30 分钟 |
| 架构判据 + 文档 | 1 | 约 12 | 12 分钟 |
| 编译 + 测试 + 架构检查 | 4 轮 | 每轮 2 | 8 分钟 |
| **合计** | | | **155 分钟** |

> 比自审里估的 115 分钟多 40 分钟：那里只算了「搬代码」，没算每步的编译验证与文档更新。

---

## 验收记录

| 用例 | 结果 | 证据 |
| --- | --- | --- |
| 编译（每步单独） | ✅ ×4 | 每步一次 `BUILD SUCCEEDED` |
| 逻辑回归 | ✅ | `swift test` 348 绿（全程未变） |
| 无状态类型归零 | ✅ | `stateless-type-smell` 4 → **0** |
| 文件行数 | ✅ | 无 `file-max` 违规 |
| 真机：进会话 → 发消息 | ✅ | **用户实测通过**：实时流正常 |
| 真机：生成中发消息（steer） | ✅ | **用户实测通过**：仍能打断当前轮 |
| 真机：断网发 → 恢复 → 补发 | ✅ | **用户实测通过**：符合预期 |

## 回看：目标达成情况

| 目标 | 结果 |
| --- | --- |
| 四个类型合并为 extension | ✅ 全部完成 |
| 删除 Providers 与装配代码 | ✅ 闭包总数 **66 → 15** |
| 文件仍分开（控制行数） | ✅ 四个文件都在，只是不再是独立类型 |
| `stateless-type-smell` 归 0 | ✅ |

## 数据

| 指标 | 合并前 | 合并后 |
| --- | --- | --- |
| 闭包注入总数 | 66 | **15** |
| app 层行数 | 11,035 | 10,768（−267） |
| `stateless-type-smell` | 4 | 0 |

## 过程中的问题（诚实记录）

四步合计出现 **6 次编译失败**，都不是逻辑问题，全是机械操作造成的：

1. setter 替换后留多余右括号（3 次）
2. 合并后方法名与调用点不一致（1 次）
3. 用 `rindex('}')` 删代码块，把文件从 422 行删到 37 行（1 次，靠 git checkout 恢复）
4. 残留孤立 `@MainActor`（1 次）

**教训**：删代码块不能用「找最后一个大括号」，必须用精确行号或文本标记首尾。
这与反例库 `interaction-019` 是同一类问题——用文本工具做结构化改动。

## 未达成 / 遗留

- 闭包总数还有 15 个（`SessionAPI` 2 个、`Diagnostics` 7 个等），它们对应的类型**有自有状态**，
  注入是合理的，不再合并。
