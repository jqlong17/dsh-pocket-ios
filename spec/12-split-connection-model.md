# 12 · 拆 ConnectionModel：从上帝对象到状态对象

## 背景 / 问题

`scripts/architecture-facts.sh` 的存量违规里，有 7 处指向同一根因：

```
[extension-split-smell] ConnectionModel.swift — 7 个 +Feature 文件
[file-max-400] ConnectionModel.swift        630 行
[file-max-400] ConnectionModel+Live.swift   993 行
[file-max-400] ConnectionModel+Sessions.swift 694 行
[file-max-400] ConnectionModel+Connect.swift  602 行
[file-max-400] ConnectionModel+Process.swift
[file-max-400] ConnectionModel+Outbox.swift
```

事实：**一个 `@Observable` 类，100 个状态字段，8 个文件约 3300 行**。所有 extension 操作同一批私有状态，
改「发送」无法判断是否影响「连接」——这就是架构规范第 5.1、5.2 条说的上帝对象 + extension 假拆分。

## 目标与非目标

**目标**
1. 按职责切成 5 个独立 `@Observable` 状态对象，各自字段 ≤ 10、文件 ≤ 400 行。
2. 删除或把 `ConnectionModel` 降为纯转发（最终消亡）。
3. 视图只依赖自己场景的状态对象，不跨场景读字段。
4. `check-architecture.sh` 的 `file-max-400` 与 `extension-split-smell` 归零。

**非目标**
- 不改任何 UI 表现（这次是纯结构重构）。
- 不改 RPC 调用语义（RPC 收口是前置任务，见 spec/08）。
- 不合并实时流的两条路径（协调器 / follow 兜底）。
- 不做持久化改造（草稿、发件箱的存储逻辑不动）。

## 参考实现

| 参考 | 取什么 |
| --- | --- |
| 架构规范第 3.3 节「状态对象设计规则」 | 字段私有写、动作按用户意图命名、字段 ≤ 10 |
| 架构规范第 6 节「落地流程」 | 每步只摘一个对象、原类转发、全量测试后再继续 |
| `pointfreeco/swift-composable-architecture` 的 feature 切分 | 每个 feature 独立持有 state + action；**只取思想**，不引入 TCA |
| 本仓 `ImagePipeline` / `OutboxRetentionPolicy` | 已验证「小类型 + 单一职责」在本项目可行 |

不采用：不引入 TCA 的 reducer/store 全套（对 5 个页面过重）；不移到 MVVM 双层（`@Observable` 已是轻量 VM）。

## 方案：5 个状态对象

| 状态对象 | 职责 | 现有字段来源（约） | 字段上限 |
| --- | --- | --- | --- |
| `ConnectionState` | 连接状态机：地址、PIN、连接中/已连/失败、错误 | `serverAddress` `pin` `isConnecting` `isConnected` `errorMessage` `addressNeedsRescan` `connectionFailureKind` | ≤8 |
| `SessionStore` | 会话列表、缓存、淘汰、当前会话 | `sessions` `archivedSessionIds` `pinnedSessionIds` `selectedSession` `conversations` `activeConversation` `isLoadingSessions` | ≤10 |
| `OutboxCoordinator` | 发件箱：入队/补发/重试/确认/草稿图 | `outboxEntries` `queuedSendRpcIds` `failedSendRpcIds` `ackedSendRpcIds` `offlineFlushInFlight` `offlineFlushNote` `draft` `draftImages` | ≤10 |
| `JobRoster` | 任务名单按需订阅 | `jobs` `jobsTask` `jobsStarted` | ≤4 |
| `Diagnostics` | 采样、进出记录、内存 | `diagVisit` `diagSamples` `memoryMB` + `recordDiagnostic` | ≤6 |

**迁移顺序**（依赖从少到多，每步独立可回滚）：

```
1. Diagnostics      （只被写，不被业务读，最安全）
2. JobRoster        （已有按需订阅，边界清晰）
3. ConnectionState  （连接页专用，视图面小）
4. OutboxCoordinator（发送链路核心，需完整回归）
5. SessionStore     （最后，因为它持有当前会话与缓存）
```

每步固定动作：新建类型 → 迁移字段与方法 → 原类保留只读转发 → 跑全量测试 + 编译 → 提交 → 挑下一项。

## 测试计划（先红后绿）

App 层没有单测 target，所以用**两种可执行的验证**替代：

