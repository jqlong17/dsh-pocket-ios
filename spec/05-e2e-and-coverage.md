# 05 · 端到端测试 + 覆盖率 + 验收

## 目标

用可重复的 E2E 套件守住整体行为；所有模块完成后统一计算覆盖率并执行验收。

## 测试环境

- **MockTransport E2E**：进程内假 DSH 服务（WS + HTTP），无需真机/电脑；
- **Demo 模式 UI 测试**：XCUITest 走演示数据（App Store 审核同路径）；
- **真机冒烟**（可选，手动）：局域网连接本机 DSH。

## 用例

### E2E（Mock 服务）
| ID | Given | When | Then |
| --- | --- | --- | --- |
| E01 | 正确 PIN | 登录 | 进入会话列表 |
| E02 | 错误 PIN | 登录 | 提示密码错误 |
| E03 | 列表含归档/子会话 | 登录 | 只显示可见会话 |
| E04 | 打开会话 | snapshot+events | 消息/过程按序出现，停在最新 |
| E05 | 发送消息（空闲） | 发送 | pending→确认→正式消息 |
| E06 | 生成中发送 | 发送 | steer 生效，出现"已引导" |
| E07 | 发送失败 | Mock 断网 | 显示失败，可重发成功 |
| E08 | 长会话向上翻 | 滚动+loadOlder | 历史加载且不跳底 |
| E09 | 切换 A→B→A | 操作 | 无串台，状态各自恢复 |
| E10 | WS 静默断 | 25s 无帧 | 自动重连并补齐消息 |
| E11 | 公网帧过大 | snapshot 被拒 | HTTP 轮询兜底仍出数据 |
| E12 | App 重启 | 重开 | 未确认消息恢复为 pending |

### Demo UI（XCUITest）
| ID | Then |
| --- | --- |
| E20 | 连接页点「体验演示模式」进入列表 |
| E21 | 打开 demo 会话看到消息/表格/图片 |
| E22 | 发送后出现本地回显与示例回复 |
| E23 | 复制整条消息成功 |
| E24 | iPad 上布局居中 |

## 覆盖率

- 命令：`xcodebuild test -enableCodeCoverage YES -resultBundlePath ...` +
  `xcrun xccov view --report --json`；
- 门槛：**每个模块代码行覆盖率 ≥85%**；低于则阻断验收；
- 新增 `scripts/coverage-gate.sh`：解析 JSON，按目标名/路径过滤，阈值可配；
- CI（可选）：`.github/workflows/ci.yml` 跑 `swift test` + `xcodebuild test` + gate。

## 验收流程（每个模块 & 总验收）

1. 测试先写并全红 → 实现 → 全绿；
2. 覆盖率脚本通过（≥85%）；
3. E2E 全绿 + 手动冒烟（登录/收发/复制/图片/iPad）；
4. 更新 `spec/README.md` 状态表；
5. `git tag module-<编号>-accepted`；总验收打 `arch-refactor-accepted`。

## 预计改动

- 新增 `DSHKit/Tests/E2E/{MockDSHServer.swift,E2ETests.swift}`
- 新增 `DSHPocketUITests/DemoFlowUITests.swift`
- 新增 `scripts/coverage-gate.sh`
- 可选 `.github/workflows/ci.yml`

## 最终验收标准

- [ ] E01–E24 全绿；
- [ ] 各模块覆盖率 ≥85%，整体有报告归档；
- [ ] 所有模块 tag 齐全；
- [ ] 线上 1.0.x 不受影响（重构在分支/增量合入）。
