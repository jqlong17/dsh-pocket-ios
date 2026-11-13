# 新建会话时选择工作区 + 工作区拖动排序

> **Status**: In Review
> **起始日期**：2026-11-13
> **预估工时**：150 分钟（单元累加，含 11-13 追加的排序需求）
> **对应提交**：（完成后回填）
> **文件名**：`spec/2026-11-13-0805-workspace-picker-on-create.md`

## 背景 / 问题

新建会话现在固定落在「默认工作区」：`createSession()` 内部调用
`workspace/initializeDefault` 拿到默认工作区 id，直接塞进 `session/create`。

用户指出这不合理：

> 现在新建对话的时候，会自动放在默认的工作区内。但是这个其实不合理，
> 最好还是让我选择一下工作区，可以默认帮用户选择一个工作区也就是默认工作区，
> 但是应该支持用户选择一个工作区。

即：**默认选中默认工作区，但用户要能换**。

## 目标与非目标

**目标**
1. 新建会话前可以先选工作区；不选时行为与现在完全一致（落默认工作区）。
2. 选择器里能看到每个工作区的**标题 + 路径 + 会话数**，据此判断选哪个。
3. 记住上次选择（同一会话内），下次新建默认停在上次那个而不是永远默认工作区。
4. **（11-13 追加）** 会话列表里的工作区分组支持长按拖动调整显示顺序。

**非目标**
- 不做「新建工作区」流程（`workspace/create` 需要目录选择，`directoryPicker` 是 Host 侧弹窗，
  移动端体验另议，留给后续）。
- 不改会话创建成功后的导航行为（仍直接进对话）。
- 不做工作区重命名/删除（`workspace/rename`、`workspace/delete` 已有接口，属另一件事）。

## 参考实现（Prior art）

- **Xcode / VS Code 的 New Project → 目录选择**：先选位置再创建，默认停在上次目录。
  → **采用**：默认选中「上次用过的」，首次用默认工作区。
  → **不采用**：完整的文件浏览器（移动端太重，且本需求只选已有工作区）。
- **GitHub Desktop 的 Repository 切换**：列表项展示「名称 + 路径」两行，选中项打勾。
  → **采用**：两行布局（标题 + 灰字路径），选中打勾。
- **iOS 的 `Picker` + `.sheet` 底部卡片**：系统提供的手势与视觉。
  → **采用**：`presentationDetents([.medium, .large])`，短列表用 medium。
  → **不采用**：自绘弹窗（没必要重造）。

## 方案

### 第 1 步：Model 加载工作区列表

`workspace/follow` 是 stream，首帧即 `baseline`，带完整列表：

```json
{ "type": "baseline", "value": { "items": [
    { "workspaceId": "...", "path": "/Users/x/proj", "title": "proj", "sessionIds": [...] }
] } }
```

Model 侧：

```swift
struct PocketWorkspace: Identifiable, Equatable {
    let workspaceId: String
    let path: String
    let title: String
    let sessionCount: Int
}

extension ConnectionModel {
    func loadWorkspaces() async   // 调 workspace/follow，取首帧后断开
    var defaultWorkspaceId: String?   // workspace/initializeDefault 的返回
}
```

**为什么复用 `workspace/initializeDefault` 拿默认值**：它的语义就是「默认工作区」，
不必自己猜（比如取列表第一个可能选错）。

### 第 2 步：`createSession` 接受显式工作区

```swift
func createSession(in workspaceId: String? = nil) async {
    let target = workspaceId ?? (try? await defaultWorkspaceId())
    // …原逻辑，把 target 塞进 session/create 的 workspaceId
}
```

**默认参数保证向后兼容**：现有调用点（如热键、deep link）不传就仍走默认工作区。

### 第 3 步：选择器 UI

点 `+` 先弹 `WorkspacePickerSheet`，而不是直接建会话：

```
┌─────────────────────────────┐
│  新建会话                    │
│  ┌─────────────────────────┐│
│  │ ✓ ios-client            ││  ← 默认选中（上次用的或默认工作区）
│  │   ~/projects/ios-client ││
│  │   12 个会话              ││
│  ├─────────────────────────┤│
│  │   dsh                   ││
│  │   ~/projects/dsh        ││
│  │   31 个会话              ││
│  └─────────────────────────┘│
│        [取消]   [创建]       │
└─────────────────────────────┘
```

