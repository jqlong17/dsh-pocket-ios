# 稳定检查点：2026-11-10

## 当前部署形态（本机验证通过）

- 插件 `dsh-pocket-ios@0.2.1`（host 稳定版，无 APNs 代码）
- 插件自带稳定代理：`127.0.0.1:3091` → DSH web（端口动态）
- `tailscale serve --bg 3091` → `https://ruskamacbook-pro-1.tail619842.ts.net`
- dsh-pocket 保留 `127.0.0.1:3081`，提供局域网/公网二维码（小火箭场景使用）
- 设置页两个原生 tab：「手机访问（iOS）」（本插件）+「手机访问」（dsh-pocket）
- 访问密码：`~/.dsh/dsh-pocket-ios/pin`（随机 8 位，设置页支持显示/复制/随机更换/自定义）
- 二维码只包含地址，不包含密码
- App 登录优先级：本插件 `/dsh-pocket-ios/login` → 失败回退 dsh-pocket `/pocket-login`

## 已验证

- 手机 Tailscale 通道登录成功（HTTP 302 → dsh-auth cookie）
- 密码管理端点（`pin.set` 兼容 `payload.args` 与扁平参数）
- 图片附件 `bytes` 字段修复（附件加载失败会显示占位）
- 键盘/气泡布局稳定（`safeAreaInset` + 垂直 `fixedSize`）

## 待办（暂停中）

- **APNs 后台推送**：host 代码已回滚（`ctx.sessions` 注入问题导致加载崩溃）；需改用 `ctx.inject(['sessions'], …)` 隔离设计后重做；需要 Apple APNs `.p8` + Key ID
- **通知/Apple Watch 回复**：App 端代码已完成，最新构建尚未装到手机验证
- **npm 发布** `dsh-pocket-ios@0.2.1`：包已就绪，缺 `npm login`
- **App Store 1.0.5**：把这批修复打包提交（1.0.4 审核中）

## 操作约定

- 不要让 agent 用 `kill` 强杀 DSH 进程（会造成 "host stopped" 假崩溃）；需要重启时请用户手动退出再打开
- 插件 host 改动必须重启 DSH 生效；client 改动强刷页面生效
- profile 崩溃恢复会重置 `cordis.patch.yml` 与第三方 bundles，恢复后需重新注册 bundles
