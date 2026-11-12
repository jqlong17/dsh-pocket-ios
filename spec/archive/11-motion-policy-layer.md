# 11 · 修掉纯逻辑层的 UI 依赖（MotionPolicy）


> **Status**: Accepted · 动效策略层已落地并被后续 spec 依赖
## 背景 / 问题

`scripts/check-architecture.sh` 扫出 8 处存量违规，其中一条：

```
[pure-logic-no-ui] DSHKit/Sources/DSHKit/UI/MotionPolicy.swift — 导入了 SwiftUI
```

证据：该文件只有 8 行，全部内容是 `reduceMotion ? nil : animation`，但因为要让 `Animation?` 类型通过签名，
`import SwiftUI` 被带进了纯逻辑层（DSHKit）。

为什么这是问题（不是洁癖）：

1. **可测性**：DSHKit 的测试要在非 UI 环境跑；一旦纯逻辑层依赖 SwiftUI，整个包被绑到 UI 框架上，
   单测被迫在 UI 运行时里执行，覆盖率统计也会把 UI 代码算进来。
2. **规则失效**：「纯逻辑层只依赖 Foundation」是架构规范的硬规则。这条规则一旦开口子，
   下次谁把 `Color`/`Font` 放进策略层也有理由了。
3. **它根本不属于这一层**：这段代码没有任何「判断逻辑」，只是把 UI 类型透传或丢弃——它是 UI 工具，
   应该待在 App 层。

## 目标与非目标

**目标**
1. DSHKit 源码树中不再出现 `import SwiftUI / UIKit / AppKit`。
2. 这条规则变成**单元测试**（architecture test），随 `swift test` 永远生效，而不只是靠脚本。
3. 动画门闸行为不变：减少动态时返回 nil，否则原样返回。

**非目标**
- 不动 `PocketMotion.quick` / `.standard` 的数值。
- 不重构其它 7 处违规（文件超长、extension 堆叠）——本 spec 只处理一条。
- 不改任何视图的动画调用方式。

## 参考实现

| 参考 | 取什么 |
| --- | --- |
| 本仓 `DSHPocket/Support/PocketMotion.swift` | 它已经是 UI 层的动画出口，把门闸内联进来即可，不新增类型 |
| 架构测试的通用做法（如 TCA、SwiftLint 的 `no_ui_import` 自定义规则） | 用「扫源码文件断言 import」的方式把架构规则变成可执行测试 |
| `scripts/check-architecture.sh`（本仓） | 规则名与判定口径保持一致（`pure-logic-no-ui`），避免两套标准 |

采用「单测 + 脚本」双保险：单测保证 `swift test` 层面一定拦截；脚本保证连非测试环境（CI 前置）也能查。

## 方案

1. **新增 architecture test**：`DSHKit/Tests/DSHKitTests/ArchitectureBoundaryTests.swift`
   - 扫描 `Sources/` 下全部 `.swift`，断言没有 `import SwiftUI/UIKit/AppKit`。
   - 失败信息指出违纪文件，便于定位。
2. **搬移门闸**：把 `MotionPolicy.animation(_:reduceMotion:)` 的逻辑内联进 `PocketMotion.animation(_:)`，
   删除 `DSHKit/Sources/DSHKit/UI/MotionPolicy.swift`。
3. **迁移测试**：`MotionPolicyTests` 依赖 SwiftUI 与 DSHKit 策略，App 层无单测 target，
   因此删除该测试文件；等效断言由 `PocketMotion` 的行为 + architecture test 覆盖（`PocketMotion` 逻辑只有一行三元表达式）。
4. 重新生成 `docs/architecture/fact.json`，确认 `pure-logic-no-ui` 违规为 0；`journey.jsonl` 追加一条决策。

## 测试计划（先红后绿）

| 测试 | target / 目录 | 断言 |
| --- | --- | --- |
| `ArchitectureBoundaryTests.testPureLogicLayerHasNoUIImports` | `DSHKit/Tests/DSHKitTests/` | `Sources/**/*.swift` 中无 `import SwiftUI/UIKit/AppKit` |
| `ArchitectureBoundaryTests.testScanFindsAndReportsViolations`（自测） | 同上 | 用一段伪造源码验证扫描器能抓到违规，避免「测试永远绿其实没扫」 |
| 回归 | `swift test` 全量 | 254 → 254（删 3 条 MotionPolicy 用例、加 2 条架构用例，净 -1） |

**红**：先写 architecture test，此时 `MotionPolicy.swift` 存在 → 断言失败。
**绿**：删掉该文件后通过。

量化标准：`check-architecture.sh` 的 `pure-logic-no-ui` 从 1 处降为 **0 处**；总违规 8 → 7；`swift test` 全绿；App 编译通过。

## 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| 删 `MotionPolicy` 后漏改调用点 | 先全仓 grep（只有 `PocketMotion` 一处）；编译验证 |
| 架构测试扫错路径（相对路径依赖工作目录） | 用 `#filePath` 推导 Sources 路径，并在自测里验证扫描确实命中文件 |
| 误删 `MotionPolicyTests` 丢失覆盖 | 该测试只断言三元表达式，且真正约束已由架构测试覆盖；在提交信息里写明 |

回滚：单次提交，`git revert` 即可恢复 `MotionPolicy.swift` 与原测试。

## 预估工时

预估 **30–45 分钟**（含写测试、搬移、全量测试、重新生成 fact.json、记录检查点）。

## 执行记录

提交 `f07b495`；检查点 baseline `b2323ae` / result `f07b495`。

- 交付：`ArchitectureBoundaryTests`（2 条：边界扫描 + 扫描器自测）、删除 `MotionPolicy.swift` 与 3 条 UI 测试、门闸内联 `PocketMotion`。
- 验证：`swift test` 254 → **253 绿**；`xcodebuild` 成功；`check-architecture.sh` 违规 **8 → 7**，`pure-logic-no-ui` 归零。
- 预估 40 分钟，实际 ≈1 分钟（偏差 0.02×）——又一次系统性高估，已计入 `estimate-accuracy` 样本。

### 回看量化标准

| 标准 | 结果 |
| --- | --- |
| 纯逻辑层无 UI import | ✅ 由测试强制 |
| 规则变成单测 | ✅ `swift test` 默认执行 |
| 违规 8 → 7 | ✅ |
| 行为不变 | ✅ 编译通过、253 测试绿 |

### 未做

其余 7 处存量违规（6 个超 400 行文件、ConnectionModel 7 个 extension）未动——按 spec 只修一条，不夹带。
