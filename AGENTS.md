# DSH Pocket iOS · 协作入口

任何 AI 在这个仓库里改代码之前，先读这两处，再动手。

## 0. 产品定位（先看这个，它决定取舍）

```
核心：iOS 体验
重心：让插件在 iOS 上完美体现
理由：插件是 DSH 的核心
```

**所以不追求「通用客户端的完整功能列表」**。判断一个需求该不该做的第一问是：

> 它让插件在手机上更好用了吗？

插件在手机端分三级（详见 [`public/插件移动端分级.md`](public/插件移动端分级.md)）：

| 级别 | 作者要做的 | 手机上的样子 | 学习成本 |
| --- | --- | --- | --- |
| L0 | 不声明 `dsh.mobile` | 列表可见，无「打开」 | 0 |
| L1 | `kind: "web"` + HTML | WebView 打开 | 会 HTML |
| L1.5 | L1 + 调 JS Bridge | 同上，且能用分享/相册/震动 | 0（还是写 JS） |
| L2a | 声明 volatile config（本来就要写） | 原生配置表单 | **0** |
| L2b | `kind: "native"` + 内容 DSL | 原生渲染内容 | 学一套 JSON |

**L2 拆成 a/b 是关键**：L2a 复用 DSH 已有的 `settings` schema（`remote.settings.describe` /
`mutate`），作者零投入、中等工作量；L2b 才需要自建 UI DSL，是重工程。

**但 L2a 别当第一优先**：连 794 stars 的同类项目 Whaleness 都没做配置表单编辑
（它的 `componentField` 是只读展示），说明需求或成本与直觉不符。**先验证再用工。**

**L0 目前不回退展示桌面端 UI，但这不等于做不到**：桌面插件面板虽无独立 URL，
但 DSH Web 的类名是语义化的、布局靠 CSS 变量、右侧栏状态存在稳定的 localStorage key，
理论上可以注入预设 + 收紧 CSS 勾出来。**待实验验证观感后再定**（细节见分级文档 L0 一节）。

## 1. 写代码的规矩（主流程）

真源：`/Users/ruska/projects/skill/代码编写规范/`

| 文件 | 作用 |
| --- | --- |
| `README.md` | 目录索引与阅读路径 |
| `代码编写执行规范.md` | **主流程**：七条原则、八步流程、提交清单 |
| `版本检查点规范.md` | 大改动前后的 git 检查点、JSONL 记录、脚本 |
| `ios架构设计规范.md` | 分层 / 垂直切片 / 依赖方向 / 阈值 / 反模式 |
| `ios交互设计规范.md` | 界面哲学 / 场景细则 / 可执行数值 |
| `开源项目参考规范.md` | 动手前怎么参考高 star 项目，抄思路不抄代码 |

**最短版**：非豁免改动先写 `spec/NN-*.md`（含预估工时）→ 先写失败测试 → 实现 → 全量测试 → 回看 spec。

**接手旧 spec 先校验格式**：按七段对照，缺段先补（历史 spec 多缺「参考实现」与「预估工时」），测试计划要标 target。

## 2. 本仓库的约定

- **`docs/` 一律不入库**（2026-11-21 用户明确）：里面的调研、宣传素材、审核文案、参考项目源码
  全部只留在本地，`.gitignore` 里是整体忽略 `docs/`。
  **不要再问「要不要把某个 docs 文件提交」**——答案永远是不要。
  README 需要展示的界面图放在 `assets/screenshots/`（不在 docs 下），改图时同步该目录。
- **spec 目录**：`spec/NN-主题.md`（已有 01–10，编号递增）。
- **测试**：`cd DSHKit && swift test`；App 编译走模拟器（真机锁屏常不可达）：
  `xcodebuild build -scheme DSHPocket -destination 'platform=iOS Simulator,id=2BD221E6-CFAA-4E90-8BEB-E7392ACCCB19'`
- **功能验证**：`ios_sim_boot` → `simctl install/launch` → 演示模式走会话列表与对话视图。
- **检查点**：大改动前后各打一次，记录只追加。

  ```bash
  ./scripts/record-checkpoint.sh baseline --spec spec/NN-xxx.md --estimate 90   # 预估分钟
  # ...改代码、跑测试、提交主改动...
  ./scripts/record-checkpoint.sh result --spec spec/NN-xxx.md --tests "swift test NNN 绿"
  ./scripts/verify-checkpoints.sh
  ./scripts/estimate-accuracy.sh   # 预估 vs 实际，输出倍率中位数用于下次校准
  ```

  记录文件 `git-checkpoints.jsonl`，每行的 `commit` 就是那次提交的完整 sha。
  规则：先提交主改动拿到 sha，再写记录；**不要 amend 合并**（会重算 sha 导致记录失效）。

## 3. 架构事实与历程

- `docs/architecture/fact.json`：**脚本生成，禁止手写**。`./scripts/architecture-facts.sh`
- `docs/architecture/journey.jsonl`：架构决策只追加，字段固定。改动分层/抽象时写一条。
- `./scripts/check-architecture.sh`：违规检查，退出码 1。**新增违规当次修掉**，存量按 spec 还债。

当前存量 **0 处违规**。

阈值按层分（`scripts/architecture-facts.sh` 的 `FILE_LIMITS`）：

| 层 | 上限 | 理由 |
| --- | --- | --- |
| pure-logic（DSHKit 策略/解析） | 400 | 纯逻辑、可单测，必须短 |
| app（编排层 `DSHPocket/Session`） | 600 | 编排天然比策略长 |
| ui-tests | 600 | — |

一刀切 400 曾逼出 197 行的碎片 extension，改一个功能要跳四个文件——真正该管的是「一个文件干几件事」。

