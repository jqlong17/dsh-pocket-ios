---
name: ios-conversation-ui
description: DSH Pocket iOS 对话界面样式经验库：消息气泡、Markdown 渲染（MarkdownUI）、表格/图片/键盘交互、滚动与重叠问题。修改 iOS 对话样式或排查布局/渲染异常前先读本 skill；新的 iOS 样式问题与解法也补充到这里。
---

# DSH Pocket iOS 对话样式

本文件是项目内 iOS 对话界面的**样式与布局经验库**。修改对话相关 UI、或遇到"显示异常/错位/重叠/渲染不对"时，先读本文件，再动手。

## 技术栈与组件选型（不要自研可替代的部分）

| 能力 | 用的组件 | 备注 |
| --- | --- | --- |
| Markdown 渲染（GFM：表格/列表/任务列表/代码块/引用） | **MarkdownUI**（SPM，`gonzalezreal/swift-markdown-ui`，锁 `upToNextMajor 2.4.1`） | 不要自研解析器；`Package.resolved` 已提交 |
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

## Markdown 主题（`.chat`）

`MarkdownBody` 使用自定义主题 `Theme.chat`（基于 `.basic` 派生，见 `DSHPocketApp.swift`）：

- **不要用 `.gitHub` 主题**：它会给内容块加背景色，叠在气泡上出现内嵌白底。
- 标题（以 iOS 根字号 17pt 计）：H1 22 / H2 19 / H3 17 / H4 15 / H5 14 / H6 12，半粗；
  标题上边距约 0.6–0.9em、下边距 0.2–0.35em（比 basic 更紧凑）。
- 段落：下边距 0.7em、行距 0.12em。
- 代码块：自定义 `.markdownBlockStyle(\.codeBlock)`，等宽 0.88em、内边距 10、`primary.opacity(0.06)` 圆角底、横向滚动。
- 表格：默认 MarkdownUI 布局（SwiftUI `Grid`，内容自适应换行），**不要**在消息列表里给表格套横向 `ScrollView`（见"布局稳定性"）。

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

## 文本选择与复制

- **部分复制**：消息气泡的 Markdown 视图开启 `.textSelection(.enabled)`，长按文字出现系统选择手柄后可复制任意片段。
- **整条复制**：`MessageRow` 外层加 `.contextMenu`，长按气泡弹出「复制整条消息」，写入 `UIPasteboard`（原始 Markdown 文本）。
- 图片不参与复制（需要时走全屏预览里的保存/分享）。
- 长按行为的优先级：文本选择与 contextMenu 可能冲突；若用户反馈长按选不中文字，优先保证选择，把整条复制改成别处入口（例如消息左侧菜单）。

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
