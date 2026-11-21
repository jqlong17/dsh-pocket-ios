# ADR-0002: ConnectionModel 拆成状态对象，RPC 逻辑下沉 DSHKit

Date: 2026-11-12
Status: implemented

## Context

`ConnectionModel` 单个类承担了四件事：状态容器、网络编排、业务判定、UI 反馈。
后果有两个同时出现：

1. **不可测**：业务判定（Outbox 状态转移、分页边界、失败分类）在 App target，
   而 App target 没有 unit test target
2. **无限膨胀**：被约 **140 处**引用，改一处要预期连锁反应

## Decision

分三批推进，每批一次提交、全绿再下一批：

| 批次 | 内容 |
| --- | --- |
| 1 | **RPC 收口**：超时/重试逻辑下沉到 DSHKit |
| 2 | **状态对象抽出**：拆成 5 个独立状态对象 |
| 3 | **视图收敛**：视图只依赖所属场景的状态 |

判据尽量接到脚本（违规数 / 测试数 / 字面量计数），不靠感觉。

## Alternatives

| 备选 | 否决原因 |
| --- | --- |
| 一次性重写 | 140 处引用，风险不可控 |
| 只拆不搬（拆成更多 extension） | 那是**假拆分**——行数在文件间转移，耦合没变 |

## Consequences

**收益**：`ConnectionModel.swift` 从 604 行降到核心文件规模；RPC 逻辑进了可测层。

**遗留（诚实记录）**：`DSHPocket/Session/` 仍有 **6525 行**，其中 **2101 行本该可测**
但因为落在 App target 而测不了。**这笔债没还完。**

Update (2026-11-16): 量化了遗留规模——30 文件 / 6525 行 / 2101 行本可测。
下一步见 `docs/adr/0010`。
