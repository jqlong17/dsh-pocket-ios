---
name: ios-conversation-ui
description: DSH Pocket iOS 对话界面样式经验库：消息气泡、Markdown 渲染（自包含 MarkdownRenderer）、文本选择、表格/图片/键盘交互、滚动与重叠问题。修改 iOS 对话样式或排查布局/渲染异常前先读本 skill；新的 iOS 样式问题与解法也补充到这里。
---

# DSH Pocket iOS 对话样式

本文件是项目内 iOS 对话界面的**样式与布局经验库**。修改对话相关 UI、或遇到"显示异常/错位/重叠/渲染不对"时，先读本文件，再动手。

交互反例（错题本，只追加、不改写已有行）在 `/Users/ruska/projects/skill/ios开发/ios开发反例库/interaction.jsonl`。改展开、收起、滚动、过渡之前先读最后若干条。

## 技术栈与组件选型（不要自研可替代的部分）

| 能力 | 用的组件 | 备注 |
| --- | --- | --- |
| Markdown 渲染（GFM：表格/列表/任务列表/代码块/引用） | **自包含 `MarkdownRenderer`**（块解析在 DSHKit `MarkdownBlockParser`，行内格式用 Foundation `AttributedString(markdown:)`） | 2026-11-24 为支持 iOS 17 移除 Textual（`3a8f22b`）；**无第三方依赖**；选择靠「合并文本块」，见下文 |
| 图片选择 / 拍照 | 系统 `PhotosPicker` + `UIImagePickerController` | 权限文案在 Info.plist |
| 图片保存 | `PHPhotoLibrary` + `NSPhotoLibraryAddUsageDescription` | |
| 分享 | 系统 `ShareLink` | |
| 网络 | `URLSessionWebSocketTask` / `URLSession` | |
| 二维码（插件侧） | 前端 qrcode 库 | 不在 iOS 端 |

原则：**能用成熟组件就不自己写**；只有组件缺能力时才写薄胶水，并记录在这里。

## 消息气泡

- 位置：`MessageRow`（`DSHPocket/DSHPocketApp.swift`）。
- 用户气泡：绿色 `Color(red: 0.08, green: 0.48, blue: 0.37)`，文字白色（`MarkdownBody(foreground: .white)`）。
- 助手气泡：`Color(uiColor: .secondarySystemBackground)`。
- 气泡内边距：水平 14、垂直 11；圆角 17（continuous）。
- 整体列宽：`maxWidth: 720` 居中，适配 iPad（iPhone 上自然铺满）。
- 不要给气泡再加内层背景；Markdown 主题自带背景会叠出"白底套灰泡"。

## Markdown 渲染（自包含 `MarkdownRenderer`，2026-11-24 起）

`MarkdownBody` 只是薄封装（超长内容折叠 + `Equatable`），真正的渲染在 `MarkdownRenderer`：

```
MarkdownBlockParser.blocks(from:)   →  MarkdownTextRuns.group(...)      →  视图
（DSHKit，按行切块）                    （DSHKit，连续文本块合成一段）         每个 .text = 一个 Text
                                                                        其余 = 独立视图
```

- **为什么不用 Textual**：它所有版本都声明 `.iOS(.v18)`；2026-11-24 的 `3a8f22b` 为了支持
  iOS 17 把它移除了，连 `swiftui-math` 一起去掉。已知损失：代码块没有语法高亮、
  表格更朴素、复杂嵌套（列表套列表/引用套代码）按平铺处理。
- 行内格式交给 Foundation：`AttributedString(markdown:options: .inlineOnlyPreservingWhitespace)`
  ——粗体/斜体/行内代码/链接都能解析，且保留原始空白。
- **链接必须显式改前景色 + 下划线**：SwiftUI 默认用 accent 渲染链接，绿色气泡里 accent 也是绿色，
  链接会直接融进背景（2026-11-24 用户发邮箱，看起来像空气泡）。
- 标题字号：H1/H2 = `.title3.weight(.semibold)`，H3 及以下 = `.headline`。
  不要写死 pt 字号（交互规范禁止 `.system(size:)`）。
- 表格是 `MarkdownTable`（SwiftUI `VStack`/`HStack`/`Text`），不追求 GitHub 那套边框；
  列多时压缩换行，**不要**在消息列表里套横向滚动。

## 文本选择（跨行 / 跨块）

**现象**（2026-11-24 用户反馈，截图 `docs/selection-bug.jpg`）：长按拖拽只能选中一两行，
选不了整段回复，列表项之间也连不起来。

