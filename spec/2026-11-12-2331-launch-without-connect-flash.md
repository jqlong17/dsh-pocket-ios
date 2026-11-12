# 启动时不再闪一下连接页

> **Status**: In Review
> **起始日期**：2026-11-12
> **预估工时**：45 分钟（单元累加）
> **对应提交**：（完成后回填）
> **文件名**：`spec/2026-11-12-2331-launch-without-connect-flash.md`

## 背景 / 问题

用户观察：凭证有效时启动 App，会**闪一下连接页**再进会话列表。

**根因**（读代码确认）：`RootView` 只有两态判据 `isConnected`。

```swift
if model.connection.isConnected { ConnectedView(...) } else { ConnectView(...) }
```

启动瞬间 `isConnected == false`，于是先渲染完整的 `ConnectView`（含扫码引导卡片、地址输入框），
等 `restoreConnection()`（读 Keychain 地址 → 放回 cookie → `fetchSessions`）跑完才切到列表。
这段约 200–800 毫秒的窗口就是用户看到的闪烁。

**加重因素**：项目没有启动图资源（`Assets.xcassets` 里无 LaunchImage，`Info.plist` 无 `UILaunchScreen`），
所以系统启动是白屏 → 直接跳到有内容的连接页，对比更明显。

## 目标与非目标

**目标**
- 凭证有效时启动不再出现连接页，直接进会话列表。
- 恢复过程用**极简占位**承接，不显示任何文字（用户不应感知「恢复中」这个技术状态）。
- **绝不出现永久白屏**。

**非目标**
- 不实现会话列表本地缓存（方案 B）。理由见「被否决的方案」。
- 不改连接页本身的任何内容或布局（它仍然是无凭证时的首屏）。
- 不改 `restoreConnection` 的恢复逻辑。

## 参考实现（Prior art）

- **Apple《Human Interface Guidelines》的 Launch Screen 指引**：启动画面应与首屏视觉一致，
  让「启动 → 可用」在视觉上无缝，避免出现「第三个中间页面」。
  → **采用**：占位用与首屏一致的浅色背景 + 居中图标，不引入新配色或新文案。
- **iOS App 的常见做法**：用 `Color(.systemBackground)` + 品牌图标承接，
  而不是 `ProgressView()`——转圈会让用户以为在等网络，而多数情况下几百毫秒内就完成了。
  → **采用**：不用转圈，用静态图标。
  → **不采用**：不用文字（「恢复中」「加载中」都会放大等待感）。

## 方案

### 第 1 步：`ConnectionState` 增加「恢复已结束」标志

```swift
/// 启动恢复流程是否已结束（成功、失败、无地址都算结束）。
var hasFinishedRestore = false
```

**为什么放在 `ConnectionState` 而不是 `ConnectionModel`**：它是连接状态机的一部分，
视图需要 `@Observable` 观察它变化；`ConnectionState` 本身就是被观察的状态对象。

**为什么默认 `false`**：启动即进入「未确定」态，这是本方案的前提。

### 第 2 步：`restoreConnection` 用 `defer` 保证所有路径都置位

```swift
func restoreConnection() async {
    defer { connection.hasFinishedRestore = true }
    ...原有逻辑，含全部 return 分支...
}
```

**为什么用 `defer` 而不是在每个 return 前手写**：`restoreConnection` 有 5 条提前返回路径
（demo 模式、`DebugLaunch.showConnect`、`DebugLaunch.demoMode`、`DebugLaunch.server`、
无地址/地址无效），手写必然漏。**漏一条就是永久白屏**，这是本方案最危险的失败模式。
`defer` 在进入时注册，任何路径退出都会执行。

### 第 3 步：2 秒超时兜底

`RootView.onAppear` 里起一个任务：

```swift
Task {
    try? await Task.sleep(for: .seconds(2))
    if !model.connection.hasFinishedRestore {
        model.connection.hasFinishedRestore = true
        model.recordDiagnostic("启动恢复超时 2 秒，直接显示界面")
    }
}
```

**为什么需要**：`fetchSessions()` 可能因网络问题长时间挂起（服务端不回、隧道不通）。
没有兜底就会停在占位页，而占位页没有转圈、没有文字，用户只会觉得「App 死了」。

**为什么是 2 秒**：真机实测恢复约 200–800 毫秒，2 秒足够覆盖慢网，又不会让人等太久。
超时后不是放弃恢复——`restoreConnection` 仍在后台跑，完成时自然切换页面。

