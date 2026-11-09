# dsh-pocket-ios（DSH 插件）

在 DSH **设置 → 手机访问（iOS）** 里加入一个原生设置页：App Store 下载二维码、Tailscale 固定地址与二维码、访问密码管理。

- 不依赖 `dsh-pocket`：插件自带稳定本地入口代理（默认 `127.0.0.1:3081` → DSH web）、自己的登录端点与访问密码。
- 二维码**只包含地址，不包含密码**；密码只保存在本机（`~/.dsh/dsh-pocket-ios/pin`，权限 600）。
- 访问密码支持：显示 / 复制 / 随机更换 / 自定义（8–64 位字母数字），保存后旧密码立即失效。

## 安装

```bash
dsh plugin add dsh-pocket-ios
```

安装后重启 DSH，并刷新页面（client 模块在启动时加载）。

App：<https://apps.apple.com/app/id6832288744>（DSH Pocket iOS）。

## 连接流程

1. 手机安装 Tailscale 并登录同一账号、开启 VPN；
2. Mac 上执行一次：

   ```bash
   tailscale serve --bg 3081
   ```

   （在 Tailscale 后台 DNS 页开启 HTTPS Certificates；插件读取 `tailscale serve status` 得到固定地址）
3. 打开 DSH 设置 →「手机访问（iOS）」→ 用 DSH Pocket iOS 扫描二维码填入地址；
4. 输入设置页显示的访问密码 → 连接。

> 若宿主进程读不到 Tailscale 状态（例如 GUI 应用 IPC 不可用），可手写配置文件：
>
> ```bash
> mkdir -p ~/.dsh/dsh-pocket-ios
> echo '{"url":"https://你的机器名.你的tailnet.ts.net"}' > ~/.dsh/dsh-pocket-ios/tailscale.json
> ```

## APNs 后台完成推送（可选）

1. Apple 开发者后台 → Keys → 新建 **APNs** Key，记录 **Key ID**，下载 `.p8`（只能下载一次），放到 `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`；
2. 确认 App ID 已开启 **Push Notifications** capability；
3. 写配置（权限 600）：

   ```bash
   cat > ~/.dsh/dsh-pocket-ios/apns.json <<'JSON'
   { "keyId": "<KEYID>", "teamId": "<TEAMID>", "environment": "sandbox" }
   JSON
   chmod 600 ~/.dsh/dsh-pocket-ios/apns.json
   ```

   Debug 构建用 `sandbox`，App Store 版本用 `production`；
4. 重启 DSH：插件每 5 秒检测会话 `turn/start → turn/end`，向已注册设备推送「对话已完成」；
5. 通知支持直接回复（含 Apple Watch），回复会作为 prompt 发回对应会话。

推送日志：`~/.dsh/dsh-pocket-ios/tailscale.log`（只记 sessionId、token 尾号、HTTP 状态）；设备 token 存 `push.json`。

## 端口说明

稳定入口默认 **3091**（避开 dsh-pocket 的 3081），可与 dsh-pocket 同时启用：

- Tailscale Serve 指向 3091：`tailscale serve --bg 3091`
- dsh-pocket 继续占用 3081 提供局域网/公网二维码
- 如需改端口：`DSH_POCKET_IOS_PROXY_PORT=<port> dsh start`，并同步 `tailscale serve`

## 安全

- 密码/token 不写入日志、不进入构建产物、不进入 Git；
- 二维码只编码地址；
- 登录端点在校验密码后，通过 DSH 自带 `connection.authenticatedUrl` 换 `dsh-auth` cookie，不另造会话体系；
- 代理只监听 loopback（`127.0.0.1`）。

## 开发

```bash
npm install
# 修改 lib/index.js / client/client.js 后：
node --check lib/index.js && node --check client/client.js
npm pack --dry-run
```

## License

GPL-2.0，见 [LICENSE](LICENSE)。
