# dsh-pocket-ios（DSH 插件）

给 DSH 桌面端加一个原生设置页 **设置 → 手机访问（iOS）**：**四种连接方式可以随时切换**，iPhone 上的 DSH Pocket 扫码即连，全程不需要输入密码。

- **四种方式全部由这一个插件提供**，不再需要第三方 `dsh-pocket`：

  | 方式 | 适合 | 手机端要装 |
  | --- | --- | --- |
  | **局域网** | 手机和电脑同一 Wi-Fi | **什么都不用** |
  | **Cloudflare** | 人在外面，任何网络 | **什么都不用**（首次电脑自动下载约 20MB cloudflared） |
  | **Tailscale** | 长期使用，要固定地址 | Tailscale（两端同一账号） |
  | **EasyTier** | 自主组网，不依赖境外服务 | Shadowrocket 等代理 App |

- 自带稳定本地入口代理（默认 `0.0.0.0:3091` → DSH web），改写了 `Host/Origin`，经隧道或代理访问不会被 DSH 的 browser-auth 判为不可信；
- 二维码是**一次性配对码**：5 分钟有效、可重复打开（不再用后作废）、剩余 30 秒自动轮换，不包含长期密码；
- 配对后插件会种一个 `dsh-pocket-device` cookie（1 年有效），App 存进 Keychain；**之后 DSH 重启、重新安装 App 都不用重新扫码**；
- 长期密码只保存在本机（`~/.dsh/dsh-pocket-ios/pin`，权限 600），用于手动登录；
- 设置卡片跟随 DSH 界面语言自动中英文切换。

> 完整使用说明（含四种方式的分步说明、常见问题）：<https://dsh-pocket.docs.notta.uk>

## 安装

```bash
dsh plugin add dsh-pocket-ios
```

安装后**重启 DSH** 并刷新页面（client 模块在启动时加载）。

App：<https://apps.apple.com/app/id6832288744>（DSH Pocket iOS）。

设置页位置：账号与余额 → 通用设置 → 手机访问 → **手机访问（iOS）** → 模型。

## 四种连接方式

### 局域网（同一 Wi-Fi，最快）

无需任何配置。电脑选「局域网」，手机连同一个 Wi-Fi 扫二维码即可。

> 换到别的网络（比如用流量）就连不上，那时改用 Cloudflare。

### Cloudflare（人在外面，手机零安装）

电脑选「Cloudflare」，首次会自动下载约 20MB 的 `cloudflared`（多源 + 分块 + 测速，1~2 秒完成），随后启动 quick tunnel 并给出二维码。

> 地址会在 DSH 重启后变化，需要重新扫码；流量经过公网中继，敏感场景建议用局域网或 Tailscale。

### Tailscale（地址固定，长期稳定）

1. Mac 与 iPhone 安装 Tailscale，登录同一账号；
2. Mac 执行一次：

   ```bash
   tailscale serve --bg 3091
   ```

   （Tailscale 后台 DNS 页需开启 HTTPS Certificates）
3. 电脑选「Tailscale」，手机扫二维码，自动登录。

> 读不到 Tailscale 状态时，可手写配置：
>
> ```bash
> mkdir -p ~/.dsh/dsh-pocket-ios
> echo '{"url":"https://你的机器名.你的tailnet.ts.net"}' > ~/.dsh/dsh-pocket-ios/tailscale.json
> ```

### EasyTier（自主组网，装成系统服务）

适合不愿意依赖 Cloudflare / Tailscale 的技术用户。**电脑端会装成一个 launchd 系统服务**（开机自启 + 崩溃自动重启 + 后台常驻），不是手动跑的一次性进程。

