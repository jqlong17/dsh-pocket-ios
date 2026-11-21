// PluginPanelSheet

import SwiftUI
import WebKit
import DSHKit

/// 插件移动面板：把插件声明的移动页面装进一个和「后台任务」一致的外壳里。
///
/// 这一版是**协议 v1 的 Layer 1（WebView 兜底）**，目的不是最终形态，
/// 而是验证「手机上到底会不会用插件」。所以刻意保持薄：
/// 原生只负责外壳（标题、加载态、失败态），内容完全交给插件自己的页面。
struct PluginPanelSheet: View {
    let baseURL: URL

    /// 提供「插件列表页」的那个插件。有它就用它的页面作为面板首页；
    /// 没有（用户没装插件管理）时退回第一个声明了移动端的插件。
    private static let aggregatorModule = "dsh-plugin-panel"

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading
    @State private var entry: PluginMobileEntry?
    @State private var pageURL: URL?
    @State private var webError: String?

    /// 非空表示走「原生列表」分支（新通道）。
    @State private var installed: PluginInstalledCatalog?
    /// 原生列表用的 token（新通道签发的，开关也用它）。
    @State private var nativeToken: String?
    /// 本地乐观更新：开关一点就变，失败再回滚。
    @State private var enabledOverrides: [String: Bool] = [:]
    /// 正在切换中的插件，避免连点。
    @State private var busyModules: Set<String> = []
    /// 切换失败的提示。
    @State private var toggleError: String?
    /// 每条的「未生效」提示（重启后生效 / 被覆盖），按 module 记。
    @State private var togglePendingNote: [String: String] = [:]
    /// 页面里是否已经打开了某个插件——只有这时导航栏才出现「返回」。
    @State private var viewerOpen = false
    /// 让导航栏的返回能回到插件列表。
    @StateObject private var webBox = PluginWebViewBox()

