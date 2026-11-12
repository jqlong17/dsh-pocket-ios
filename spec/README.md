# DSH Pocket iOS 重构 Spec

> **新写 spec 先看 [`00-TEMPLATE.md`](00-TEMPLATE.md)**——模板骨架取自
> [rust-lang/rfcs 的 0000-template.md](https://github.com/rust-lang/rfcs/blob/master/0000-template.md)（约 6 万 star），
> 并补了三段外部模板没有的：测试计划（标 target）、预估工时（+校准）、验收记录。
>
> **定位**：我们的 spec 是**执行契约（pitch）**，不是 20 页的设计讨论文档。
> 判据是有时间预算、有方案、有验收标准，接受即执行；不要求「评审意见征集」。

## 每份 spec 的开头必须有 Status

```
> Status: Draft | In Review | Accepted | Superseded
```

没有它，18 份 spec 里哪些还活着只能靠记忆。四态含义：

| Status | 含义 |
| --- | --- |
| Draft | 还在写，可能有 Open Questions |
| In Review | 写完待确认，动代码前必须是这个或 Accepted |
| Accepted | 已确认、正在或已经实现 |
| Superseded | 被新 spec 取代，保留不动（历史记录，不回改） |

## 07 之前的历史 spec

`01`–`10` 写在模板定稿之前，多数只有 2–3 段（缺目标/测试计划/预估工时）。
**处理方式**：标记为 `Superseded (historical)`，不补写。
理由：spec 的价值在执行期，事后补写等于编造决策过程；它们对应的代码已迭代数轮，
补写出来的「当初为什么这样做」是假的。

---

# 原 TDD 版说明

本目录是架构重构的规格文档，按**可独立优化的模块**顺序编号。开发规则：**先测试、后实现**；
每个模块独立验收；最终跑端到端测试并统计覆盖率（**≥85%** 才允许验收）。

## 模块列表

| 编号 | 模块 | 目标 | 依赖 |
| --- | --- | --- | --- |
| [01](01-dshkit-transport-protocol.md) | DSHKit / Transport + Protocol | 抽出可单测的协议客户端（RPC、WS、解码） | — ✅ 已验收 |
| [02](02-sync-coordinator.md) | Sync Coordinator | 单一同步真相源：snapshot/事件/轮询/重连/分页 | 01 ✅ 已验收（包内） |
| [03](03-message-lifecycle.md) | 消息生命周期 | 状态机、rpcId 对账、发件箱、排序、steer | 01,02 |
| [04](04-conversation-ui.md) | Conversation UI / ViewModel | 滚动、发送、键盘、复制、附件、渲染 | 03 |
| [05](05-e2e-and-coverage.md) | 端到端测试 + 覆盖率 | 全链路场景、覆盖率门槛、验收流程 | 01–04 |

## TDD 工作流（每个模块必须遵守）

1. **写测试**：按 spec 的用例表，把测试全部写完（此时应全部失败 = Red）；
2. **最小实现**：让测试逐个通过（Green）；
3. **重构**：清理代码，保持测试绿；
4. **覆盖率**：模块代码行覆盖率 **≥85%**，否则补测试或补实现；
5. **验收**：单元测试 + 回归端到端测试全部通过 + 覆盖率达标 + 更新本文档状态。

## 测试环境与命令

```bash
# 单元测试（本地包）
cd DSHKit && swift test --enable-code-coverage

# iOS App 测试（模拟器）
xcodebuild test -project DSHPocket.xcodeproj -scheme DSHPocket \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -enableCodeCoverage YES -resultBundlePath build/TestResults.xcresult

# 覆盖率报告（模块门槛 85%）
xcrun xccov view --report --json build/TestResults.xcresult > build/coverage.json
./scripts/coverage-gate.sh build/coverage.json 85 DSHKit
```

## 验收门槛（Definition of Done）

- [ ] spec 中该模块的全部用例已存在且通过；
- [ ] 模块行覆盖率 ≥ **85%**（`coverage-gate.sh` 通过）；
- [ ] 回归端到端测试全绿（`05` 的 E2E 套件）；
- [ ] 旧功能无回归（演示模式、登录、收发、复制、图片、iPad）；
- [ ] 代码路径与 spec「预计改动」一致，偏差已更新 spec；
- [ ] 对应 commit + tag（`module-<编号>-accepted`）。

## 进度

| 模块 | 状态 | 测试 | 行覆盖率 |
| --- | --- | --- | --- |
| 01 DSHKit | ✅ 已验收（tag `module-01-accepted`） | 49 条全绿 | **91.6%**（`DSHKit/scripts/coverage.sh`） |
| 02 Sync | ✅ 已验收（包内，tag `module-02-accepted`；App 接入在 02b） | 18 条全绿 | 整体 **92.7%** |
| 03 消息生命周期 | ✅ 已验收（包内，tag `module-03-accepted`） | 25 条全绿 | Store 各文件 92–100% |
| 04 Conversation UI | ✅ 已验收（包内纯逻辑，tag `module-04-accepted`） | 13 条全绿 | UI 93.7% |
| 05 E2E | ✅ 已验收（包内 Mock 集成 + Demo/真实会话 XCUITest，tag `module-05-accepted`） | 9 + 3 条全绿 | 覆盖 92.7% |
| 05 E2E | ⏳ 待开始 | — | — |

> 模块 01/02 目前范围是独立 SPM 包（`DSHKit/`）：包内已可单测验收；
> **App 接入（替换 `ConnectionModel` 内联 RPC/同步逻辑）在 02b 完成**，避免同一 PR 同时动协议与 UI。
> 接入后需要跑模块 05 的 E2E 回归，再打 `module-02b-integrated` 标签。

## 包内总结（2026-11-09）

- `DSHKit` 共 **115 条测试全绿**，行覆盖率 **92.73%**（门槛 85%）；
- 模块 01–05 的包内验收标签：`module-01-accepted` … `module-05-accepted`；
- 剩余工作（未验收）：
  - **02b**：✅ 已完成——App 的实时同步已切换到 `SessionSyncCoordinator`（URL 层此前已接 `DSHURL`），
    模拟器局域网真实会话冒烟通过（已连接/消息加载/生成中状态）；待真机回归；
  - 04 的 SwiftUI 视图拆分与快照测试（包内只覆盖纯逻辑）；
  - 05 的 XCUITest（Demo UI 流程，需新增 iOS UI Test target）。

## 测试分层

| 层 | 位置 | 覆盖 |
| --- | --- | --- |
| 单元测试 | `DSHKit/Tests/`、`DSHPocketTests/` | 协议编解码、状态机、排序、对账、分页、ViewModel |
| 集成测试 | `DSHKit/Tests/Integration/` | 用 MockTransport 跑 sync coordinator 全流程 |
| 端到端测试 | `DSHPocketUITests/`（XCUITest）+ Demo 模式 | 登录/演示/收发/切换/断线重连 |

- [06 · 后台完成推送（APNs）](06-apns-background-notifications.md) — 设计稿
