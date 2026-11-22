# 技术索引

> **用途**：改功能或排查问题前，先在这里定位「这件事在哪个文件」。
> **别只看一半**：本文件存在的直接原因是 2026-11-22 的一次判断失误——只读了
> `markdownImageURL` 的前半段（http/https 直用），没读后半段（本地路径转 `/api/file`），
> 于是凭直觉去猜 URL、得出「本地图不能显示」的错误结论，还差点为此加一套多余的路由。
>
> **维护**：新增能力时补一条。用「文件 · 符号」而不是行号（行号会漂移）。
> `scripts/check-tech-index.sh` 会校验每一条的符号是否还存在。

## 0. 架构分层

| 层 | 目录 | 约束 |
| --- | --- | --- |
| 纯逻辑 | `DSHKit/Sources/` | 禁止 import UI 框架；可单测；阈值 400 行 |
| App | `DSHPocket/` | 编排 + 视图；阈值 600 行 |

- 检查脚本：`scripts/check-architecture.sh`（读 `docs/architecture/fact.json`）
- 已知存量：`DSHPocket/Session/ConnectionModel.swift` 663 行（Swift extension 不能加存储属性，拆不动）

## 1. 连接

| 能力 | 位置 | 要点 |
| --- | --- | --- |
| 连接编排 | `DSHPocket/Session/ConnectionModel+Connect.swift` | 地址解析、连/断、重连 |
| 地址策略（局域网优先） | `DSHKit/Sources/DSHKit/Protocol/EndpointPolicy.swift` · `DSHEndpointPolicy` | 端点分类 + 配额（lan 3 / 公网 5 / 自定义 2） |
| 自动选路 | `DSHPocket/Session/ConnectionModel.swift` · `autoRouteEnabled` | 默认开；用户可关 |
| 服务器 URL 解析 | `DSHPocket/Session/ConnectionModel+Endpoints.swift` · `serverURL` | 所有相对路径都以它为 base |
| 错误文案 | `DSHPocket/Model/ConnectionError.swift` | 面向用户的中文提示 |

## 2. 发送

| 能力 | 位置 | 要点 |
| --- | --- | --- |
| 发送主流程 | `DSHPocket/Session/ConnectionModel+Send.swift` · `sendMessage` | `requestId` 生成一次、存 outbox，重试复用（不会重复发） |
| 离线队列 | `DSHPocket/Session/ConnectionModel.swift` · `outboxEntries` | 断网时暂存，恢复后重放 |
| 发送态集合 | `DSHPocket/Session/ConnectionModel.swift` · `queuedSendRpcIds` / `ackedSendRpcIds` / `failedSendRpcIds` | 三套 id 分别表示 排队/确认/失败 |

## 3. 对话与渲染

| 能力 | 位置 | 要点 |
| --- | --- | --- |
| 按 turn 合并 | `DSHPocket/Session/ConnectionModel+History.swift` · `mergeByTurn` | 相邻同 `turn` 的助手消息合成一条，`text` 用 `\n\n` 拼 |
| `turn` 从哪来 | `DSHKit/Sources/DSHKit/Protocol/Decoding.swift` · `fromEvent` | 读 `data.turn`；`DSHMessage` 之前漏了这个字段 |
| 精简模式判定 | `DSHPocket/Views/ConversationTimeline.swift` · `isCompactMessage` | 最近 10 条完整渲染，其余纯文本 |
| 精简文本解析 | `DSHPocket/Views/MessageRow.swift` · `compactBlocks` | 空行 = 段落分隔；表格、代码块、整行图片各自成块（代码块不再丢弃） |
| 极简表格 | `DSHPocket/Views/MessageRow.swift` · `CompactTable` | VStack + HStack + Text，不走 Textual |
| 完整 Markdown | `DSHPocket/Views/MarkdownBody.swift` · `MarkdownBody` | Textual `StructuredText` |
| Markdown 样式 | `DSHPocket/Views/ChatHeadingStyle.swift` · `ChatStructuredStyle` | 段落用 `GitHubParagraphStyle.gitHub` |
| 消息行 | `DSHPocket/Views/MessageRow.swift` · `MessageRow` | 文本/图片/排队态的装配 |
| 时间线构建 | `DSHPocket/Views/ConversationTimeline.swift` · `entries` | 消息 + 过程 + 失败 → 可渲染条目 |

## 4. 图片（三条路径，别混）

| 来源 | 入口 | 取图方式 |
| --- | --- | --- |
| **用户发的图 / 附件** | `DSHPocket/Views/AttachmentThumbnail.swift` | 走 `attachmentId`，DSH 附件接口 |
| **markdown 里的 http(s) 图** | `DSHPocket/Views/RemoteMarkdownImage.swift` | 直接用该 URL |
| **markdown 里的本地路径** | `ConnectionModel+Endpoints.swift` · `markdownImageURL` | 转成 `/api/file?path=<绝对路径>`，**需要登录态（未登录返回 401，不是 404）** |