### 第 4 步：`RootView` 三态渲染

```swift
if !model.connection.hasFinishedRestore {
    LaunchPlaceholder()                 // 占位
} else if model.connection.isConnected {
    ConnectedView(model: model)
} else {
    ConnectView(model: model, connection: model.connection)
}
```

`LaunchPlaceholder`：`Color(.systemBackground)` + 居中 SF Symbol（`sparkles`，与品牌色一致），
**无文字、无转圈**。

**为什么用 SF Symbol 而不是 App 图标**：`Assets.xcassets` 里没有可用的启动图标资源，
硬塞 `AppIcon` 在 SwiftUI 里需要额外处理；SF Symbol 同色系，视觉上足够承接。

## 被否决的方案

| 方案 | 否决理由 | 否决依据 |
| --- | --- | --- |
| 显示「恢复中…」文字 | 把技术状态暴露给用户，放大等待感 | HIG：不要让用户感知启动细节 |
| 显示 `ProgressView()` 转圈 | 转圈暗示「在等网络」，而多数情况几百毫秒完成，反而显得慢 | 同上 |
| 会话列表本地缓存（方案 B） | 要处理缓存失效、切换电脑、数据新鲜度三种情况，改动量翻倍；收益只是「连占位都看不到」 | 相比方案 A 边际价值低 |
| 不加超时兜底，靠恢复本身结束 | `fetchSessions` 可能长时间挂起 → 永久白屏 | 本方案最危险的失败模式 |
| 用 `sleep` 硬等再显示 | 白屏更久 | — |
| **什么都不做** | 代价：每次启动闪一下完整连接页，含扫码引导，观感差 | 用户反馈 |

## 代价与风险

**代价**（确定会付）
- 新增一个状态字段与一个占位视图（约 30 行）。
- 启动路径多一个分支，读 `RootView` 的人要理解三态。

**风险**（可能发生）
| 风险 | 缓解 |
| --- | --- |
| 漏掉某条 return 路径 → 永久白屏 | 用 `defer` 而非手写；真机验证无地址启动 |
| 恢复真卡住 → 占位停留 | 2 秒超时兜底 + 诊断日志 |
| 占位与连接页背景色不一致 → 二次闪烁 | 都用 `systemBackground`，真机看过渡 |

**为什么不该做这件事**（Drawbacks，诚实写反面）
- 这只是观感优化，不解决任何功能问题。若启动恢复本身足够快（<100ms），
  用户根本注意不到闪烁，这 45 分钟就是白花。
- 引入「未确定」态后，`RootView` 从两态变三态，**逻辑复杂度换观感**——
  且这个态只在启动瞬间存在，是很难被测到的状态。

## 未决问题（Unresolved Questions）

- 占位用 SF Symbol 是否足够？如果后续有正式 App 图标资源，应改为图标以贴近启动图。
- 2 秒超时阈值没有实测依据（基于「恢复约 200–800ms」的观察），需要多设备样本校准。
- 是否该把「启动恢复耗时」纳入诊断指标？目前只有超时才有日志。

## 测试计划（先红后绿）

| 用例 | target | 断言 |
| --- | --- | --- |
| 编译 | `xcodebuild` | BUILD SUCCEEDED |
| 逻辑回归 | `DSHKit` | 348 绿（本轮不改 DSHKit） |
| 架构 | `check-architecture.sh` | 违规 0 |
| 真机：有凭证启动 | 手工 | 不出现连接页，占位→列表；日志无「超时」 |
| 真机：无凭证启动 | 手工 | 占位→连接页；日志无「超时」 |
| 真机：demo 模式启动 | 手工 | 占位→列表；不卡住 |

## 预估工时

| 单元 | 数量 | 单耗依据 | 小计 |
| --- | --- | --- | --- |
| spec 定稿 | 1 | 实测约 15 | 15 分钟 |
| 状态字段 + defer | 1 | 约 8 行 | 5 分钟 |
| 占位视图 | 1 | 约 15 行 | 8 分钟 |
| RootView 三态 + 超时 | 1 | 约 12 行 | 8 分钟 |
| 编译 + 测试 + 架构 | 1 | 实测 6 | 6 分钟 |
| 真机三条路径 | 1 | 实测 10 | 10 分钟 |
| **合计** | | | **52 分钟** |
