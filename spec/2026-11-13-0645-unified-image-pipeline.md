# 统一图片管线 + 全屏翻页 + 延迟清理

> **Status**: In Review（代码完成，待真机验证）
> **起始日期**：2026-11-13
> **预估工时**：185 分钟（单元累加）
> **对应提交**：`3d44a20`
> **文件名**：`spec/2026-11-13-0645-unified-image-pipeline.md`

## 背景 / 问题

用户发现「聊天里发的截图点开是糊的」，排查后定位到三件事：

### 问题 1：两条图片链路不一致（根因）

| | 附件图片（过程区） | Markdown 内嵌图 |
| --- | --- | --- |
| 数据来源 | `session/attachment` RPC（带 `maxPixel` 尺寸协商） | `URLSession.data(from: URL)` |
| 缩略 | 640（`tier: .thumbnail`） | 640（硬编码） |
| **全屏** | **2048（`tier: .full`）** | **640（没有 full 层）** |
| 缓存 | 内存 32MB + 磁盘 5MB | 仅内存 |
| 磁盘缓存键 | `{attachmentId}-{maxPixel}.jpg` | 无 |

**后果**：Markdown 图全屏时是 640px 放大到 2868px 屏幕（约 4.5×），必然糊。
`RemoteMarkdownImage` 拿到的其实是**原图字节**，但解码时直接砍到 640，高清数据被丢弃。

### 问题 2：全屏只能看一张

`FullscreenImageViewer` 传入单张 `UIImage`，无法左右滑动看同会话的其他图。用户看一屏截图想对比前后几张，只能退出再点。

### 问题 3：滑出屏幕立即清空

`RemoteMarkdownImage` 的 `.onDisappear { image = nil }` —— 快速滑动列表时，图片反复销毁重建，
表现为「滑回来先看到转圈」。内存缓存还在，但视图状态要从头走一遍。

## 目标与非目标

**目标**
1. **一条图片管线**：附件图与 Markdown 图走同一套缓存、分层、降采样逻辑，只保留「怎么拿原始字节」的差异。
2. **全屏可左右翻页**，翻到哪张才拉哪张的高清。
3. **视图消失后延迟 5 秒清空**，滑动来回不重新加载。
4. 修复「Markdown 图全屏糊」——全屏分辨率按设备屏幕像素算。

**非目标**
- 不改服务端（`session/attachment` 与 `api/file` 的接口形状不动）。
- 不改气泡/过程区里缩略图的 640 上限（省内存是对的）。
- 不动 Markdown 表格、代码块的渲染。
- 不改 `240pt` 宽度上限（用户实测观感正常，本轮不动）。

## 参考实现（Prior art）

- **SDWebImage / Kingfisher 的分层缓存**：memory（NSCache）+ disk（LRU）+ 单一 pipeline，
  不同来源（URL / PHAsset / 本地文件）通过 `Source` 抽象统一。
  → **采用**：把「来源」抽成接口，缓存/降采样/pipeline 只留一份。
  → **不采用**：引入完整第三方库。我们已有 `ImagePipeline` + 两层缓存，
  缺的只是「来源抽象」，加库属于杀鸡用牛刀。
- **Apple 的 `CGImageSourceCreateThumbnailAtIndex`**：按目标尺寸解码而非全解码再缩，
  内存占用与目标尺寸成正比。项目已在 `ImageMemory.thumbnail` 使用。
  → **采用**：高低清两档都走它，只是 `kCGImageSourceThumbnailMaxPixelSize` 不同。
- **iOS 相册/Photos 的全屏手势**：左右翻页用 `TabView(.page)` 或横向分页 `ScrollView`。
  → **采用** `TabView(.page)`：自带分页手势与相邻页预加载，代码最少。

## 方案

### 第 1 步：抽出「图片来源」接口（DSHKit，可测）

```swift
public protocol ImageByteSource: Sendable {
    /// 缓存键：不同来源必须不同，同来源不同尺寸由 pipeline 拼后缀。
    var cacheKey: String { get }
    /// 拿原始字节。`maxPixel` 是给「支持尺寸协商的来源」用的提示。
    func data(maxPixel: Int) async throws -> Data
}
```

两个实现（都在 App 层，因为依赖 RPC / URLSession）：

```swift
struct AttachmentByteSource: ImageByteSource   // ─ session/attachment RPC（带 maxPixel）
struct RemoteURLByteSource: ImageByteSource    // ─ URLSession.data(from:)
```

**为什么放 DSHKit 只放协议**：协议本身是纯类型，可测；实现依赖网络与 RPC，
放 App 层。这样 `ImagePipeline` 依赖协议而不是具体实现。

### 第 2 步：`ImagePipeline` 接受任意来源，保留 tier 分层

