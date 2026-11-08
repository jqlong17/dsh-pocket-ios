---
name: ios-conversation-ui
description: DSH Pocket iOS 对话界面样式经验库：消息气泡、Markdown 渲染（MarkdownUI）、表格/图片/键盘交互、滚动与重叠问题。修改 iOS 对话样式或排查布局/渲染异常前先读本 skill；新的 iOS 样式问题与解法也补充到这里。
---

# DSH Pocket iOS 对话样式

本文件是项目内 iOS 对话界面的**样式与布局经验库**。修改对话相关 UI、或遇到"显示异常/错位/重叠/渲染不对"时，先读本文件，再动手。

## 技术栈与组件选型（不要自研可替代的部分）

| 能力 | 用的组件 | 备注 |
| --- | --- | --- |
| Markdown 渲染（GFM：表格/列表/任务列表/代码块/引用） | **Textual**（SPM，`gonzalezreal/textual`，锁 `from 0.1.0`） | MarkdownUI 的继任者；**原生跨视图文本选择**；要求 iOS 18+；`Package.resolved` 已提交 |
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

## Markdown 渲染（Textual）

`MarkdownBody` 使用 `StructuredText(markdown:)` + `.textual.textSelection(.enabled)` + `.textual.structuredTextStyle(.gitHub)`，标题用自定义 `ChatHeadingStyle`。

- **为什么从 MarkdownUI 迁移**：MarkdownUI 的已知限制（[issue #264](https://github.com/gonzalezreal/swift-markdown-ui/issues/264)）——每个段落/块是独立 `Text`，只能按段落选中，无法跨行选择。作者的新库 Textual 用 SwiftUI Text 管线重生，支持跨视图选择。
- **部署目标因此升到 iOS 18**（Textual 所有版本都要求 iOS 18；iOS 18 与 17 支持相同机型，代价可接受）。不要再降回 17，除非放弃 Textual。
- 表格：`.gitHub` 风格自带边框，列多时会压缩换行（与 MarkdownUI 类似），**仍不要**在消息列表里套横向滚动。
- 标题字号用 `ChatHeadingStyle` 的 `fontScales = [1.18, 1.06, 1.0, 0.94, 0.88, 0.76]`（Textual 基准 `.body` = 17pt）：
  实际 H1 20 / H2 18 / H3 17 / H4 16 / H5 15 / H6 13。移动端刻意克制，标题不抢正文；
  权重统一 semibold，间距 `fontScaled(top: 0.9, bottom: 0.35)`。改标题大小只动这个数组。
- 代码块由 Textual 内置语法高亮，样式通过 `structuredTextStyle` 控制，不要自己写高亮。

## 布局稳定性（重点，血泪经验）

消息列表结构：`ScrollView { VStack(spacing: 14) { ... } }` + `.defaultScrollAnchor(.bottom)` + `.scrollDismissesKeyboard(.interactively)`。

必须遵守：

1. **用 `VStack` 而不是 `LazyVStack`**。MarkdownUI/图片/表格行高是动态的，LazyVStack 会缓存旧高度导致行重叠。会话窗口只有 30 条消息，全量布局开销可忽略。
2. **不要在纵向消息列表里嵌套横向 `ScrollView`**（例如给宽表格做横向滚动）。iOS 26 上会出现"表格被缩放/叠到别的消息上"的错位绘制。宽表格宁可让它自适应换行。
3. **行高变化时不要用带动画的 scrollTo**：`proxy.scrollTo(id, anchor: .bottom)` 直接调用，不要包 `withAnimation`。
4. **`.textSelection(.enabled)` 是有意保留的**（为了复制部分文字）：它曾与错位问题一起出现，但真正根因是上面的容器/嵌套滚动。如果以后又出现气泡重叠，再考虑去掉它作为排查手段。
5. 修改后再排查重叠，先确认真机跑的是新进程：`devicectl install` 不会重启 App，要 `terminate` 后重新 `launch`（或让用户手动强制退出）。曾有多次"改了没效果"其实是旧进程。

排查顺序（由外到内）：容器（VStack/LazyVStack）→ 嵌套滚动 → 动画/选择层 → 单行内容（Markdown/表格/图片）。

## 表格

- MarkdownUI 表格实现是 SwiftUI `Grid`（`TableView.swift`），列宽由内容决定、**没有横向滚动**；列多时会压缩换行、行高变大。
- 项目结论：≤3 列体验最好；≥4 列在手机上无完美解（横向滚动会引入嵌套滚动问题），接受换行即可。
- 表格内边距、边框、隔行底色由主题控制；如需调整，改 `.table` / `.tableCell` 块样式，不要自己写表格视图。

## 图片

- 缩略图 `AttachmentThumbnail`（150pt 圆角 14）；点击全屏 `FullscreenImageViewer`：黑底、捏合/双击缩放、关闭、分享、保存到相册。
- 上传图发送时本地先显示 `localImages` 缩略图，同样可点开全屏。
- 保存失败（权限被拒）用底部 toast 提示。

## 会话切换与异步隔离（防串台）

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

## 文本选择与复制

- **部分/跨行复制**：Textual 的 `.textual.textSelection(.enabled)` 支持**跨段落/跨块**选择（这是迁移的核心理由）。长按文字出现选择手柄，可跨行、跨列表选中后复制。
- **整条复制**：消息头部（"DSH/你"旁边）的小图标按钮，点击把整条 Markdown 写入 `UIPasteboard`。
- **不要给整行加 `.contextMenu`**：它会拦截长按，导致文本选择无法触发（踩过）。整条复制放头部按钮，长按留给文本选择。
- 图片不参与复制（需要时走全屏预览里的保存/分享）。

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
