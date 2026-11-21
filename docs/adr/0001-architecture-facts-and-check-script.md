# ADR-0001: 架构事实由脚本生成，检查脚本卡红线

Date: 2026-11-12
Status: implemented

## Context

架构规范写了阈值（400/600 行）和反模式，但**代码没有机器校验**。结果是：
`ConnectionModel` 堆到 7 个 extension、6 个文件超 400 行、纯逻辑层 `import SwiftUI`
——这些长期无人发现。

## Decision

三个东西分工：

| 文件 | 谁维护 | 内容 |
| --- | --- | --- |
| `docs/architecture/fact.json` | **脚本生成，禁止手写** | 模块 / 依赖 / 违规 |
| `docs/architecture/journey.jsonl` | 只追加 | 决策注册表（`id` 指向 ADR） |
| `scripts/check-architecture.sh` | 人工维护规则 | 卡红线，**退出码 1** |

`./scripts/architecture-facts.sh` 扫代码 → `fact.json`；`check-architecture.sh` 按它判违规。

## Alternatives

| 备选 | 否决原因 |
| --- | --- |
| 继续靠人工 review | 已经证明会漏（7 个 extension 就是漏出来的） |
| 把规则写成文档定期自查 | 没有退出码的检查会被忽略 |

## Consequences

**收益**：违规从 8 处降到 **0 处**；新增违规当次修掉（CI 可化）。

**代价**：
- `fact.json` 不能手改，人工补充要写进 `journey.jsonl`
- 阈值本身会误伤——见 `docs/adr/0005`

Update (2026-11-12): 架构硬规则同时写成单测，不只靠扫描脚本。
