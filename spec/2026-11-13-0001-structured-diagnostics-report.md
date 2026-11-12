# 诊断信息改为结构化英文报告

> **Status**: In Review
> **起始日期**：2026-11-13
> **预估工时**：70 分钟（单元累加）
> **对应提交**：（完成后回填）
> **文件名**：`spec/2026-11-13-0001-structured-diagnostics-report.md`

## 背景 / 问题

用户两点反馈：

**① 切换语言后「复制诊断信息」仍是中文。**
诊断文本全部硬编码中文，没有走 `L10n`。

**② 不够正式专业。**
现在的实现是「中文标签 + 大段口语解释」：

```
会话: 做一个 iOS 版 DSH
含义: 手机上这次加载进来的消息条数，不是电脑上的全部历史。待发是还没被服务端确认的本地气泡。
App 内存: 48.2 MB
含义: phys_footprint，整个进程现在有多重... iOS 杀后台看的就是这个数。文字通常只有几十 KB；涨到几百 MB 时先看图片缓存和会话页是否还活着。
```

问题：
- 无固定分区，标签与解释混行，扫读困难
- 口语化（「不要先怪网络」「不是这段对话的文本大小」）
- 硬编码中文，跨语言排查时对方看不懂
- 无头部元信息（App 版本 / 设备 / 系统 / 生成时间都没有）

## 目标与非目标

**目标**
- 报告**全英文**（诊断日志的行业惯例，跨语言排查不需要翻译）。
- 结构对齐 Apple 系统诊断报告（sysdiagnose / crash report）：
  头部元信息 → 分区 → 键值对齐 → 最近事件。
- 去掉口语解释，只保留**确实容易被误读**的字段说明，且收敛到每组末尾一行。
- 复制出来的文本在等宽字体下对齐。

**非目标**
- 不改诊断**采集**逻辑（采样、进出记录、内存拆解的计算都不动）。
- 不改 `diagnostics.log` 文件格式（App 内部日志仍是中文，因为它只给开发看）。
- 不引入新的诊断指标。

## 参考实现（Prior art）

- **Apple 崩溃报告格式**：`Process / Path / Identifier / Version / Code Type / Parent Process` 头部，
  然后 `Exception Type / Termination Reason / Threads / Binary Images` 分区。
  特点：**键左对齐、值对齐、无解释性文字**，扫一眼就能找到要找的字段。
  → **采用**：头部元信息 + 分区 + 对齐。
- **`sysdiagnose`**：分组标题用 `==` 或 `---` 分隔，每组内是 `key: value`。
  → **采用**：`[ Section ]` 分区标题。
- **不采用**：JSON 格式。理由：用户要复制粘贴到聊天里给开发者看，JSON 在手机上不可读，
  且 `jq` 之类工具在对话里用不上。

## 方案

### 第 1 步：定义报告结构

```
DSH Pocket Diagnostics
Generated   2026-11-13T00:05:12+08:00
App         1.0.7 (4)
Device      iPhone 17 Pro · iOS 27.3
Locale      zh-Hans

[ Connection ]
State       connected
Server      https://<redacted-host>
Live        connected · last frame 0.4s ago

[ Session ]
Title       做一个 iOS 版 DSH
Session     8b859496-…
Address     https://<redacted-host>/?session=8b859496-…
Messages    30  (user 12 / assistant 18 / pending 0)
Steps       24  (unfinished 0 / error 1 / groups 8)
Timeline    11 rows · failed turns 0
Load        820 ms via follow

[ Storage ]
Message text   42.1 KB
Step results   128.4 KB
Images         12 refs · cache 8 / 3.2 MB
Live views     1

[ Memory ]
Footprint    48.2 MB
Compressed   12.1 MB

[ Outbox ]
Pending 0 · Queued 0 · Failed 0

[ Notes ]
Footprint is phys_footprint for the whole process, not conversation text size.
Step count is not row count — the UI draws one row per step group.
Live views should return to 0 after leaving a conversation.

[ Recent Events ]
00:03:12  follow snapshot 30 msgs
00:03:13  reply arrived seq 412
...
```

**为什么英文**：诊断日志的读者是「排查问题的人」，不一定是说中文的人。
App 内其他文案继续本地化，只有这份报告固定英文——这也是 iOS 生态的通行做法
（日志、崩溃报告、控制台输出基本都是英文）。

### 第 2 步：抽成独立的报告生成器（DSHKit，可测）

现状：`Diagnostics.report()` + `indexBlock()` + `memoryLine()` 三处各自拼字符串，
格式无法统一、也没法测。

改为一个纯函数式的拼装器放 DSHKit：

```swift
public struct DiagnosticsReport {
    public struct Section { public let title: String; public let rows: [(String, String)] }
    public struct Input { ... }   // 全部是值，不含 UI / 文件依赖
    public static func render(_ input: Input) -> String
}
```

**为什么放 DSHKit**：列对齐、字段缺省（比如没打开会话时 Session 段的处理）、
事件截断都是纯逻辑，可穷举测试。App 层没有测试 target，放进去就测不到。