- `.presentationDetents([.medium, .large])`
- 选中项打勾（`checkmark`）
- 「创建」按钮带 loading（`session/create` 有网络往返）
- 失败落 `reportActionError`

### 第 4 步：记住上次选择

`@AppStorage("dsh-pocket.lastWorkspaceId")`：
- 首次为空 → 用 `defaultWorkspaceId`
- 建会话成功后写入选中 id

**为什么用 AppStorage 而不是内存**：用户「上次用哪个工作区」是跨启动的偏好，
和 `SessionListMode` 同类。

**改动范围**：`DSHPocket/Session/SessionActions.swift`、
新增 `DSHPocket/Views/WorkspacePickerSheet.swift`、`DSHPocket/Model/PocketWorkspace.swift`、
`ConnectedView.swift`（`+` 按钮的入口）、`ConnectionModel+Process.swift`（解析 helper）

### 第 5 步（11-13 追加）：工作区拖动排序

会话列表按工作区分组显示（`workspace/follow` 的 `items` 顺序就是「手动顺序」）。
长按分组标题拖到新位置后，调用 `workspace/insertBefore` 落库。

```swift
workspace/insertBefore {
    request: {
        workspaceId: "被移动的",
        beforeWorkspaceId: "插到这个之前" | null   // null = 移到末尾
    }
}
```

**UI**：`.draggable` + `.dropDestination`（iOS 16+），封装成 `WorkspaceDragModifier`。

~~原先打算用 `.onMove`~~ —— 实现时发现不行，见变更记录 #3。

**为什么服务端也要落**：本地排序只是本次会话的视图顺序，DSH 桌面端看到的是同一份顺序。
不落库的话手机上调完、电脑上还是旧的，用户会觉得「白拖了」。

**风险**：拖完立刻重排本地数组（乐观更新），请求失败要回滚并提示。

## 被否决的方案

| 方案 | 否决理由 | 否决依据 |
| --- | --- | --- |
| 长按 `+` 才出选择器，点按直接建 | 用户明确要「新建的时候让我选择」；长按是隐藏入口，发现不了 | 需求原话 |
| 每次新建都强制选（不默认） | 用户明确说「可以默认帮用户选择一个」 | 需求原话 |
| 选择器里内置「新建工作区」 | `workspace/create` 要 path，路径得靠 `directoryPicker`（Host 侧原生弹窗），移动端拿不到；强行做要传绝对路径，用户没法浏览 | API 限制 |
| 列表只显示 title | 同名工作区常见（都叫 `src`），路径是唯一区分手段 | 实际使用 |
| 用 `session/create` 失败再回退默认 | 失败已经发生了才回退，用户白等一次 | 体验 |
| **什么都不做** | 代价：所有会话堆在默认工作区，用户得去电脑上改 | 需求 |

## 代价与风险

**代价**（确定会付）
- 新增一个 sheet + 一个模型类型，约 180 行。
- 多一次 `workspace/follow` 往返（首帧即断开，约 100–300ms；可在打开 sheet 时并行）。

**风险**（可能发生）
| 风险 | 缓解 |
| --- | --- |
| `workspace/follow` 不断开会占着连接 | 拿到 baseline 立刻 `cancel()`；超时 3 秒兜底 |
| 工作区很多（>10）sheet 滚不动 | 用 `List` 而非 `VStack`，`medium` 高度也能滚 |
| 上次选的工作区被删除 | 回退到 `defaultWorkspaceId`，并清掉 AppStorage |
| `session/create` 传空 workspaceId | 服务端可能拒绝；为空时退回不传（保持旧行为） |

**为什么不该做这件事**（Drawbacks，诚实写反面）
- 现在「自动落默认工作区」其实是可用的，只是不够灵活。做完这个功能，
  用户**每次新建都要多一次点击**（选完再点创建）。如果用户 90% 的时候都用默认工作区，
  这就是净负担。
- 折中方案（未采用）：默认直接创建，但创建后在会话里提供「移动到工作区」。
  这依赖一个不存在的接口（见下文「未决问题」），所以本轮做不了。

## 未决问题（Unresolved Questions）

