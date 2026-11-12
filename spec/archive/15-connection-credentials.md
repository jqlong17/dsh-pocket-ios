# 15 · 连接凭证：重装与重启都不再重新扫码


> **Status**: Accepted · 真机实测：卸载重装后自动连上
## 背景 / 问题

用户实测反馈两件事：

1. **每次 build 安装 App 都要重新扫码**。原因：电脑地址存 `UserDefaults`、登录 cookie 存 `HTTPCookieStorage`，都在沙盒里，覆盖安装即清空（调试期尤其频繁）。
2. **DSH 电脑端完全退出重开后，手机提示「请重新扫码配对或输入访问密码」**。原因：`dsh-auth` cookie 是 **session 级**的，DSH 进程重启即失效；插件原本只发 60 秒有效、用后作废的一次性配对 token，没有任何可复用的长期凭证。

产品期望（用户原话）：**一旦建立连接，除非用户主动删除，否则应该一直保留**。

## 目标与非目标

**目标**
- App 覆盖安装后自动恢复连接，不重新扫码。
- DSH / Tailscale 重启后自动恢复连接，不重新扫码。
- 凭证明文不落 `UserDefaults`；跨重装能存续。
- 用户删除这台电脑时，凭证彻底清除。

**非目标**
- 不改变 PIN 登录流程本身。
- 不做多设备管理界面（只提供 `device.list` / `device.revoke` 接口层）。
- 不改 cookie 的服务端有效期语义（由 DSH browser-auth 决定）。

## 参考实现

- iOS Keychain 的跨安装存续特性（App 删除后 Keychain 项仍保留，除非设备重置），Apple 文档 *Keychain Services*。
- OAuth 2.0 的 refresh token 模式：短命 access token + 长命 refresh token，客户端用后者静默换前者。这里把 DSH 的 `dsh-auth` cookie 当 access token，插件签发的设备凭证当 refresh token。

## 方案

**插件侧**（`plugin/lib/index.js`，"服务端"就是这个仓库的插件）

- 配对成功时签发设备凭证：43 字符随机串，存 `~/.dsh/dsh-pocket-ios/devices.json`（权限 `0600`），内容是 `{ name, createdAt, lastUsedAt }`。
- 以 `Set-Cookie: dsh-pocket-device=…; Max-Age=31536000; HttpOnly` 下发——**保持 302 流程不变**，旧版 App 不受影响。
- 新增 `POST /dsh-pocket-ios/refresh`：校验设备凭证 → `authenticatedUrl` → 302（种新 cookie）。该端点加入免浏览器会话白名单（与 `login`/`pair` 同级，它自带凭证校验）。
- 新增 `device.list` / `device.revoke` 供设置页查看与撤销。

**App 侧**

- `ConnectionVault`（Keychain，`kSecAttrAccessibleAfterFirstUnlock`）保存三样：电脑地址、`dsh-auth` cookie、`dsh-pocket-device`。
- 启动时地址优先 `UserDefaults`、兜底 Keychain；`restoreConnection` 把 cookie 放回 `HTTPCookieStorage` 再连接。
- 401 时先静默换票：`tryRefreshAuth()` → 清旧 `dsh-auth` cookie → 带 `{}` body 与 `x-dsh-pocket-device` 头 POST `refresh` → 跟随 302 → 确认拿到**新** cookie 才 `connect()`；失败才走 `finishAuthExpired` 提示重新配对。
- `authRefreshAttempted` 防 401 循环。

## 测试计划（先红后绿）

| 用例 | target | 断言 |
| --- | --- | --- |
| 传输错误保留类型 | DSHKit `TransientNetworkTests` | `URLError` 原样抛出，`isTransient == true` |
| 设备凭证格式 | 插件 `node` 自测 | 43 字符、无非法字符、存盘可读回 |
| 刷新端点契约 | 手动 `curl` | 带 body + 正确头 → 302；错误凭证 → 401 |
| 真机端到端 | 手工 | 重启 DSH 后 App 自动连上，日志出现「设备凭证换票成功」且**无**「配对登录」 |

## 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| 设备凭证泄露 | 只存本机 `0600` 文件与手机 Keychain；可 `device.revoke` 撤销；删除电脑时连带清除 |
| 换票假成功 | 判定必须是「拿到新 cookie」，不能只看 storage 里存在（踩过，见反例 018） |
| 插件改动导致 DSH 起不来 | 改动前 `node --check` + 在 `node_modules` 目录实测 `import()` 可加载 |
| 旧版 App 不兼容 | 设备凭证走 `Set-Cookie`，302 流程不变 |

回滚：还原 `plugin/lib/index.js`（备份在 `/tmp/plugin-index-backup-*.js`），App 侧保留兼容（读不到设备凭证时走原配对流程）。

## 预估工时

插件 60 分钟、App 60 分钟、真机联调 60 分钟。合计 **3 小时**。
实际约 2.5 小时，但**中间三轮修复才收敛**（401 判定失效 → refresh 被会话校验拦 → 请求缺 body + 假成功判定），根因是前两轮修的是症状、第三轮才定位到「缓存里有凭证 ≠ 换到了新凭证」。

---

## 修复记录：配对分支漏存地址（2026-11-12，`25fd289`）

**现象**：用户重装 App 后又要求扫码，而设备凭证明明还在 Keychain 里。

**根因**：凭证落盘分散在两条成功路径，扫码配对分支只存了 cookie 与设备凭证，
**没存地址**——UserDefaults 和 Keychain 都没写。

```
扫码配对成功 → saveAuthCookies + saveDeviceToken，return    ← 缺 saveAddress
密码登录成功 → saveAddress + saveAuthCookies                ← 齐全
```

重装后 `restoreConnection` 判断 `hasAddress == false`，直接回连接页。
设备凭证救不了——**因为不知道连哪台电脑**。

**修法**（不是补一行，而是收口职责）：新增 `persistConnectedState()`，
地址（UserDefaults + Keychain）、cookie、设备凭证三样一起写，两条成功路径都只调它。
理由：三者缺一都会导致「重装后又要求扫码」，分散写就一定会再漏。

**验证**（卸载 + 重装，真正清空沙盒）：

```
14:51:38  网络恢复（路径监听）
14:51:39  会话列表刷新：47 个
```

无「开始连接」、无「配对登录」、无「换票」——Keychain 地址恢复 + cookie 放回后直接有效，
走的是最快路径。

**教训**：凭证这类「缺一不可」的一组数据，必须只有一个写入口。
审核清单应包含：「新增/修改凭证时，确认所有成功路径都走同一个落盘方法」。