**为什么不直接改 `Diagnostics` 里的三个方法**：它们分别被「复制诊断」「设置页展示」
「菜单」三处调用，各自期望的详略不同；先统一成一份结构化输入，再按需渲染，才不会三处漂移。

### 第 3 步：保留「Notes」组，但收敛

原实现每条都跟一句「含义: …」。改为末尾统一的 `[ Notes ]`，只留 3 条真正容易误读的：
- footprint ≠ 文本大小
- 步骤数 ≠ 行数
- live views 应回到 0

**为什么保留**：这三条是实际排查时最容易看错的地方（我在排查中自己就误读过）。
但**不再逐字段解释**——那会让报告变成教程。

### 第 4 步：App 侧接入

`diagnosticReport()` 组装 `DiagnosticsReport.Input` 并 `render`；
`conversationDiagnosticsBlock()`（菜单里那段）不再单独维护格式，改为调用同一个渲染器、传更少的字段。

## 被否决的方案

| 方案 | 否决理由 | 否决依据 |
| --- | --- | --- |
| 继续用中文，但走 `L10n` 跟随语言 | 跨语言排查时对方看不懂；且中英双语报告要维护两套措辞 | 诊断日志的行业惯例是英文 |
| 改成 JSON | 用户要复制到聊天里看，JSON 在手机上不可读且冗长 | 实际使用场景是粘贴给开发者 |
| 保留逐字段「含义」解释 | 报告变教程，扫读时解释比数据还长 | 用户反馈「不够专业」 |
| 直接把 `Diagnostics` 三个方法各自改成新格式 | 三处调用期望详略不同，改完必然漂移 | 同一份数据三个格式是当前问题的根源 |
| **什么都不做** | 代价：用户切英文后拿到中文诊断；报告越写越长，真正的数字被解释淹没 | 用户明确反馈 |

## 代价与风险

**代价**（确定会付）
- 新增 DSHKit 渲染器（约 120 行）+ 测试（约 60 行）。
- 老的 `indexBlock()` 里的详细解释会被大幅删减——**排查时可读性下降**，
  需要用「知道字段含义」换「扫读速度」。

**风险**（可能发生）
| 风险 | 缓解 |
| --- | --- |
| 删解释后新人看不懂字段 | `[ Notes ]` 保留最容易误读的三条；其余字段名本身自解释 |
| 报告格式变了，历史日志对比困难 | 报告是即时生成的，不存历史，无兼容问题 |
| 等宽对齐在非等宽字体下错位 | 用固定宽度键（≤12 字符）+ 空格填充；用户多半粘贴到聊天/编辑器，等宽场景足够 |

**为什么不该做这件事**（Drawbacks，诚实写反面）
- 诊断报告是**极低频使用**的功能（只在出问题时用）。为一个低频功能写 180 行渲染器 + 测试，
  性价比本身可疑；用现在的中文版也能排查，只是观感差。
- 用户在真机上把中文报告直接贴给我时，我其实读得懂——「不专业」更多是观感问题而非功能问题。

## 未决问题（Unresolved Questions）

- `[ Notes ]` 是否该跟随语言（中文用户看中文注释，其余英文）？本轮先全英文，保持整体一致。
- 是否需要「简洁版 / 详细版」两档？目前只有一档。若以后日志太长影响粘贴，再考虑。
- 报告里是否该带 `report id`（用于对账手机日志）？本轮不加，因为日志本身有完整时间戳。

## 测试计划（先红后绿）

| 用例 | target | 断言 |
| --- | --- | --- |
| 分区与顺序 | `DSHKit` `DiagnosticsReportTests` | 渲染结果含 `[ Connection ]` … `[ Recent Events ]` 且顺序固定 |
| 键值对齐 | 同上 | 每行 `key` 后至少一个空格，值从固定列开始 |
| 未打开会话 | 同上 | Session 段显示 `—` 而不是崩溃或空段 |
| 事件截断 | 同上 | 超过上限时只保留最近 N 条并追加省略标记 |
| 不含中文 | 同上 | 渲染结果里没有 CJK 字符（防止回归到硬编码中文） |
| 回归 | `swift test` | 348 → 约 360 绿 |
| 架构 | `check-architecture.sh` | 违规 0 |

## 预估工时

| 单元 | 数量 | 单耗依据 | 小计 |
| --- | --- | --- | --- |
| spec 定稿 | 1 | 实测约 18 | 18 分钟 |
| DSHKit 渲染器 | 1 | 约 120 行纯逻辑 | 25 分钟 |
| 测试 5 条 | 5 | 约 3/条 | 15 分钟 |
| App 侧接入（三处调用统一） | 3 | 约 4/处 | 12 分钟 |
| 编译 + 测试 + 架构 | 1 | 实测 8 | 8 分钟 |
| 真机确认（切英文后复制） | 1 | 实测 8 | 8 分钟 |
| **合计** | | | **86 分钟** |