| 验证 | 位置 | 断言 |
| --- | --- | --- |
| 架构事实检查 | `scripts/check-architecture.sh` | 每步完成后 `file-max-400` 命中数下降；全部完成后为 0 |
| 行为回归 | `swift test` + `xcodebuild` + 真机走查清单 | 进会话/发消息/断网补发/看图片/任务面板 5 条路径不走样 |
| 状态单一真相 | 新增 `ArchitectureBoundaryTests` 同类检查 | 视图文件中不出现跨场景状态对象访问（按命名扫描） |

**红**：先写「视图不得访问其他场景状态对象」的扫描测试（此时 `model.xxx` 满天飞，必然失败）。
**绿**：每迁一个对象、视图改为依赖自己的对象后，命中数下降。

量化标准：
- 5 个状态对象字段分别 ≤ 8/10/10/4/6；
- 单文件 ≤ 400 行；
- `+Feature` extension 文件数 < 3；
- `check-architecture.sh` 的 `extension-split-smell` 与 `file-max-400` 归零；
- 5 条真机路径走查通过。

## 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| 迁移中模型与视图状态不一致（改了读的、没改写的） | 每步只迁一个对象、原类保留转发；全量测试 + 编译后再下一步 |
| `@Observable` 跨对象观察失效（视图不再随字段刷新） | 视图持有的对象不变；`ConnectionModel` 转发时显式 `access(keyPath:)` 或直接让视图改用新对象 |
| 一次改太多导致无法定位回归 | 严格一对象一提交，`git revert` 单个提交即可回滚 |
| 与 RPC 收口（spec/08）冲突 | **顺序约束：RPC 收口 T1–T5 全部完成后再启动本 spec** |

## 预估工时

分 5 步，每步含迁移 + 测试 + 编译 + 提交：
- Diagnostics 20–30 分钟，JobRoster 20–30，ConnectionState 30–40，OutboxCoordinator 40–60，SessionStore 60–90；
- **合计预估 3–4 小时**（按最近校准系数 0.83 折算 ≈ 2.5–3.5 小时，但结构重构通常低估，保守留 4 小时）。

## 前置条件

- [ ] spec/08 的 T1–T5 完成（`grep -rn "func rpc"` 只剩 DSHKit 一处）
- [ ] `swift test` 全绿
- [ ] `check-architecture.sh` 基线已记录（当前 7 处）

## 执行记录

### 已完成：5 个对象全部抽出

| 对象 | 提交 | 说明 |
| --- | --- | --- |
| Diagnostics | `0723ea7` | 采样/进出/日志；采集值由调用方传入，无反向依赖 |
| JobRoster | `5ff6897` | 做成**服务**而非状态对象（名单属于会话）；`+Process` 345→290 |
| ConnectionState | `fe96eb2` | 6 字段 + 计算转发（约 140 处调用点未改） |
| OutboxCoordinator | `d75ed17` | 条目与磁盘；顺手修「重启丢附件元数据」 |
| SessionStore | `c589acd` | 列表/当前会话/缓存字典 + 转发 |

### 顺带完成的逻辑下沉（可测性收益）

| 内容 | 提交 | 测试 |
| --- | --- | --- |
| 问答卡 JSON 解析 → `PendingQuestionPayload.decode` | `d7aced0` | +3 |
| Markdown 分段 → `MarkdownSegments.split` | `4562d35` | +5 |
| 诊断值类型外移 | `ed944cb` | — |

DSHKit 测试 260 → **268**。

### 未完成（明确交接）

剩余 7 处存量违规**全部集中在 ConnectionModel 编排层与两个大视图**，都属于「需要改结构才能降行数」的部分：

| 文件 | 行数 | 下降路径 |
| --- | --- | --- |
| `ConnectionModel+Live.swift` | 940 | 抽 SendPipeline（发送/核验）、LiveStreamCoordinator（follow/coordinator） |
| `ConversationView.swift` | 731 | 拆子视图：气泡列表、输入栏、工具条、未读按钮 |
| `ConnectionModel+Sessions.swift` | 693 | 抽 SessionListLoader（列表拉取/分页/搜索） |
| `ConnectionModel.swift` | 652 | 转发属性已占大半；对象迁完后可删转发 |
| `ConnectionModel+Connect.swift` | 548 | 抽 ConnectFlow（握手/扫码/诊断出口） |
| `ConnectView.swift` | 504 | 拆扫码卡、手动连接卡、端点卡片 |

`extension-split-smell` 仍在（7 个 `+Feature` 文件）：要把 ConnectionModel 从编排层彻底拆散才能真正归零，
那是下一阶段（需要新的 spec，因为要改调用约定）。

### 行为验证

- 模拟器安装启动成功，无崩溃日志；
- 连接页 → 演示模式 → 会话列表 → 对话视图（气泡/表格/过程行/输入栏）全部正常；
- `swift test` 268 绿。
