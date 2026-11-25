# 12 · 连接方式的可靠性修复与回归防线

- 日期：2026-11-25
- 状态：已完成（本地验证通过，npm 待用户验证后发布）
- 预估：180 分钟

## 背景

一天内连续暴露五类问题，全部发生在「切换连接方式 → 出二维码」这条链路上：

1. **端口回落但 serve 没跟着改**：插件从 3091 落到 3093，`tailscale serve` 仍指向 3092，
   二维码地址连不上，App 报「二维码已过期」。
2. **Cloudflare 地址被局域网冒充**：CF 隧道未就绪时静默回退局域网 IP，
   用户选了 Cloudflare 却扫到局域网地址，以为「CF 没加上」。
3. **首次扫 CF 码必失败一次**：quick 隧道建成后要几秒才对外生效。
4. **`pair.create` 阻塞导致 RPC 超时**：等待 + 探测叠加超过 DSH 的 RPC 超时，
   面板显示 `connection: invalid server-response failure`。
5. **面板白屏**：`addressForMode` 在 `pairBaseRef` 声明之前读取它（`var` 提升为
   `undefined`），抛 TypeError 整个面板挂掉。

以及一条**流程问题**：`resolvePairBase` 用了却忘记 `import`——语法检查与单测全绿，
只有真跑起来才 ReferenceError。同类问题还有「`$VAR` 紧跟中文标点」一天踩三次。

## 目标

- 上述五类问题全部修好，且**每一类都有自动化检查**，不再靠手测。
- 把检查固化成一条命令 `./scripts/preflight.sh`，提交前必跑。

## 方案

### 修复

| 文件 | 改动 |
| --- | --- |
| `lib/serve-status.js`（新） | `parseServeStatus` / `needsRepoint`：serve 端口与插件端口不一致时重新 `--bg` |
| `lib/reachability.js`（新） | `probe`：出码前探测 CF 地址是否已生效 |
| `lib/pair-base.js`（新） | `resolvePairBase` / `decideAfterProbe`：把「该用哪个地址」从 `index.js` 抽成纯函数 |
| `lib/index.js` | serve 端口校验；CF 不等不阻塞、回 `{ retry: true }`；启动对齐 serve；切走 CF 留 10 分钟宽限期；CF 启动文案区分「下载」与「启动」 |
| `client/client.js` | ref 声明提前（修白屏）；地址显示以二维码地址兜底；切模式先清旧码；`data.retry` 自动重试；切完 700ms 密集刷新 |

### 回归防线

| 新增 | 作用 |
| --- | --- |
| `test/import-wiring.test.js` | **local 模块的导出被使用却没 import** → 直接失败（本次事故的根因） |
| `test/panel-wiring.test.js` | 面板结构断言：ref 先用后声明、地址兜底来源、切模式清码、retry 分支 |
| `test/pair-base.test.js` | 出码地址决策（CF 绝不回退局域网等 7 条） |
| `test/reachability.test.js` | 可达性判定（200/401/403 算可达） |
| `test/serve-status.test.js` | serve 端口解析与是否需要重新指向 |
| `scripts/check-shell-vars.py` | `$VAR` 紧跟中文/全角标点（bash 会误读变量名） |
| `scripts/check-serve-port.sh` | 线上检查：插件端口 vs serve 端口 vs 地址可达性 |
| `scripts/preflight.sh` | 一条命令跑完：shell 语法 + 变量检查 + 插件单测 + iOS 单测 + 架构检查（`--live` 额外查真实端口） |

## 影响面

- 仅插件（`plugin/`）与仓库脚本；App 代码未改，无需重新上架。
- Cloudflare 隧道改为「切走后 10 分钟才停」，期间会保留一个 cloudflared 进程。

## 测试计划

- 单元/静态：`plugin/npm test`（115 条，含上述新增）
- 集成：`./scripts/preflight.sh`（6 项全绿）
- 线上：`./scripts/check-serve-port.sh`（本次实测抓到真实端口不一致，已修）
- 手动：切换 lan/tailscale/cloudflare，确认二维码地址形态与状态地址一致

## 已知限制

面板的完整 UI 端到端（点按钮→读二维码）**无法自动跑**：面板 RPC 走 DSH 内部会话鉴权，
脚本拿不到 cookie。因此改用「纯函数单测 + 面板源码静态断言」覆盖，UI 仍需手测。

## 回滚

`git revert` 对应提交即可；无数据迁移。npm 上的 0.8.2/0.8.3 未经用户验证，按用户要求暂停发布。
