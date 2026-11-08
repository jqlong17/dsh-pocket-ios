# DSH Pocket iOS 重构 Spec（TDD 版）

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
| 02 Sync | ✅ 已验收（包内，tag `module-02-accepted`；App 接入在 02b） | 18 条全绿 | **91.6%**（整体） |
| 03 消息生命周期 | ⏳ 待开始 | — | — |
| 04 Conversation UI | ⏳ 待开始 | — | — |
| 05 E2E | ⏳ 待开始 | — | — |

> 模块 01/02 目前范围是独立 SPM 包（`DSHKit/`）：包内已可单测验收；
> **App 接入（替换 `ConnectionModel` 内联 RPC/同步逻辑）在 02b 完成**，避免同一 PR 同时动协议与 UI。
> 接入后需要跑模块 05 的 E2E 回归，再打 `module-02b-integrated` 标签。

## 测试分层

| 层 | 位置 | 覆盖 |
| --- | --- | --- |
| 单元测试 | `DSHKit/Tests/`、`DSHPocketTests/` | 协议编解码、状态机、排序、对账、分页、ViewModel |
| 集成测试 | `DSHKit/Tests/Integration/` | 用 MockTransport 跑 sync coordinator 全流程 |
| 端到端测试 | `DSHPocketUITests/`（XCUITest）+ Demo 模式 | 登录/演示/收发/切换/断线重连 |