```swift
func image(source: ImageByteSource,
           tier: Tier,                 // .thumbnail(640) / .full(screenPixels)
           maxPixel: CGFloat) async -> UIImage?
```

内部逻辑不变（内存 → 磁盘（仅 thumbnail）→ in-flight 去重 → 降采样 → 回写缓存），
只是把「取字节」换成 `source.data(maxPixel:)`。

**为什么磁盘缓存只给 thumbnail**：高清图动辄 800KB–1MB，存磁盘会让 5MB 预算只能放 5 张，
把缩略图挤出去反而更慢。高清只在全屏时临时用，退出即可丢（内存缓存足够）。

**改动范围**：`DSHPocket/Model/ImagePipeline.swift`、新增 `DSHPocket/Model/ImageByteSource.swift`

### 第 3 步：全屏分辨率按设备像素算

```swift
// ImageFetchPolicy（DSHKit）
public static var fullMaxPixel: Int {
    // 由调用方注入，DSHKit 不依赖 UIKit
}
public static func fullMaxPixel(screenLongSide: Int) -> Int {
    max(screenLongSide, 2048)     // 至少 2048，屏幕更大就按屏幕
}
```

**为什么用函数而不是常量**：DSHKit 是纯逻辑层，不能读 `UIScreen`。
App 侧传入 `UIScreen.bounds.longSide * scale`（Pro Max = 2868），**1:1 不放大**。

### 第 4 步：全屏支持左右翻页 + 按需拉高清

`FullscreenImageViewer` 从「单张图」改为「图片集合 + 当前索引」：

```swift
struct FullscreenImageViewer: View {
    let items: [FullscreenItem]      // 同会话按时间排序的全部图片
    @State private var index: Int
    @State private var loaded: [Int: UIImage] = [:]   // 只装已加载的
}
```

- 首帧用调用方已持有的缩略图（点开**立刻有图**，不转圈）
- `TabView(selection: $index)` 分页
- `.task(id: index)`：翻到某页就为该页请求 `tier: .full`，回来换掉缩略图
- 相邻页不预取（`TabView` 只渲染当前页，天然满足「滑动才请求」）

**为什么不预取相邻页**：用户明确要求「滑动时才请求高清」。预取会让快速划过时浪费流量。

### 第 5 步：延迟 5 秒清空

`RemoteMarkdownImage` 的 `.onDisappear { image = nil }` 改为：

```swift
@State private var clearTask: Task<Void, Never>?

.onAppear { clearTask?.cancel(); clearTask = nil }
.onDisappear {
    clearTask = Task {
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        await MainActor.run { image = nil }
    }
}
```

**为什么 5 秒不是立即**：列表快速滑动时，一屏之外的图片反复进出。
立即清空 = 每次都重建；5 秒足够覆盖「滑过去又滑回来」的常见操作，
又不会长时间占着解码后的位图（一张 640 缩略约 1.6MB）。

### 第 6 步：Markdown 图接入新管线

`RemoteMarkdownImage` 不再自己 `URLSession` + `ImageMemory.thumbnail`，
改为 `ImagePipeline.shared.image(source: RemoteURLByteSource(url), tier: .thumbnail, ...)`。

**改动范围**：`DSHPocket/Views/RemoteMarkdownImage.swift`、`FullscreenImageViewer.swift`、
`ConnectionModel+Process.swift`（补 `loadFullImage(source:)`）

## 被否决的方案

| 方案 | 否决理由 | 否决依据 |
| --- | --- | --- |
| 只把 Markdown 图的 640 改成 2048（治标） | 两条链路仍然各自维护缓存与降采样，下次再出问题还要改两处 | 用户明确要求「抽象成一套复用」 |
| 引入 Kingfisher / SDWebImage | 已有一半实现，缺的只是来源抽象；引入第三方要吃它的 API 与包体积 | 项目已有 `ImagePipeline` + 两层缓存 |
| 全屏预取相邻 2 张 | 用户明确说「滑动时才请求」；预取在快速划过时浪费流量 | 需求原话 |
| 视图消失立即清空 | 快速来回滑会反复重建，体感是「永远在转圈」 | 用户反馈 |
| 视图消失永不清理 | 一张全屏 2868px 解码后约 15MB，留多了会被系统杀 | 内存实测（148→161MB 已接近告警区） |
| **什么都不做** | 代价：截图永远糊、看不了相邻图、滑动闪 | 用户反馈 |

## 代价与风险

**代价**（确定会付）
- 新增一个协议与两个实现（约 80 行）+ `ImagePipeline` 改造。
- 全屏组件从「单图」变「集合 + 状态」，代码量增加约 60 行。
- 全屏高清从 2048 → 2868：单张解码 7.7MB → **15MB**，同时开两张 30MB。

