# 更新日志

本项目的版本更新记录。App Store 版本号与 GitHub Release 的 Build 号对应关系见每节标题。

## [1.0.3] — 2026-11-09（Build 13，审核中）

- 实时同步迁移到 **DSHKit `SessionSyncCoordinator`**（连接状态机、重连、看门狗）：统一处理快照、增量、断线重连，连接状态与「重连中/已断开」更准确。
- 消息按**服务端 seq 排序**；生成中发送走 **steer**（引导当前回复，不再排队）；修复点「回到底部」后被强制拉回的滚动问题。
- 首页「连接你的 DSH」新增 **「使用说明」入口**，直达飞书产品文档（公开可读）。
- **局域网优先自动连接 + 会话页手动切换地址**：启动时优先尝试局域网，连不上自动切公网；会话页右上角可手动切换，不用每次重新扫码。
- 连接页改版：**12pt 圆角紧凑布局**，统一边距与图标/按钮对齐，一屏显示，减少滚动。
- TLS / 地址失效时给出**友好提示 + 一键重新扫码**（电脑隧道地址变化时不再只报英文错误）。
- demo 示例数据升级：**Markdown 长回复、表格、代码块、图片**示例，更接近真实使用场景。

## [1.0.0] — 2026-11-08

- 首个 App Store 版本：原生 SwiftUI iOS 客户端，远程连接电脑上的 DeepSeek Harness（DSH）。
- 会话列表与实时对话、Markdown 渲染（含表格/代码块）、图片发送与查看、整条消息复制、iPad 布局、演示模式。
- 配套 DSH 插件：`dsh-pocket`（连接基础）与 `dsh-pocket-ios`（iPhone 使用引导与下载二维码）。
- 支持局域网与 Cloudflare Tunnel 公网两种连接方式。

[1.0.3]: https://github.com/jqlong17/dsh-pocket-ios/releases
[1.0.0]: https://github.com/jqlong17/dsh-pocket-ios/releases