1. 安装 EasyTier（macOS 没有 Homebrew formula，从 [GitHub Releases](https://github.com/EasyTier/EasyTier/releases) 下 zip，解压后把 `easytier-core` / `easytier-cli` 放进 `~/.local/bin`）；
2. 电脑选「EasyTier」，面板会给出**一条命令**（heredoc 写 plist + `launchctl bootstrap`），复制到终端执行一次，输密码即可；
3. 手机在 Shadowrocket 里加载面板给出的订阅地址：

   ```
   http://<内网IP>:3091/dsh-pocket-ios/easytier.conf
   ```

   **全局路由必须选「配置」，不能选「代理」**——选「代理」会全局劫持，把 Apple 的证书验证请求也代理走，App 会报「无法验证」。
4. 之后扫面板二维码即自动连接，无需密码。

> 卸载服务：面板就绪态会给出 `uninstallCommand`（`launchctl bootout` + 删 plist）。

## CLI（服务器场景）

DSH 装在**没有图形界面的服务器**上时，没有「手机访问（iOS）」页面可以看二维码。用 CLI 在终端里操作：

```bash
npx dsh-pocket-ios pair                  # 打印一次性配对二维码（10 分钟有效）
npx dsh-pocket-ios pair --png ~/q.png    # 存成 PNG，发到手机再扫
npx dsh-pocket-ios pair --url            # 只输出地址，便于脚本使用
npx dsh-pocket-ios status                # 当前连接方式 / 地址 / 是否就绪
npx dsh-pocket-ios mode tailscale        # 切换：lan | cloudflare | tailscale | easytier
npx dsh-pocket-ios doctor                # 诊断：端口可达性、依赖是否装好
```

**认证方式**：`cli.*` 端点免 cookie，但**只接受来自 `127.0.0.1` / `::1` 的请求**——只有本机能调，公网进不来。所以 CLI 必须和 DSH 跑在同一台机器上。

**云服务器上推荐 Tailscale**：不开任何公网端口。

```bash
# 服务器
curl -fsSL https://tailscale.com/install.sh | sh   # 国内不稳时改用 pkgs.tailscale.com 的 yum/dnf 源
systemctl enable --now tailscaled
tailscale up --hostname=dsh-server
tailscale serve --bg 3091

# 之后
npx dsh-pocket-ios mode tailscale
npx dsh-pocket-ios pair
```

**有域名**的话，也可以用 Nginx/Caddy 反代到 `127.0.0.1:3091`，得到固定 HTTPS 地址、手机零安装。

## 端口

- 稳定入口默认 **3091**，监听 `0.0.0.0`（局域网/虚拟网络需要）；
- Tailscale Serve 指向 3091：`tailscale serve --bg 3091`；
- 改端口：`DSH_POCKET_IOS_PROXY_PORT=<port> dsh start`，并同步 `tailscale serve`；
- EasyTier 的 SOCKS5 默认 **1080**，WireGuard 门户默认 **11500**（避开 EasyTier 自用的 11010–11013）。

## 端点

| 路径 | 说明 |
| --- | --- |
| `/dsh-pocket-ios/pair` | 一次性配对：校验 token → 302 → 种 `dsh-auth` + `dsh-pocket-device` |
| `/dsh-pocket-ios/login` | 用访问密码换 cookie |
| `/dsh-pocket-ios/refresh` | 用 `dsh-pocket-device` 换新 cookie（免扫码重连） |
| `/dsh-pocket-ios/easytier.conf` | Shadowrocket 订阅配置（纯文本，免认证） |
| `/dsh-pocket-ios/cli.pair` | CLI 出配对码（免 cookie，**仅限 127.0.0.1**） |
| `/dsh-pocket-ios/cli.status` | CLI 查状态（同上） |
| `/dsh-pocket-ios/cli.mode` | CLI 切连接方式（同上） |
| `/dsh-pocket-ios/tailscale.status` / `mode.set` / `mode.status` | 设置页 RPC |

## 安全

- 密码/token 不写入日志、不进入构建产物、不进入 Git；
- 二维码只含一次性配对 token，不含长期密码；
- 配对登录通过 DSH 自带 `connection.authenticatedUrl` 换 `dsh-auth` cookie，不另造会话体系；
- 配对 token 只存内存，5 分钟过期；
- `easytier.conf` 卡片不含任何凭证（只有内网 IP + 端口 + 虚拟网段）。

## 开发

```bash
npm install
node --check lib/index.js && node --check client/client.js
node --test test/          # 全部单测
npm pack --dry-run
```

## License

GPL-2.0，见 [LICENSE](LICENSE)。