- **会话建好后能不能换工作区？** 查过 DSH RPC 全表：`workspace/*` 只有
  create/rename/delete/pinSession/insertBefore/archiveSession/unarchiveSession，
  `session/*` 里与路径相关的是 `openWorkspacePath`（在 Host 桌面打开路径）和
  `canOpenWorkspacePath`，**没有「把已有会话移到另一个工作区」的接口**。
  所以「建完再改」做不了，只能在建之前选。这条要写进 journey。
- 选择器里是否显示「会话数」？如果 `sessionIds` 与实际可见会话不一致（归档等），
  数字可能误导。本轮先显示，若用户反馈困扰再去掉。
- 是否需要记住「按项目固定工作区」（比如按当前会话的 cwd 推荐）？本轮不做。

## 测试计划（先红后绿）

| 用例 | target | 断言 |
| --- | --- | --- |
| 工作区解析 | `DSHKit` `WorkspaceParsingTests` | 从 baseline JSON 解析出 id/path/title/sessionCount；缺字段的项被跳过 |
| 默认工作区解析 | 同上 | `workspace/initializeDefault` 返回 `workspace.workspaceId` 能被取出 |
| 空列表不崩 | 同上 | `items` 为空时返回 `[]` |
| 上次选择失效回退 | 同逻辑（纯函数） | 记录 id 不在列表 → 返回默认 id |
| 回归 | `swift test` | 359 绿 |
| 架构 | `check-architecture.sh` | 违规 0 |
| 真机：默认工作区 | 手工 | 首次点 + 选中默认工作区 |
| 真机：切到另一个 | 手工 | 选另一个 → 创建 → 会话落在该工作区 |
| 真机：记住上次 | 手工 | 第二次点 + 停在刚用过的那个 |
| 排序参数正确 | `DSHKit` `WorkspaceParsingTests` | `insertBefore` 的 args 组成正确：移到末尾时 `beforeWorkspaceId` 省略/为 nil；移到中间时为目标 id |
| 真机：拖动排序 | 手工 | 拖完刷新后顺序仍是新的（服务端已落库） |

## 预估工时

| 单元 | 数量 | 单耗依据 | 小计 |
| --- | --- | --- | --- |
| spec 定稿 | 1 | 实测约 20 | 20 分钟 |
| 解析类型 + 3 条测试 | 1 | 同类 20 | 20 分钟 |
| Model 加载工作区（follow 首帧 + 断开） | 1 | 约 40 行 | 25 分钟 |
| 选择器 sheet | 1 | 约 100 行 | 30 分钟 |
| `createSession` 改造 + 入口接线 | 1 | 约 20 行 | 10 分钟 |
| 编译 + 测试 + 架构 | 4 轮 | 每轮约 2 | 8 分钟 |
| 真机验证三条 | 1 | — | 12 分钟 |
| **合计** | | | **105 分钟** |

---

## 变更记录

| # | 日期 | 原判断 | 新判断 | 触发原因 |
| --- | --- | --- | --- | --- |
| 1 | 11-13 | 范围只有「新建时选工作区」，非目标里明确写「不做排序」 | **范围加「工作区拖动排序」** | 用户：「会话列表的这些工作区行，最好能支持我手动按住后拖动的修改这些工作区之间的显示顺序」 |
| 2 | 11-13 | 预估 105 分钟 | **150 分钟** | 排序功能需要 Model 调用 `workspace/insertBefore` + List 拖动 UI + 失败回滚，约 45 分钟 |
| 3 | 11-13 | 排序 UI 用 `ForEach.onMove` | **改 `draggable` + `dropDestination`** | 会话列表是「分组 → 会话」的嵌套 `ForEach`，`onMove` 作用在直接子项上，写上去会变成「组内排会话」而不是「排组」。`draggable/dropDestination` 才能表达「拖这个组头放到那个组头上」 |
| 4 | 11-13 | 选择器按服务端返回顺序 | **默认工作区固定第一 + 其余按最近活跃降序** | 用户：「默认可以把默认工作区放在第一个位置，并且默认勾选上，另外这些工作区的排序最好是默认按照活跃的时间降序排列」。工作区自身没有活跃时间，按 `path` 从 `session/list` 的 `updatedAt` 取最新一条 |
