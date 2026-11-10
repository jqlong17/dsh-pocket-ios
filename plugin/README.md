# dsh-pocket-ios（DSH 插件）

给 DSH 桌面端加一个原生设置页 **设置 → 手机访问（iOS）**：一个**一次性配对二维码**，iPhone 上的 DSH Pocket 扫码即连，全程不需要输入密码。

- 自带稳定本地入口代理（默认 `127.0.0.1:3091` → DSH web），改写了 `Host/Origin`，经 Tailscale / 代理访问不会再被 DSH 的 browser-auth 判为不可信；
- 二维码是**一次性配对码**：60 秒有效、用后作废、每约 50 秒自动轮换，不包含长期密码；
- 长期密码只保存在本机（`~/.dsh/dsh-pocket-ios/pin`，权限 600），用于手动登录；
- 设置卡片跟随 DSH 界面语言自动中英文切换；
- 不依赖 `dsh-pocket`，可与它同时安装（3091 / 3081 互不冲突）。

## 安装

```bash
dsh plugin add dsh-pocket-ios
```

安装后**重启 DSH** 并刷新页面（client 模块在启动时加载）。

App：<https://apps.apple.com/app/id6832288744>（DSH Pocket iOS）。

设置页位置：账号与余额 → 通用设置 → 手机访问 → **手机访问（iOS）** → 模型。

## 连接流程

### 方式一：Tailscale（推荐，地址固定）

1. Mac 与 iPhone 安装 Tailscale，登录同一账号；
2. Mac 执行一次：

   ```bash
   tailscale serve --bg 3091
   ```

   （Tailscale 后台 DNS 页需开启 HTTPS Certificates）
3. 打开 DSH → 设置 →「手机访问（iOS）」，用 DSH Pocket 扫卡片上的二维码；
4. 自动登录，无需密码。

> 读不到 Tailscale 状态时，可手写配置：
>
> ```bash
> mkdir -p ~/.dsh/dsh-pocket-ios
> echo '{"url":"https://你的机器名.你的tailnet.ts.net"}' > ~/.dsh/dsh-pocket-ios/tailscale.json
> ```

### 方式二：dsh-pocket（局域网/公网，不装 Tailscale）

1. 安装 `dsh-pocket` 插件（它负责局域网/公网通道）；
2. DSH → 设置 →「手机访问」用它的局域网/公网二维码连接；
3. 在 DSH Pocket 里输入它显示的访问密码。

方式二不需要本插件也能连；本插件提供的是扫码免密与统一设置页。

## 端口

- 稳定入口默认 **3091**（避开 dsh-pocket 的 3081）；
- Tailscale Serve 指向 3091：`tailscale serve --bg 3091`；
- 改端口：`DSH_POCKET_IOS_PROXY_PORT=<port> dsh start`，并同步 `tailscale serve`；
- 代理只监听 loopback（`127.0.0.1`）。

## 安全

- 密码/token 不写入日志、不进入构建产物、不进入 Git；
- 二维码只含一次性配对 token，不含长期密码；
- 配对登录通过 DSH 自带 `connection.authenticatedUrl` 换 `dsh-auth` cookie，不另造会话体系；
- 配对 token 只存内存，60 秒过期、单次使用。

## 开发

```bash
npm install
node --check lib/index.js && node --check client/client.js
npm pack --dry-run
```

## License

GPL-2.0，见 [LICENSE](LICENSE)。
