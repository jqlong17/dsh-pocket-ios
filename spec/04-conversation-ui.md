# 04 · Conversation UI / ViewModel

## 背景

`ConversationView` body 300+ 行，滚动/键盘/发送/排序逻辑都在 View；`MessageRow` 直接读写 model。
参考项目均为 "ViewModel + 小视图 + 可替换组件"。

## 目标

- 抽出 `ConversationViewModel`（滚动意图、发送、取消、重发、加载更早、键盘状态）；
- 拆分视图：`ConversationStatusBar`、`MessageList`、`MessageBubble`、`Composer`、`BackToBottomButton`；
- 保留行为：点空白收键盘、跨行选择、整条复制、图片全屏、iPad 居中、演示模式。

## 参考实现

- `github-references/stream-chat-swiftui/Sources/StreamChatSwiftUI/ViewFactory/*`
- `github-references/SwiftyChat/Sources/SwiftyChat/ChatView.swift`（followsLatest / reachedBottomID）
- `github-references/element-x-ios/.../Screens/Timeline/View/TimelineView.swift`

## 测试用例

### 滚动（ViewModel 单测 + UI 快照）
| ID | Given | When | Then |
| --- | --- | --- | --- |
| U01 | 在底部 | 新消息 | 自动跟随 |
| U02 | 用户上滑 | 新消息 | 不抢滚动，未读数 +1，显示 ↓ 按钮 |
| U03 | 点击 ↓ | 点击 | 滚到底并清零未读 |
| U04 | 进入会话 | 首屏 | 多段补滚直到稳定，最终在底部 |
| U05 | 补滚待执行时用户上滑 | 上滑 | 待执行补滚失效 |

### 发送/输入
| ID | Given | When | Then |
| --- | --- | --- | --- |
| U10 | 有文本 | 点击发送 | 清空输入、pending 入列 |
| U11 | 发送中 | 点击取消 | 撤回 pending，恢复文本 |
| U12 | 生成中 | 发送 | steer 状态显示"已引导" |
| U13 | 失败 | 点击重发 | 重新发送并移除失败态 |
| U14 | 键盘展开 | 点对话区 | 收起键盘 |
| U15 | 生成中 | 继续输入并发送 | 允许（不阻塞输入） |

### 复制/渲染/附件
| ID | Given | When | Then |
| --- | --- | --- | --- |
| U20 | 消息 | 点头部复制 | 剪贴板=整条 Markdown |
| U21 | 长消息 | 长按 | 支持跨行选择 |
| U22 | 用户/助手气泡 | 渲染 | 颜色/内边距/圆角符合 design token |
| U23 | Markdown 表格 | 渲染 | 列对齐、超宽换行 |
| U24 | 附件 | 点击缩略图 | 全屏查看，可保存/分享 |
| U25 | iPad 宽度 | 渲染 | 内容 maxWidth 720 居中 |

### 视图组合（快照测试）
| ID | Then |
| --- | --- |
| U30 | 状态栏 4 种连接状态点/文案正确 |
| U31 | 过程行折叠/展开 |
| U32 | 演示模式横幅 |

## 预计改动

- 新增 `DSHPocket/Features/Conversation/{ConversationViewModel.swift, ConversationStatusBar.swift, MessageList.swift, MessageBubble.swift, Composer.swift}`
- 新增 `DSHPocketTests/ConversationViewModelTests.swift`、`DSHPocketUITests/ConversationSnapshotTests.swift`
- 修改 `DSHPocketApp.swift`：删除 `ConversationView` 内的滚动/键盘/发送逻辑（迁移到 VM）
- 新增 `DSHPocket/Shared/DesignTokens.swift`

## 实施步骤

1. U01–U32 测试（Red，ViewModel 可先用纯函数实现）；
2. ViewModel 抽取，View 改读 VM（Green）；
3. 子视图拆分 + 快照测试；
4. 回归 E2E；覆盖率 ≥85%（ViewModel 层），验收。

## 验收标准

- [ ] U01–U32 全绿；
- [ ] ViewModel 覆盖率 ≥85%；
- [ ] 交互回归通过（滚动/键盘/复制/图片/iPad）。