    private enum Phase: Equatable {
        case loading
        case ready
        case empty
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView(L10n.t("正在准备插件页面…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .empty:
                    ContentUnavailableView(
                        L10n.t("这台电脑上没有支持手机端的插件"),
                        systemImage: "puzzlepiece.extension",
                        description: Text(L10n.t("插件可以在 package.json 里声明 dsh.mobile 来启用手机端页面。"))
                    )

                case .failed(let message):
                    ContentUnavailableView(
                        L10n.t("打不开插件面板"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )

                case .ready:
                    // 顺序很重要：用户点了某个插件（pageURL 有值）就该显示它的页面，
                    // 而不是继续停在列表上。之前反过来写，导致「点了没反应」。
                    if let pageURL {
                        PluginWebView(url: pageURL, errorMessage: $webError, viewerOpen: $viewerOpen, box: webBox)
                            .ignoresSafeArea(edges: .bottom)
                            .overlay {
                                if let webError {
                                    ContentUnavailableView(
                                        L10n.t("页面加载失败"),
                                        systemImage: "wifi.exclamationmark",
                                        description: Text(webError)
                                    )
                                    .background(.background)
                                }
                            }
                    } else if let installed {
                        nativeList(installed)
                    }
                }
            }
            .navigationTitle(entry?.title ?? L10n.t("插件"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 返回有**两层**，别混：
                //   ① 插件页内部开了查看器（图片放大等）→ 先关查看器，回插件页
                //   ② 已经在插件页 → 回插件列表
                // 之前只写了 ①，条件是 viewerOpen，所以直接进插件页时没有返回按钮。
                if viewerOpen {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            webBox.closeViewer()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "chevron.backward")
                                    .font(.body.weight(.semibold))
                                Text(L10n.t("返回"))
                            }
                        }
                        .accessibilityLabel(L10n.t("关闭查看器"))
                    }
                } else if pageURL != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            // 清空 pageURL 就切回列表；顺手清掉上一页的加载错误，
                            // 否则回到列表后那条错误还挂着。
                            pageURL = nil
                            webError = nil
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "chevron.backward")
                                    .font(.body.weight(.semibold))
                                Text(L10n.t("插件列表"))
                            }
                        }
                        .accessibilityLabel(L10n.t("返回插件列表"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("完成")) { dismiss() }
                }
            }
        }
        .task { await prepare() }
    }

    /// 移动端接入指引（飞书文档）。作者改完插件后按里面的清单自查。
    private static let mobilePluginGuideURL = URL(string: "https://github.com/jqlong17/dsh-pocket-ios/blob/main/public/插件移动端接入指引.md")!

    /// 换 token → 拉列表 → 拼出要加载的地址。
    ///
    /// 为什么一次只加载**第一个**声明了移动端的插件：协议 v1 明确「一个按钮 → 一个面板」，
    /// 多插件选择列表留到后续。真出现多个时，取第一个并记录诊断，避免静默忽略。
    // MARK: - 原生列表

    /// 原生插件列表：比 WebView 里的 HTML 更跟手，也不存在「token 跨插件失效」的问题。
    @ViewBuilder
    private func nativeList(_ catalog: PluginInstalledCatalog) -> some View {
        if catalog.isEmpty {
            ContentUnavailableView(
                L10n.t("这台电脑上还没装插件"),
                systemImage: "puzzlepiece.extension",
                description: Text(L10n.t("在电脑端的 DSH 里安装插件后，这里就能看到。"))
            )
        } else {
            // 分成两组而不是给每一行加「不支持手机」：23 行重复同一句会把可用插件淹没，
            // 而分组标题只说一次，用户一眼就知道「哪些能点开、为什么其余的不能」。
            let openable = catalog.plugins.filter(\.canOpen)
            let desktopOnly = catalog.plugins.filter { !$0.canOpen }

            List {
                // 放在最上方：插件作者打开这个面板时，第一眼就能看到「怎么让自己的插件也能被打开」。
                Section {
                    Link(destination: Self.mobilePluginGuideURL) {
                        HStack(spacing: 10) {
                            Image(systemName: "book")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("开发能在手机上打开的插件"))
                                Text(L10n.t("接入指引：dsh.mobile 声明、路由、token、六个坑"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if !openable.isEmpty {
                    Section {
                        ForEach(openable) { plugin in
                            row(plugin)
                        }
                    } header: {
                        Text(L10n.tf("可在手机上打开 %d 个", openable.count))
                    } footer: {
                        Text(L10n.t("拨动开关会在电脑上重载插件。"))
                    }
                }

                if !desktopOnly.isEmpty {
                    Section {
                        ForEach(desktopOnly) { plugin in
                            row(plugin)
                        }
                    } header: {
                        Text(L10n.tf("仅桌面端 %d 个", desktopOnly.count))
                    } footer: {
                        Text(L10n.t("这些插件只有电脑端界面，手机上打不开。插件作者声明 dsh.mobile 之后才会出现在上面。"))
                    }
                }

                if let toggleError {
                    Section {
                        Text(toggleError).foregroundStyle(.red)
                    }
                }

            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func row(_ plugin: PluginInstalledEntry) -> some View {
        let on = enabledOverrides[plugin.module] ?? plugin.enabled
        let busy = busyModules.contains(plugin.module)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(plugin.title)
                        .font(.body)
                        .foregroundStyle(on ? .primary : .secondary)
                    if plugin.canOpen {
                        Image(systemName: "iphone")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(L10n.t("支持手机打开"))
                    }
                    if !plugin.version.isEmpty, plugin.version != "0.0.0" {
                        Text(plugin.version)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if !plugin.summary.isEmpty {
                    Text(plugin.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                // 运行状态：开关反映的是「配置启用」，这里补上「实际在不在跑」。
                // 加载失败时开关仍是开着的——不显示这一行用户会以为它在正常工作。
                if !stateText(plugin, on: on).isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(runStateColor(plugin, on: on))
                            .frame(width: 6, height: 6)
                        Text(stateText(plugin, on: on))
                            .font(.caption2)
                            .foregroundStyle(runStateColor(plugin, on: on))
                        if !plugin.diagnostic.isEmpty {
                            Text(plugin.diagnostic)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                // 切换后没立即生效时留一条，别让用户以为已经切好了。
                if let pending = togglePendingNote[plugin.module] {
                    Text(pending)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            // 打开入口：只有声明了手机页面才有。整行点击也走这里。
            if plugin.canOpen, on {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Toggle("", isOn: binding(for: plugin))
                .labelsHidden()
                // 只读条目（受管理 / 不可寻址）改了也不会生效，禁用比假装可点更诚实。
                .disabled(busy || !plugin.canToggle)
                .opacity((busy || !plugin.canToggle) ? 0.4 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard plugin.canOpen, on, !busy else { return }
            open(plugin)
        }
    }

    /// 运行状态点的颜色。只有「跑着」是绿、「失败」是红，其余灰。
    /// 状态文字：**以开关当前值为准**。
    /// 刚拨开、服务端还没回新状态时显示「已启用」，而不是继续显示旧的「未启用」。
    private func stateText(_ plugin: PluginInstalledEntry, on: Bool) -> String {
        if busyModules.contains(plugin.module) { return L10n.t("处理中…") }
        if !on { return L10n.t("未启用") }
        return plugin.runStateLabel.isEmpty ? L10n.t("已启用") : plugin.runStateLabel
    }

    private func runStateColor(_ plugin: PluginInstalledEntry, on: Bool) -> Color {
        if !on { return .secondary }
        switch plugin.fiberPhase {
        case "active", "ready", "running": return .green
        case "failed", "error": return .red
        case "pending", "loading": return .orange
        default: return .secondary
        }
    }

    /// 开关的绑定：**先改本地状态再发请求**（乐观更新），失败回滚。
    /// 手机上等一次往返才动的开关会让人以为没按到。
    private func binding(for plugin: PluginInstalledEntry) -> Binding<Bool> {
        Binding(
            get: { enabledOverrides[plugin.module] ?? plugin.enabled },
            set: { newValue in
                let previous = enabledOverrides[plugin.module] ?? plugin.enabled
                guard newValue != previous else { return }
                enabledOverrides[plugin.module] = newValue
                Task { await toggle(plugin, to: newValue, rollbackTo: previous) }
            }
        )
    }

    private func toggle(_ plugin: PluginInstalledEntry, to enabled: Bool, rollbackTo previous: Bool) async {
        guard let token = nativeToken else { return }
        toggleError = nil
        busyModules.insert(plugin.module)
        defer { busyModules.remove(plugin.module) }
        do {
            let outcome = try await PluginMobileAPI.setPluginEnabled(
                baseURL: baseURL,
                token: token,
                module: plugin.module,
                enabled: enabled
            )
            // 立即生效就不打扰；需要重启 / 被覆盖时**必须说出来**，
            // 否则用户以为已经切好了，实际行为没变。
            if !outcome.note.isEmpty {
                togglePendingNote[plugin.module] = outcome.note
            } else {
                togglePendingNote[plugin.module] = nil
            }
            // 插件刚被启用时，fiberPhase 要等它真正加载完才有值。
            // 不刷新就会一直停在「已启用」，看不到「运行中」。
            Task {
                try? await Task.sleep(for: .seconds(2))
                await refreshInstalled()
            }
        } catch {
            // 失败必须回滚，否则开关停在用户以为成功了的位置。
            enabledOverrides[plugin.module] = previous
            togglePendingNote[plugin.module] = nil
            toggleError = error.localizedDescription
        }
    }

    /// 打开某个插件的手机页面：用**新通道的 token**（插件页面只验格式，能过）。
    private func open(_ plugin: PluginInstalledEntry) {
        guard let path = plugin.mobilePath, let token = nativeToken else { return }
        guard let url = PluginMobileAPI.pageURL(baseURL: baseURL, path: path, token: token) else {
            toggleError = L10n.t("插件声明的页面地址无效。")
            return
        }
        pageURL = url
        webError = nil
    }

    /// 只重新拉 `/installed`，不重新握手。
    /// 开关切换后用它拿新的 fiberPhase；同时清掉已经和服务端一致的覆盖值，
    /// 否则旧的乐观值会一直挡住新数据。
    private func refreshInstalled() async {
        guard let token = nativeToken else { return }
        guard let catalog = try? await PluginMobileAPI.fetchInstalled(
            baseURL: baseURL, token: token
        ) else { return }
        installed = catalog
        for plugin in catalog.plugins where enabledOverrides[plugin.module] == plugin.enabled {
            enabledOverrides[plugin.module] = nil
        }
    }

    private func prepare() async {
        do {
            // 双通道握手：`dsh-pocket-ios`（必装）优先，失败回退 `dsh-plugin-panel`（选装）。
            // 早先只认后者，导致只装了必装插件的用户点「插件」只能看到 HTTP 404。
            let session = try await PluginMobileAPI.fetchSession(baseURL: baseURL)

            // 新通道能拿结构化数据 → 原生列表（不经过 WebView，也就没有跨插件 token 问题）。
            if session.supportsNativeList {
                let catalog = try await PluginMobileAPI.fetchInstalled(
                    baseURL: baseURL,
                    token: session.token
                )
                nativeToken = session.token
                installed = catalog
                entry = session.catalog.entries.first { $0.module == Self.aggregatorModule }
                phase = .ready
                return
            }

            // 旧通道只有 HTML 列表页，退回原来的 WebView 路径。
            let result = session.catalog
            guard let first = result.entries.first else {
                // 有声明但不合格时把原因说出来——否则用户会以为是「没装插件」。
                // 这段判断逻辑在 DSHKit 里（PluginMobileCatalog.emptyStateMessage），有单测覆盖。
                if let message = result.emptyStateMessage {
                    phase = .failed(message.title + " — " + message.detail)
                } else {
                    phase = .empty
                }
                return
            }
            // 优先加载「聚合列表页」——它能开关插件、还能进别的插件，
            // 是用户点「插件」时真正想看的东西。
            //
            // 为什么不能只取 entries.first：哪个插件排第一取决于电脑端的返回顺序。
            // 换聚合通道后，排第一的变成了「音频解析」，面板会直接跳进它的页面，
            // 用户就再也看不到插件列表了（2026-11-16 实测到，是本轮引入的回归）。
            let preferred = result.entries.first { $0.module == Self.aggregatorModule } ?? first
            entry = preferred
            guard preferred.manifest.kind == .web, let path = preferred.manifest.path else {
                // kind == .native 需要 Layer 2 的 Schema 渲染器，本版还没实现
                phase = .failed(L10n.t("这个插件用了原生声明（schema），需要更新版本的 App。"))
                return
            }
            guard let url = PluginMobileAPI.pageURL(baseURL: baseURL, path: path, token: session.token) else {
                phase = .failed(L10n.t("插件声明的页面地址无效。"))
                return
            }
            pageURL = url
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// 让 SwiftUI 能操作底层 `WKWebView`：导航栏的「返回」要回到插件列表。
final class PluginWebViewBox: ObservableObject {
    weak var webView: WKWebView?

    /// 页面没暴露 `__dshCloseViewer` 时什么也不做，不报错。
    func closeViewer() {
        webView?.evaluateJavaScript("window.__dshCloseViewer && window.__dshCloseViewer();")
    }
}

/// 最薄的 `WKWebView` 包装：负责加载、上报失败，以及把「进/出插件页」告诉原生。
///
/// 为什么要有这条消息：插件页是加载在列表页内部的（同源 iframe），
/// `WKWebView` 自己不会产生导航记录，原生无从知道用户是不是已经进了某个插件。
/// 页面在打开/关闭时发一条消息，导航栏据此决定显不显示「返回插件列表」。
struct PluginWebView: UIViewRepresentable {
    let url: URL
    @Binding var errorMessage: String?
    @Binding var viewerOpen: Bool
    let box: PluginWebViewBox

    func makeCoordinator() -> Coordinator {
        Coordinator(errorMessage: $errorMessage, viewerOpen: $viewerOpen)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // 告诉页面「原生已经有返回按钮了」，页面就不用再画一条自己的
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: "window.__DSH_NATIVE_VIEWER__ = true;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: Coordinator.viewerMessage)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        box.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        box.webView = webView
        // 地址没变就不重载，避免 SwiftUI 重绘时把页面刷掉、丢掉用户滚动位置
        if webView.url != url, webView.isLoading == false {
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.viewerMessage)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let viewerMessage = "viewerState"

        private let errorMessage: Binding<String?>
        private let viewerOpen: Binding<Bool>

        init(errorMessage: Binding<String?>, viewerOpen: Binding<Bool>) {
            self.errorMessage = errorMessage
            self.viewerOpen = viewerOpen
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Coordinator.viewerMessage,
                  let body = message.body as? [String: Any],
                  let open = body["open"] as? Bool else { return }
            viewerOpen.wrappedValue = open
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            errorMessage.wrappedValue = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            errorMessage.wrappedValue = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // 收到 401 时 WKWebView 报的是通用加载失败，这里换成更可操作的文案
            if (error as NSError).code == NSURLErrorUserAuthenticationRequired {
                errorMessage.wrappedValue = L10n.t("插件页面拒绝了这次访问，请关掉面板重新打开。")
            } else {
                errorMessage.wrappedValue = error.localizedDescription
            }
        }
    }
}