**风险**（可能发生）
| 风险 | 缓解 |
| --- | --- |
| 全屏同时开多张高清 → 内存峰值 | 只保留当前页 + 上一页的高清，其余丢；离开全屏全部清 |
| `TabView(.page)` 在 `.fullScreenCover` 里手势冲突 | 真机验证左右滑与下滑关闭能共存 |
| 5 秒延迟任务泄漏 | `onAppear` 取消 + `Task.isCancelled` 双重判断 |
| 附件与 Markdown 的缓存键冲突 | 键前缀区分（`att:` / `md:`），单测锁定 |

**为什么不该做这件事**（Drawbacks，诚实写反面）
- 这三件事都在优化「看图的体验」，不是核心功能。如果近期重点是稳定性与新功能，
  这 185 分钟可以不花。
- 统一管线是**结构性改动**，动的是所有图片的加载路径；一旦有 bug，影响面覆盖聊天里所有图片。
  相比之下「只把 Markdown 图改成 2048」是 10 行的局部修补，风险小得多。

## 未决问题（Unresolved Questions）

- 全屏翻页时，图片集合按什么顺序？按消息时间正序还是倒序？本轮用**时间正序**（与聊天阅读方向一致），
  若用户习惯「从最新往回翻」，需要调整。
- 图片集合的范围：只限当前会话，还是跨会话？本轮限当前会话。
- 高清图是否要写磁盘缓存（跨启动复用）？本轮不写，理由见第 2 步；若实测重复打开很慢再考虑。

## 测试计划（先红后绿）

| 用例 | target | 断言 |
| --- | --- | --- |
| 缓存键不冲突 | `DSHKit` `ImageByteSourceTests` | 附件源与 URL 源拼接后键不同 |
| 全屏像素取屏幕值 | `DSHKit` `ImageFetchPolicyTests` | `fullMaxPixel(screenLongSide: 2868) == 2868`；`1200` 时返回 2048 |
| 分层尺寸 | 同上 | `thumbnailMaxPixel == 640` 不变 |
| 回归 | `swift test` | 356 绿 |
| 架构 | `check-architecture.sh` | 违规 0 |
| 真机：Markdown 图全屏清晰 | 手工 | 点开截图，文字可读（对比修改前明显改善） |
| 真机：全屏左右翻 | 手工 | 能翻到同会话其余图片，翻到才转圈 |
| 真机：快速滑动列表 | 手工 | 滑回来不重新转圈 |

## 预估工时

| 单元 | 数量 | 单耗依据 | 小计 |
| --- | --- | --- | --- |
| spec 定稿 | 1 | 实测约 25 | 25 分钟 |
| DSHKit 协议 + 2 条测试 | 1 | 同类 20 | 20 分钟 |
| `ImagePipeline` 改造 | 1 | 约 60 行改动 | 30 分钟 |
| App 侧两个 Source 实现 | 2 | 约 20/个 | 25 分钟 |
| 全屏翻页组件 | 1 | 约 100 行 | 45 分钟 |
| 5 秒延迟清理 | 1 | 约 15 行 | 12 分钟 |
| 编译 + 测试 + 架构 | 4 轮 | 每轮约 2 | 8 分钟 |
| 真机验证三条 | 1 | 实测 20 | 20 分钟 |
| **合计** | | | **185 分钟** |

---

## 实现进度（2026-11-13 07:30）

| 步骤 | 状态 |
| --- | --- |
| 1. `ImageByteSource` 协议 + 键前缀 | ✅ DSHKit，+3 条测试 |
| 2. `ImagePipeline` 改 source 驱动 | ✅ 附件与 Markdown 共用同一套缓存/分层/去重 |
| 3. `fullMaxPixel` 按屏幕算 | ✅ 函数化，2868 屏幕取 2868（原固定 2048） |
| 4. 全屏翻页 | ✅ `TabView(.page)`，翻到才拉高清，页脚显示 `n / N` |
| 5. 延迟 5 秒清理 | ✅ `onAppear` 取消 + `Task.isCancelled` 双保险 |
| 6. Markdown 图接入管线 | ✅ 不再自己 `URLSession` + 硬编码 640 |

**本轮未做（记入未决问题）**：`AttachmentThumbnail`（过程区附件图）仍是单张全屏，
没有接入翻页。它和 Markdown 图的数据源不同（`PocketImageRef` 列表需要从 `steps` 里收集），
本轮先做用户实际遇到的 Markdown 图。

**验证状态**：`swift test` 359 绿；架构 0 违规；已装机。
真机三条待验：Markdown 图全屏清晰、左右翻页、快速滑动不重新转圈。