**原因**：SwiftUI 的 `.textSelection(.enabled)` 只让**每个 `Text` 各自**可选
（[Apple 文档](https://developer.apple.com/documentation/swiftui/view/textselection(_:)) 原文是
"make **each** contained text view selectable"），SwiftUI 没有跨视图选择。
早先「一块一个 `Text`」的渲染方式，等于把可选范围切成了每个段落/每个列表项。

**处理**：连续的**文本类块**（段落/标题/列表项/引用）由 `MarkdownTextRuns.group` 合成一个 run，
拼成**一个** `AttributedString` 放进**一个** `Text`，选择才能一路连过去。
代码块/表格/图片/分隔线保持独立视图，同时是**选择边界**（这是结构决定的，不是缺陷）。

**代价（有意接受，别再当 bug 报）**：

- 引用竖条用每行 `▍` 前缀重建：独立的竖条视图会把选择切断；
- 列表项换行后，续行不再悬挂缩进（文本流里做不了 `NSParagraphStyle` 的悬挂缩进，SwiftUI `Text` 会忽略它）；
- 块间距从 `VStack(spacing: 10)` 变成空行；连续列表项/连续引用行仍用单换行保持紧凑。

**不要做**：

- 不要为了「每块独立样式」再把文本块拆成多个 `Text`——选择会立刻退回单行。
- 不要用 `Text("a") + Text("b")` 拼：等价但没法按 range 控制字体。
- 不要把代码块也塞进 AttributedString：会丢掉底色与横向滚动，代码块本来就能长按单独选中。

## 布局稳定性（重点，血泪经验）

消息列表结构：`ScrollView { VStack(spacing: 14) { ... } }` + `.defaultScrollAnchor(.bottom)` + `.scrollDismissesKeyboard(.interactively)`。

必须遵守：

1. **用 `VStack` 而不是 `LazyVStack`**。MarkdownUI/图片/表格行高是动态的，LazyVStack 会缓存旧高度导致行重叠。会话窗口只有 30 条消息，全量布局开销可忽略。
   - **2026-11-21 二次实验（结论不变，但原因更清楚）**：滚动帧率埋点显示 `VStack` 滚动时 21-25ms/帧（40-48fps），
     数据层重排只 0.1ms —— 怀疑是「24 条全部参与合成」，于是换 `LazyVStack` 重试。
     **结果：滚动出现明显异常（行重叠/跳动），且帧率并未改善到 60fps。已回滚。**
   - **根因（当时用 Textual）**：行高与**容器实际宽度**耦合；`LazyVStack` 按缓存高度布局，
     宽度/内容变化导致缓存失效 → 错位。同赛道的 Orbis（`docs/参考项目/orbis`）能用 `LazyVStack`，
     是因为它**自己算行高**（`transcript.rows` 预分组），不是让 Textual 现量。
   - **所以：要虚拟化必须自己做行高，不能只换容器。**
   - **正确的降本方向**：只让最近 3 条跑完整 Markdown，更早的降级纯文本（2026-11-21 已转正，
     见 `ConversationView.fullRenderRecentCount`）。用户实测体感明显更顺。
2. **不要在纵向消息列表里嵌套横向 `ScrollView`**（例如给宽表格做横向滚动）。iOS 26 上会出现"表格被缩放/叠到别的消息上"的错位绘制。宽表格宁可让它自适应换行。
3. **行高变化时不要用带动画的 scrollTo**：`proxy.scrollTo(id, anchor: .bottom)` 直接调用，不要包 `withAnimation`。
4. **`.textSelection(.enabled)` 是有意保留的**（为了复制部分文字）：它曾与错位问题一起出现，但真正根因是上面的容器/嵌套滚动。如果以后又出现气泡重叠，先怀疑容器/嵌套滚动，再考虑去掉它作为排查手段。跨块选择见「文本选择」一节。
5. 修改后再排查重叠，先确认真机跑的是新进程：`devicectl install` 不会重启 App，要 `terminate` 后重新 `launch`（或让用户手动强制退出）。曾有多次"改了没效果"其实是旧进程。

排查顺序（由外到内）：容器（VStack/LazyVStack）→ 嵌套滚动 → 动画/选择层 → 单行内容（Markdown/表格/图片）。

## 表格

- `MarkdownTable` 用 `HStack` 等分列宽，列由内容决定、**没有横向滚动**；列多时会压缩换行、行高变大。
- 项目结论：≤3 列体验最好；≥4 列在手机上无完美解（横向滚动会引入嵌套滚动问题），接受换行即可。
- 表格样式集中在 `MarkdownTable` 里（背景 tint 0.04、描边 0.12、单元格 `.footnote`），改版式只动这一个类型。

## 图片

- 缩略图 `AttachmentThumbnail`（150pt 圆角 14）；点击全屏 `FullscreenImageViewer`：黑底、捏合/双击缩放、关闭、分享、保存到相册。
- 上传图发送时本地先显示 `localImages` 缩略图，同样可点开全屏。
- 保存失败（权限被拒）用底部 toast 提示。

### 多图消息把整页宽度撑爆（2026-11-24）

**现象**：一条消息带 5 张图时，整个对话页被撑得超出屏幕——标题、气泡、表格全部左移被裁，
**底部输入栏的发送按钮被推到屏幕右侧之外**（真机反馈「iOS 端甚至看不到发送按钮」）。

**原因**：用户气泡里的缩略图是 `HStack(spacing: 6)` 套固定 88pt 的图：
`5 × 88 + 4 × 6 = 464pt`，而 iPhone 一屏内容宽约 361pt。`HStack` 对固定宽度子视图**不会收缩**，
`Spacer(minLength: 44)` 又被压到最小，这一行的最小宽度 ≈ 534pt。消息列表内层 `VStack`
把这个宽度上报出去，`ScrollView` 的整页宽度被撑开；输入栏按撑宽后的页宽布局，发送按钮就出屏了。
**一处超宽内容毁掉的是整页布局，不只是那个气泡。**

**处理**（缺一不可）：

1. 缩略图**按行换行**，每行几个由可用宽度算（`DSHKit` 的 `ThumbnailWrapLayout`，纯逻辑可单测）：
   `columns = floor((availableWidth + spacing) / (itemSize + spacing))`，至少 1 列。
2. 可用宽度**必须从容器量**（`ConversationView` 在 `ScrollView` 上 `onGeometryChange` 取宽度），
   不能量气泡自己——气泡宽度随内容变化，会绕回同一个溢出。
3. 气泡再封一层 `.frame(maxWidth: maxBubbleWidth, alignment: .leading)` 兜底：
   `maxBubbleWidth = min(720, 容器宽) - 32(列表 padding) - 44(Spacer 最小留白)`
   （`DSHKit` 的 `BubbleWidthPolicy`）。只封顶、不强制撑满，短消息仍然贴着内容收紧。

**不要做**：

- 不要用横向 `ScrollView` 包多图（纵向列表里嵌套横向滚动会错位，见上文第 2 条）。
- 不要用自定义 `FlowLayout: Layout`——它在 `HStack` 里的 ideal width 只能返回「一张图」或
  「一整行」，前者让气泡永远单列，后者继续撑爆；要修好还是得传可用宽度，却多一个不可单测的布局类型。
- 不要只加 `.clipped()`：内容仍超宽，整页照样被撑开。

**验证**：`DSH_DEMO=1 DSH_OPEN=demo-4`（临时把示例改成 5 张图）→ 缩略图 3+2 两行、
页面不左移、发送按钮可见。截图：`/tmp/final-5img.png`（修复后）。

## 进入会话定位最新消息

**现象**：偶发进入会话后停在某些历史消息，而不是最新消息。

**原因**：历史是异步加载的，Markdown 渲染、表格重排、图片/过程行到达都会让内容高度
在"滚动执行完"之后继续增长；`scrollTo` 只执行一次必然可能滚在旧位置。`.defaultScrollAnchor(.bottom)`
只影响首次布局，不负责后续高度变化。

**处理（组合拳，缺一不可）**：
1. 列表尾部放一个 1pt 的**底部锚点** `.id("conversation-bottom-anchor")`，`scrollTo` 锚点而不是最后一条消息；
2. 打开会话 / 历史或快照到达时，在 **~3 秒内多次补滚**（0、0.08、0.2、0.4、0.7、1.1、1.6、2.2、3.0s）；
3. 给内容加 `GeometryReader` + `PreferenceKey` 上报高度；**进入后 4 秒稳定期内**只要高度变化就再贴底；
4. 消息数量、过程行数量变化也触发补滚。

## 进会话上滑被"锁在底部"（2026-11-09）

**现象**：刚进入会话时手指上滑，列表被反复拉回底部，持续 2–4 秒后才恢复。

**原因**：打开会话后有 4 秒首屏稳定期，会分多次 `scrollTo(bottomAnchor)`；用户上滑时只把 `followsLatest` 置 false，没有递增 `scrollGeneration`、也没有清 `isSettlingScroll`，已排期的补滚继续执行。

**处理**：`DragGesture` 第一个 changed 事件里立刻 `scrollGeneration += 1` + `isSettlingScroll = false`（超过阈值再 `followsLatest = false`）；滚动几何检测到离开底部且 `!followsLatest` 时也清 settle。核心原则：**用户的滑动必须能取消所有程序化补滚**。

## 实时流假死（无回复/无过程行）

**现象**：发送消息后，助手回复和"过程"行都不出现，但顶部仍显示"实时连接：已连接"、
"深度求索中 · X 分"。等很久后（或重新进前台）才一次性补出来。

**原因**：公网隧道/代理会在空闲或抖动时**静默断开 WebSocket**，socket 不报错，UI 仍以为已连接，
于是没有任何帧、也不触发重连。诊断日志能证实：那段时间**完全没有收帧记录**。

**处理（双保险）**：
- 记录 `lastLiveFrameAt`；
- 生成中（`isTurnRunning`）的收帧加 **25 秒看门狗**：`withThrowingTaskGroup` race `socket.receive()`
  与 `Task.sleep(25s)`，超时抛错走原有重连逻辑，重连会补发 snapshot；
- `pollLiveFallback` 每 5 秒检查：只要"未连接"或"生成中且 15 秒无帧"，就用 `session/page` HTTP 兜底拉一次；
- 空闲（无生成）时不做 25 秒超时，避免空会话反复重连。

## 连接状态机

- `ConnectionModel.LiveConnectionState`：`idle / demo / connecting / connected / reconnecting(attempt) / disconnected(reason)`；
- UI：状态点颜色（绿/橙/红/灰）+ 文案；`disconnected` 时显示「重连」按钮 → `manualReconnect()`；
- `follow` 维护重连次数并写入状态；生成中无帧 25s 看门狗仍保留；轮询兜底判断 `!liveConnection.isConnected`。

## 会话切换与异步隔离（防串台）

**结构级隔离（2026-11-09 重构）**：每个会话一个 `ConversationState` 实例（messages/steps/turn/
scrollTick/liveTask/token/turnSeqs/发送状态），`ConnectionModel` 只保留 `activeConversation` 与
`conversations[sessionId]` 字典，会话级属性全部转发到 active 实例。切换会话即切换实例：
旧会话数据不会出现在新会话；迟到帧/迟到 await 结果通过 `activeConversation?.sessionId` 校验丢弃。
`ConversationState.isFollowing` 用于判断"实时流是否真的在跑"，避免返回会话时 `liveTask != nil`
但已结束导致不再重连。


**现象**：点进某个会话，偶尔显示其他会话的消息内容。

**原因**：所有 `await` 返回后都必须重新校验"当前会话还是不是发起时的那个"。典型漏洞：
`pollForReply` 在 `await rpc("session/page")` 返回后直接 `mergeMessages/mergeSteps`，
此时用户已切到别的会话 → 旧会话消息串进新会话。

**处理（约定）**：
- 模型里维护 `conversationToken`，`open`/`disconnect` 时更新；异步任务捕获 token，
  落地数据前检查 `token == conversationToken` **且** `selectedSession.sessionId` 未变。
- 所有 `loadHistory` / `pollForReply` / 实时流回调：`await` 之后第一件事就是校验，
  再 merge/append 任何消息或步骤。
- 实时流（`acceptLive`）入口按 `sessionId` 校验；`follow` 的 while 条件同时检查会话未变。
- 新增任何会写 `messages`/`steps` 的异步路径，都要走同样的双重校验，不要只依赖 Task.cancel
  （取消是协作式的，可能晚一拍）。

## 消息顺序：steer 模式不要按 turn 区间重排（2026-11-09 真机验证）

- 曾为"排队消息"按 turn 区间把用户消息排到本轮回复之后；但 **steer 会打断当前轮**，
  用户消息 seq 本来就在回复之前，重排会把「用户消息 → 回复」颠倒成「回复 → 用户消息」。
- 结论：**展示排序 = 服务端 seq 升序**（pending 固定末尾即可）；不要用 turn 区间兜底排序。
- 验证方法：`session/page` 打印 seq，对比 UI 中气泡顺序（本次真实会话 seq 8/29/30 用户消息、
  32 回复，重排 bug 表现为回复跑到用户消息上方）。

## 回到底部与 followsLatest（2026-11-09）

- 点「回到底部」后的补滚必须可被用户滚动取消：`scrollGeneration` 捕获后，**force 也不能豁免**
  generation 校验；补滚次数限制为 [0, 0.15]，否则立刻上滑会被再次拉回底部（已用 XCUITest 覆盖）。
- 行高异步变化（Markdown 表格/图片晚渲染）会让内容变高、底部留白；用 `followsLatest`（用户上滑
  置 false，回底/点箭头置 true）在高度变化时补贴底，而不是只靠几何 `isAtBottom`。
- 已知：长回复首次渲染后仍可能短暂留白，待后续用 contentOffset 校准。

## 发送模式：steer 代替 queue（消除排队）

- DSH `session/prompt` 的 `mode`：`queue` = 追加到当前轮之后（进 inbox 排队，本轮结束后才处理）；
  `steer` = **打断当前轮**并把新消息作为引导继续。
- 约定：`isTurnRunning ? "steer" : "queue"`——生成中发送一律 steer，不再排队；空闲时 queue 等价于普通一轮。
- UI 状态：steer 的消息气泡显示「已引导，正在继续」；普通发送显示「已发出，等待处理」。
- 发送的 `requestId` 必须与发件箱/ pending 记录的一致（曾误用新 UUID 导致 rpcId 对账失效）。
- steer 会中断当前生成，属于产品预期（引导式对话）；若以后要"排队/引导"二选一，加设置项。

## 消息顺序（排队消息）

**现象**：生成中（"深度求索中"）发送的新消息，显示在正在生成那一轮的旧回复上方。

**原因**：DSH 里排队消息的 `user/message` 事件 seq 落在当前 `turn/start` 与 `turn/end`
之间，而这一轮的助手回复 seq 更大；只按 seq 排序就会把"下一轮的用户消息"插到"本轮回复"前面。

**处理**：`ConnectionModel` 记录每轮 `turnStarts` / `turnEnds`（用 seq，去重）；渲染排序时
对落在 turn 区间内的用户消息改用 `displaySortKey` = 该轮 `turn/end` 的 seq，从而排到本轮
回复之后、下一轮回复之前。**同一 sortKey 的多条排队消息必须用原始 seq 做二级排序**，
否则会按 id 随机排（踩过）。服务端 seq 本身是对的，不要改排序基准为时间戳。

## 会话绑定与发送目标（防"消息发到别的会话/丢失"）

- `navigationDestination` 里**不要只靠 `.onAppear { open(session) }`**：同一目的地类型的 onAppear
  在某些 iOS 版本不会重复触发，导致进入 B 会话时 `selectedSession` 还是 A，看着像串台/消息丢失。
  用 `.task(id: session.sessionId) { open(session) }`。
- `ConversationView` 显式持有 `let session: PocketSession`，发送按钮调用
  `model.sendMessage(in: session)`；模型先校验 `selectedSession` 是否一致，不一致先纠正再发。
- 这样"用户看到的会话"和"消息实际发送的会话"始终一致。

## 发送状态机与重发（借鉴 stream-chat LocalMessageState）

- pending 气泡下方显示状态：`发送中…` → `已发出，等待处理`（服务端已 ACK、等队列消费）→ 失败时显示
  `发送失败 + 重新发送` 按钮；
- 状态集合：`ackedSendRpcIds` / `failedSendRpcIds`（按 rpcId），收到服务端 user/message（rpcId 匹配）后清理；
- 失败**不再**把文字塞回输入框，而是保留气泡可重发（`retryPendingMessage` 从发件箱取回文本重新发送）。

## 跟随底部与回到底部（借鉴 SwiftyChat followsLatest）

- `onScrollGeometryChange` 计算距底部距离（≤48pt 视为在底部）→ `isAtBottom`；
- 在底部/首屏稳定期才自动跟随新消息；用户往上翻时不抢滚动，只累计 `unreadWhileScrolled`；
- 非底部时显示右下角**回到底部按钮**（带未读数），点击强制滚到底；
- `scrollToBottom(force:)`：只有按钮或首屏才强制，其余调用受 followsLatest 门控。

## 滚动抢位与历史 pending（2026-11-09）

**问题 1：频繁被拉到底部，无法上滑看历史。**
原因：`loadHistory`/轮询/快照每次合并都会请求贴底，且贴底是 3 秒内 9 次补滚；用户上滑后仍会被抢。
处理：只有"会话首次加载/用户点回到底部/首屏稳定期"才多段补滚，日常新消息只滚一次；
`scrollGeneration` 在用户上滑时递增，使待执行的补滚任务全部失效；每次延迟执行前再次检查
`isAtBottom || isSettling || force`。

**问题 2：历史消息一直显示"发送中"。**
原因：发件箱条目未确认（早期 requestId 与 prompt 不一致）→ 每次合并历史又把它们补成 pending。
处理：发件箱 TTL 降到 10 分钟；合并历史时 pending 保留规则改为"仅在发件箱中或失败待重发"，
不在发件箱的 rpcId 直接丢弃；只有首次加载才自动贴底。

## 消息丢失（发件箱 + rpcId 对账）

**现象**：有时"发出的消息没了"。

**原因**：DSH 的一轮生成中发送的消息进入 `agent.inbox.nextTurn` **队列**，要等本轮结束、
队列被消费时才写成正式的 `user/message` 事件。在这段时间里服务端历史里没有它；如果这时
App 被杀、重进会话、或本地 pending 气泡被清掉，就会出现"消息丢了"的错觉。
另外客户端 `session/prompt` 的 `requestId` 会被服务端回填到 `user/message` 的 `source.rpcId`。

**处理**：
- 发送时生成 `requestId`，pending 气泡和本地**发件箱**（UserDefaults，24 小时过期）都记录它；
- 收到历史/实时用户消息时，**只用 `source.rpcId` 精确对账**；绝不能"文本出现在历史里就算已确认"——
  用户发过同样内容的短消息（如"继续"）时，会把刚发出的 pending 误删，表现为消息发不出去。
  仅在服务端不回 rpcId 时，用"发送之后新出现的最后一条用户消息且文本相同"作为兜底；
- 打开会话时把该会话未确认的发件箱条目重新渲染成 pending 气泡，所以即使重启 App，
  已发出但未落库的消息也不会"消失"；
- 发送失败/取消时移除发件箱条目并把文本还给输入框。

## 文本选择与复制

- **部分/跨行复制**：`MarkdownBody` 上挂了 `.textSelection(.enabled)`；连续的文本块被合并进**一个** `Text`
  （见「文本选择（跨行/跨块）」），所以长按拖拽能跨行、跨列表项、跨引用连续选中，
  到代码块/表格/图片处停住。
- **整条复制**：消息头部（"DSH/你"旁边）的小图标按钮，点击把整条 Markdown 写入 `UIPasteboard`。
- **不要给整行加 `.contextMenu`**：它会拦截长按，导致文本选择无法触发（踩过）。整条复制放头部按钮，长按留给文本选择。
- 图片不参与复制（需要时走全屏预览里的保存/分享）。

## 问答卡（ask_user_question）

卡片本身在 `ConversationStatusViews.swift`（`model.pendingQuestion`），状态机在
`QuestionInbox`：`tool/call` 抬卡片、`tool/result` / 问答回复结算、`turn/end` 收起。

### 已回答的卡片回到会话又弹出来（2026-11-24）

**现象**：选了选项、卡片也收起了；退出会话再进来（或杀掉 App 重开）它又弹出来让人再选。

**原因**：「已回答」以前只记在 `ConversationState.answeredQuestionCallIds`（**纯内存**）。
重进会话时实时协调器推**快照**，把历史步骤重放一遍，`tool/call` 又走一次 `noteAsked`；
而回答的持久证据——`user/message` 且 **`source.kind == "user-question-reply"`**
（正文是 JSON 答案，用 `source.callId` 关联）——我们从来没解析过（解码时还被当成
「不是用户消息」丢掉了）。步骤窗口一旦不包含该问题的 `tool/result`，就没有任何东西能证明它答过了。

**处理**（判定基准是 DSH 官方 `userQuestions` 投影：
`packages/interaction/user-questions/src/projection.ts`）：

- `DSHMessage` 带出 `sourceKind` / `sourceCallId`，解码**允许** `user-question-reply` 通过；
- 摄入时先用它结算卡片，再把它从渲染列表里剔除（正文是 JSON，不能当气泡）；
  HTTP 历史走 `applyRecords`（`mergeSteps(from:)` 里扫描 `questionReplyCallId(fromRecord:)`）；
- `tool/result` **只有非 pending 才结算**：`{"pending":true}` 表示超时后仍可回答。

**不要做**：

- 不要在本地 UserDefaults 里存一份「已回答」当唯一依据——它治不了「电脑端已回答」
  和「步骤窗口截断」，而且官方语义是「会话日志即事实」。
- 不要把 `{"pending":true}` 当成答完：那会把还能回答的问题永久吞掉。

**实测（2026-11-24，1.1.1 build 11 真机）**：手机回答问题后，会话日志里是一条
`tool/result`（`toolCallId` 对得上，正文是 `{"answers":[...]}`），**不是** `user-question-reply`
用户消息——窗口内回答走结果通道，`user-question-reply` 只用于超时后的迟到回答。
两条分支都已覆盖：退出会话再进、**杀进程重进**都不再出现（均已确认）；电脑端回答与超时迟到回答分支待单独验。

**验证步骤**：电脑端触发 `ask_user_question` → 手机回答 → 退出会话再进 / 杀进程重进，
卡片都不应再出现；超时未答（pending）时重新进会话，卡片应在。

## 键盘与输入

- 点对话区空白收键盘：`@FocusState` + `ScrollView.simultaneousGesture(TapGesture())` 置 false。
- 拖拽滚动跟随收起：`.scrollDismissesKeyboard(.interactively)`。
- 不要加键盘上方悬浮"收起"按钮（用户明确不要）。
- 发送态：`isSending` 只覆盖 prompt RPC 阶段；确认后立即恢复发送按钮。停止生成用 `session/cancel`（⏹）。

## 验证方法（本机）

```bash
# 模拟器
xcodebuild -quiet -project DSHPocket.xcodeproj -scheme DSHPocket -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/dsh-pocket-ios-sim-derived \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl install <SIM_UDID> /tmp/dsh-pocket-ios-sim-derived/Build/Products/Debug-iphonesimulator/DSHPocket.app
SIMCTL_CHILD_DSH_DEMO=1 SIMCTL_CHILD_DSH_OPEN=demo-3 xcrun simctl launch <SIM_UDID> com.ruska.dsh-pocket-ios
xcrun simctl io <SIM_UDID> screenshot /tmp/shot.png

# 真机（T626DDUR47）
xcodebuild ... -destination 'id=<UDID>' DEVELOPMENT_TEAM=T626DDUR47 CODE_SIGN_STYLE=Automatic build
xcrun devicectl device install app --device <UDID> <app>
xcrun devicectl device process terminate --device <UDID> --pid <pid>  # 必须重启才生效
xcrun devicectl device process launch --device <UDID> com.ruska.dsh-pocket-ios
```

调试入口（DEBUG 构建）：`DSH_DEMO=1` 进演示模式，`DSH_OPEN=demo-1|2|3` 直接打开示例会话。


## UIKit 列表实验结论（2026-11-09，分支 feat/uikit-message-list）

**现象**：把消息列表换成 UIKit（UICollectionView / UITableView + `UIHostingConfiguration` 承载 SwiftUI `MessageRow`，或内嵌 `UIHostingController`）后，滚动时**气泡里的文字会"滚动"/重排/抖动**，气泡背景与文字不同步；手工测量行高还会出现行重叠。

**原因（当时的渲染器是 Textual）**：我们的消息行是 **复杂 Markdown/表格/代码块**，不是轻量 SwiftUI 文本：
- UIKit cell 复用 + `UIHostingConfiguration` 下，行高由 UIKit 估算/测量，Markdown 渲染完成布局的时机晚于 cell 尺寸确定 → 滚动中反复重排；
- 手动 `UIHostingController.sizeThatFits` 测量也会低估（表格/图片晚布局），导致行高偏小、内容被裁剪或与下一行重叠；
- Element X 能安全使用翻转 UITableView + `UIHostingConfiguration`，是因为它的消息行是轻量 SwiftUI/AttributedString 渲染，不是这种多视图拼装的 Markdown 渲染。

**处理（结论）**：
- **默认保留 SwiftUI `VStack` 消息列表**（虽然无法做像素级锚定，但文字渲染稳定）；
- UIKit 列表代码保留在分支 `feat/uikit-message-list`，仅通过 `DSH_LIST=uikit`（DEBUG）实验开关启用，不要默认开启；
- 以后若要"彻底解决长历史性能"，只有两条路：
  1. 接受 SwiftUI VStack + 分页（现状），做局部性能优化；
  2. 把消息渲染换成 **UIKit 原生（TextKit/AttributedString）**，列表与渲染都用 UIKit —— 工作量大（约 1–2 周），需单独评估。

**不要做**：不要再用"UICollectionView/UITableView + 自适应行高 + SwiftUI Markdown 行"的组合去修重叠；调 `estimatedRowHeight`、预测量、延迟 apply 都只能缓解，不能根治。

## 扩展约定

- 以后所有 iOS 样式/布局问题都补充到本文件对应章节；新领域（例如暗色模式、动态字体、横屏、iPad 分栏）可以新增章节。
- 每一条记录保持三段式：**现象 / 原因 / 处理**，附上最小复现代码或截图路径。
- 记录"不要做什么"往往比"要做什么"更有价值（例如：不要 gitHub 主题、不要嵌套横向滚动、不要 LazyVStack）。
- 若换了组件或改了主题，同步更新"技术栈与组件选型"表，并提交 `Package.resolved`。

## 参考项目（开源，可对照实现）

| 项目 | 可参考点 |
| --- | --- |
| [gonzalezreal/textual](https://github.com/gonzalezreal/textual) | 我们当前用的渲染库；跨视图选择、GFM 表格、`.gitHub`/`.default` 样式 |
| [MarkdownUI issue #264](https://github.com/gonzalezreal/swift-markdown-ui/issues/264) | 说明"只能按段落选中"的限制与业界绕法 |
| [BasedHardware/omi · SelectableMarkdown.swift](https://github.com/BasedHardware/omi/blob/768905c6/desktop/Desktop/Sources/MainWindow/Components/SelectableMarkdown.swift) | 折中方案：整段合并成单个 `Text(AttributedString)` 以获得跨段落选择，代码块单独渲染 |
| [exyte/Chat](https://github.com/exyte/Chat) | SwiftUI 聊天 UI 框架，消息单元/媒体选择可参考 |
| [ml-explore/mlx-swift-examples · Markdown 支持 PR](https://github.com/ml-explore/mlx-swift-examples/pull/303) | 聊天场景下 Markdown 渲染的另一种实现思路 |
| [microsoft/SwiftStreamingMarkdown](https://github.com/microsoft/SwiftStreamingMarkdown) | 微软开源（MIT，iOS 16+）的**流式 Markdown 渲染库**，专为 LLM 流式回复优化：增量解析、表格/代码/图片/LaTeX、约 +1MB；若以后做逐字流式输出优先评估它 |
| [element-hq/element-x-ios](https://github.com/element-hq/element-x-ios) | SwiftUI 版 Matrix 客户端（Element X），完整聊天 App：时间线滚动定位、消息气泡、附件、已读等，细节参考价值最高 |
| [tchapgouv/tchap-x-ios](https://github.com/tchapgouv/tchap-x-ios) | 法国政府基于 Element X 的 SwiftUI 聊天客户端分支 |
| [signalapp/Signal-iOS](https://github.com/signalapp/Signal-iOS) | UIKit 成熟聊天 App，消息渲染/选择/输入体验参考 |
| [wireapp/wire-ios](https://github.com/wireapp/wire-ios) / [nextcloud/talk-ios](https://github.com/nextcloud/talk-ios) / [RocketChat/Rocket.Chat.iOS](https://github.com/RocketChat/Rocket.Chat.iOS) | 其他开源 Swift 聊天客户端 |
| [artcc/openclient-llm](https://github.com/ArtCC/openclient-llm) / [Ichigo3766/Open-Relay](https://github.com/Ichigo3766/Open-Relay) | 原生 SwiftUI LLM 客户端（多 provider / Open WebUI），AI 对话 UI 参考 |
| [EnesKaraosman/SwiftyChat](https://github.com/EnesKaraosman/SwiftyChat) / [GetStream/stream-chat-swiftui](https://github.com/GetStream/stream-chat-swiftui) | SwiftUI 聊天气泡/消息列表组件 |

## 系统推送（APNs）的归属陷阱

**做「锁屏提醒」之前先回答一个问题：这个 App 只给自己用，还是要发给所有人？**

- **只给自己** → 可以走「自己的 APNs Key」，用户 Mac 直接发
- **发给所有人** → **APNs Key 属于开发者，不属于用户**；把 Key 打包进客户端是严重违规，
  App Store 必拒。此时只有两条路：**中心推送服务**（要运维）或 **本地通知 + `BGAppRefreshTask`**（延迟不可控）

**曾犯过的错**（2026-11-21）：想当然认为「每个用户有自己的 Mac 和 DSH」就能各自发推送，
花两小时做完 APNs 全链路才发现凭证归属问题——用户没 Key，方案对公众用户是死的。
详细记录见 `~/projects/skill/代码编写规范/ios踩坑记录.md` 第 29 条。