- 取字节与缓存：`DSHPocket/Model/ImagePipeline.swift` · `ImagePipeline` / `ThumbnailDiskCache`
- 字节来源抽象：`DSHPocket/Model/ImageSources.swift` · `AttachmentByteSource` / `RemoteURLByteSource`
- **反例（别再犯）**：不要用 `/docs/xxx.png` 这种静态路径去测——DSH 没有静态文件路由，
  但**不代表本地图不能显示**，真实路径是 `/api/file`。

## 5. 历史分页

| 能力 | 位置 | 要点 |
| --- | --- | --- |
| 触发加载 | `DSHPocket/Views/ConversationView.swift` · `onScrollGeometryChange`（`topOffset < 80`） | 快到位就加载，不要求滑到最顶 |
| 发起请求 | `DSHPocket/Session/ConnectionModel+Live.swift` · `loadOlderMessages` | 记录 `olderAnchorID` 供加载后锚定 |
| 分页与判定 | `DSHKit/Sources/DSHKit/Sync/SessionSyncCoordinator.swift` · `loadOlder` | 每页 10 条；**判据只认「这页有没有新增消息」**，不信任服务端 `hasMore` |
| 视口保持 | `DSHPocket/Views/ConversationView.swift` · `olderLoadTick` | `scrollTo(anchor, anchor: .top)` |
| 保留上限 | `DSHPocket/Session/ConnectionModel.swift` · `inSessionMessageLimit`（200）/ `retainedMessageLimit`（24） | 会话内 200，切走回 24 |

## 6. 通知

| 能力 | 位置 | 要点 |
| --- | --- | --- |
| 本地通知 | `DSHPocket/Model/CompletionNotifier.swift` | 无 APNs（凭证属开发者不属用户），用本地通知 |
| 后台刷新 | `DSHPocket/Model/BackgroundRefresh.swift` | `BGAppRefreshTask`，唤醒时机由 iOS 决定 |

## 7. 插件面板

| 能力 | 位置 | 要点 |
| --- | --- | --- |
| 面板容器 | `DSHPocket/Views/PluginPanelSheet.swift` | WebView；数据服务端直出，页面里不 fetch 自己的 RPC |
| 插件侧路由 | `plugin/lib/index.js` · `webServer.register`（`PLUGIN_CHANNEL = /dsh-pocket-ios`） | 前缀注册，可加子路由 |
| 移动端分级 | `public/插件移动端分级.md` | L0/L1/L1.5/L2a/L2b 的定义与成本 |

## 8. 设置与持久化

| 能力 | 位置 | 要点 |
| --- | --- | --- |
| 设置页 | `DSHPocket/Views/AppSettingsSheet.swift` | 开关；部分走 `didSet`，部分走专门方法 |
| 自动持久化的开关 | `DSHPocket/Session/ConnectionModel.swift` · `showToolProcess` / `autoRouteEnabled`（`didSet`） | 直接赋值即落盘 |
| 手动持久化的开关 | `ConnectionModel+Sessions.swift` · `toggleCompletionAlerts` | 改它**必须**走这个方法，直接赋值不落盘 |
| 密钥/凭证 | `DSHPocket/Support/AppSupport.swift` · `PinKeychain` / `ConnectionVault` | Keychain 封装 |

## 9. 诊断与遥测

| 能力 | 位置 | 要点 |
| --- | --- | --- |
| 遥测上报 | `DSHPocket/Support/TelemetryReporter.swift` | 写到 `~/Library/Logs/DSHPocket/app-telemetry-*.jsonl` |
| 遥测字段 | `DSHPocket/Session/ConnectionModel+Diagnostics.swift` | 含 `rawMsgCount` / `mergedMsgCount` / `hasMoreOlder` / `olderLoadAttempts` |
| 渲染模式标识 | `DSHPocket/Session/ConnectionModel.swift` · `renderModeLabel` | `showToolProcess ? "full" : "compact"` |
| 本机诊断日志 | `DSHPocket/Support/DiagFileLog.swift` | App 沙盒内，`devicectl` 才拉得到 |

## 10. 工具与脚本

| 脚本 | 作用 |
| --- | --- |
| `scripts/architecture-facts.sh` | 扫描分层/依赖/行数/违规 → `docs/architecture/fact.json` |
| `scripts/check-architecture.sh` | 按 fact.json 判违规，退出码 1 |
| `scripts/check-tech-index.sh` | 校验本文件里每条「文件 · 符号」是否还存在 |
| `scripts/record-checkpoint.sh` | 大改动前后记录检查点 |
| `docs/website/build.py` | 文档站 `doc.xml` → `index.html`（本地，不入库） |

## 附：本仓库的三条硬规则

1. **`docs/` 一律不入库**（整体 gitignore）。README 要展示的界面图放 `assets/screenshots/`。
2. **改动需用户验证通过后才提交**，不要自己拍板。
3. **改了 `DSHKit` 必须全新构建**（`rm -rf /tmp/dd-fresh`），否则可能链接旧产物，
   表现是「代码改了、行为没变」。
