# 13 · 终态架构：一次到位

## 终态（唯一真相）

```
┌───────────────────────────────────────────────┐
│ Views（只依赖自己场景的状态对象）                 │
├───────────────────────────────────────────────┤
│ 5 个 @Observable 状态对象（各自 ≤10 字段）        │
│ Diagnostics · JobRoster · ConnectionState      │
│ OutboxCoordinator · SessionStore                │
├───────────────────────────────────────────────┤
│ DSHKit：唯一协议实现                              │
│ DSHClient（envelope/超时/重试）· DSHErrorKind    │
│ 策略与解析（全部可单测）                          │
└───────────────────────────────────────────────┘
```

**判据（机器可查）**
- `grep -rn "func rpc"` 只命中 DSHKit 一处；
- App 不再出现 `"client-request"` / `"rpcId"` 字面量（不拼 envelope）；
- `check-architecture.sh`：`extension-split-smell` 与 `file-max-400` 归零；
- 每个状态对象字段 ≤10、文件 ≤400 行；
- 视图文件不出现其他场景状态对象的读取。

## 三个交付批次（每批一个提交，全绿再下一批）

| 批次 | 内容 | 交付后判据 |
| --- | --- | --- |
| 1 | **RPC 终态**：`ConnectionModel.rpc` 内部委托 `DSHClient`；`DSHError` 适配回 `ConnectionError`；删除 App 手拼 envelope | App 无 envelope 字面量；21 调用点行为不变；传输错误仍是 `URLError` |
| 2 | **模型拆分**：Diagnostics → JobRoster → ConnectionState → OutboxCoordinator → SessionStore | `ConnectionModel` 降为转发或消亡；每步全绿 |
| 3 | **视图收敛**：视图只依赖所属场景对象 | 跨场景访问为 0 |

## 非目标

- 不改 UI 表现与交互数值。
- 不改持久化格式（发件箱/草稿）。
- 不合并实时流两条路径。

## 风险与回滚

| 风险 | 缓解 |
| --- | --- |
| 一次重构无法定位回归 | 三批次各一次提交，`git revert` 单批即可 |
| 错误类型改动影响 UI 分类 | 批次 1 保留 `ConnectionError` 作为展示适配层，先不改 34 处引用 |
| `@Observable` 跨对象观察失效 | 批次 2 每迁一个对象就编译 + 跑测试；视图持有的引用不换 |

## 预估工时

批次 1：40–60 分钟；批次 2：3–4 小时；批次 3：1–2 小时。合计 **5–7 小时**。
（历史校准：同类任务系统性高估约 0.4–0.8×，实际可能 3–5 小时。）