`extension-split-smell` 的判据是「≥3 个同前缀 extension **且其中仍有超阈值文件**」，
即「拆了但职责没分开」。按职责拆 extension 是正常做法，文件数本身不是问题。

## 3.5 提交时必须包含工程文件

`DSHPocket.xcodeproj` 在仓库根目录，**不在** `DSHPocket/` 里。新增 Swift 文件后：
- 必须在 `project.pbxproj` 注册（fileRef + group + Sources phase），否则 CI/他人拉下来编译失败；
- `git add` 要显式带上 `DSHPocket.xcodeproj`，只写 `git add DSHPocket` 会漏掉它（已踩两次）。

自检：

```bash
# 工作区每个新增 .swift 都应在 pbxproj 里出现
for f in $(git status --porcelain | awk '$1=="??"{print $2}' | grep '\.swift$'); do
  grep -q "$(basename "$f")" DSHPocket.xcodeproj/project.pbxproj || echo "未注册: $f"
done
```

## 3.6 改了 DSHKit 必须全新构建

本地 Swift Package 修改后，**增量构建可能继续链接旧的包产物**——表现是「代码改了、行为没变」，
甚至「修的 bug 还在」（2026-11-12 真机闪退就是这样：源码已修，设备上仍是旧二进制）。

验证或装机时用干净产物：

```bash
rm -rf /tmp/dd-fresh && xcodebuild build -scheme DSHPocket \
  -destination 'platform=iOS,id=<udid>' -derivedDataPath /tmp/dd-fresh ...
```

另外：`Dictionary(uniqueKeysWithValues:)` 遇到重复 key 是 **fatalError**（不是可选失败）。
服务端返回的列表可能重复，一律改用 `Dictionary(_:uniquingKeysWith:)`。

## 3.7 查 DSH 行为：先读源码，不要猜

**DSH 是开源的（MIT）**：<https://github.com/deepseek-ai/deepseek-harness>

它的 `packages/**/README.zh.md` 写得非常细——接口签名、限制、已知问题、
甚至「我们在等客户端做什么」都有。**比读打包产物靠谱得多**。

查证顺序：

1. **GitHub 的 `README.zh.md`**（`raw.githubusercontent.com` + 具体 commit 才拿得到纯文本；
   `github.com/.../blob/...` 返回的是 HTML 页面，会被截断）
2. **`packages/**/src/*.ts`** 源码，确认签名和边界
3. **本机 `app.asar`**（`npx asar extract`）—— minified，只用来确认「运行时装了什么」

**踩过的教训（2026-11-16）**：为确认「DSH 是否暴露插件配置 schema」，
先在 asar 的 minified 代码里翻了很久没找到结论，还据此写过「大概没有」。
读了源码后一次查清：`remote.settings.describe / mutate` 早就存在，
而且官方文档明说「供按 schema 生成页面的客户端使用；**目前没有已发布的客户端这样做**」。

```bash
# 拿纯文本 README 的正确写法（blob 链接不行）
C=<commit-sha>
curl -sS "https://raw.githubusercontent.com/deepseek-ai/deepseek-harness/$C/packages/settings/settings/README.zh.md"

# 列目录用 API
curl -sS "https://api.github.com/repos/deepseek-ai/deepseek-harness/contents/packages/boot?ref=$C"
```

## 3.8 消息来源：这条是手机发的还是电脑发的

iOS App 发出的消息，正文末尾带 **U+2063 ×2**（INVISIBLE SEPARATOR，零宽不可见）；
Mac 桌面端（DSH Web）发出的消息**不带**。这是唯一可靠的来源判据——
DSH 的 `user/message.source` 只有 `kind` / `rpcId` / `clientTimeZone`，**没有客户端标识**。

**读原始内容判断，不要靠渲染后的视觉**（零宽字符看不见）：

```bash
# 查最近一条用户消息是不是带 iOS 标记
L=$(ls -t ~/.dsh/sessions/*dsh-pocket-ios*/session-*/session.v4.jsonl.zstd | head -1)
zstd -dc "$L" | python3 -c "
import sys, json
last = None
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: o = json.loads(line)
    except: continue
    # ⚠️ 必须同时限定 source.kind == 'user'：
    # type 是 user/message 的还有 time-context、agent-instructions 等系统注入，
    # 只按 type 取最后一条会拿到注入内容，判出来永远是 Mac（已踩）。
    if o.get('type') == 'user/message' and o.get('data', {}).get('source', {}).get('kind') == 'user':
        last = o
for b in last['data']['content']:
    if b.get('type') == 'text':
        t = b['text']
        print('iOS' if t.endswith('\u2063\u2063') else 'Mac', '|', repr(t[-8:]))
"
```

**什么时候必须先查这个**：

- 用户报「App 进不去 / 闪退 / 点了没反应」
- 出现「我这边正常、你那边不对」的分歧
- 改过发送路径、鉴权、启动流程之后

**为什么**：这台机器的 iOS 端是 AI 直接装机调试的，**崩的概率明显高于桌面端**。
分不清来源时，会在错误的一侧白查很久（2026-11-18 就发生过：
把 App 跑挂了却在查服务端，来回四轮）。

**注意**：这个标记**只用于归因，不许当功能用**。不要基于它改变回复内容或行为——
用户可能同时在两端发消息。

## 4. 硬性禁止

- 不要把公网地址、token、凭证写进代码或日志（历史已因此重写过一次）。
- 不要新增 `+Feature` extension 堆叠（那是假拆分，见架构规范）。
- 不要用 `.system(size:)` 硬编码字号（用系统文本样式，见交互规范）。
- 不要在小改动里夹带无关重构（漂移是主要回归来源）。
