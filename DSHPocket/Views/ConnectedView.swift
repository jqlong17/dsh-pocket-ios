// ConnectedView

import SwiftUI
import Security
import DSHKit
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import Photos
import os
import AudioToolbox
import ImageIO
import UserNotifications


struct ConnectedView: View {
    @Bindable var model: ConnectionModel
    @AppStorage("dsh-pocket.session-list-mode") private var sessionListModeRaw = SessionListMode.grouped.rawValue
    @AppStorage("dsh-pocket.collapsed-groups") private var collapsedGroupsRaw = ""
    @State private var renamingSession: PocketSession?
    @State private var didAutoOpen = false
    @State private var searchText = ""
    @State private var showsWorkspacePicker = false
    /// 插件面板入口（会话列表页）。详情页也有一个，两处都通向同一个面板。
    @State private var showingPlugins = false
    /// 正在拖动的工作区分组 id（cwd 路径）；nil 表示没在拖。
    @State private var showsWorkspaceReorder = false
    @State private var reorderOptions: [PocketWorkspace] = []
    @State private var workspaceOptions: [PocketWorkspace] = []
    @State private var isLoadingWorkspaces = false
    @State private var defaultWorkspaceId = ""
    /// 上次用过的工区：跨启动记住，选择器默认停在这里。
    @AppStorage("dsh-pocket.lastWorkspaceId") private var lastWorkspaceId = ""
    @FocusState private var searchFocused: Bool
#if DEBUG
    private var hideDemoBanner: Bool { DebugLaunch.hideDemoBanner }
#else
    private var hideDemoBanner: Bool { false }
#endif

    private var collapsedGroupIDs: Set<String> {
        Set(collapsedGroupsRaw.split(separator: ",").map(String.init))
    }

    private func isCollapsed(_ id: String) -> Bool {
        collapsedGroupIDs.contains(id)
    }

    private func toggleGroup(_ id: String) {
        var ids = collapsedGroupIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        collapsedGroupsRaw = ids.sorted().joined(separator: ",")
    }

    /// 归档撤销条：系统材质 + 3 秒自动消失（Apple 临时提示的常见做法）。
    private var archiveUndoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill")
                .font(.subheadline)
                .foregroundStyle(PocketChrome.brandText)
            Text(L10n.t("会话已归档"))
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 16)
            Button(L10n.t("撤销")) {
                Task { await model.undoArchive() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PocketChrome.brandText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: model.lastArchivedSession?.sessionId) {
            guard let id = model.lastArchivedSession?.sessionId else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled,
                  model.lastArchivedSession?.sessionId == id else { return }
            withAnimation(PocketMotion.animation(.easeOut(duration: 0.2))) { model.dismissArchiveUndo() }
        }
    }

    /// 按设置切换：工作区分组 / 单一时间线。
    private var displayGroups: [ConnectionModel.SessionGroup] {
        if sessionListModeRaw == SessionListMode.timeline.rawValue {
            return [ConnectionModel.SessionGroup(id: "__timeline__", title: "",
                                                 sessions: model.displaySessions, isPinned: false)]
        }
        return model.sessionGroups
    }

    /// 搜索词只筛标题，不跳过分组；整组没命中就整组不显示。
    private var filteredGroups: [ConnectionModel.SessionGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return displayGroups }
        return displayGroups.compactMap { group in
            let hits = group.sessions.filter { $0.displayTitle.localizedCaseInsensitiveContains(query) }
            guard !hits.isEmpty else { return nil }
            return ConnectionModel.SessionGroup(id: group.id, title: group.title,
                                                sessions: hits, isPinned: group.isPinned)
        }
    }

    /// 底部搜索条：左边输入，右边放大镜。输入即筛，按钮用来收起键盘。
    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField(L10n.t("搜索会话"), text: $searchText)
                .layoutDebug("S9", text: LayoutDebug.font(.body))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 36)
                .pocketSystemGlassField(cornerRadius: 18)
                .accessibilityIdentifier("session-search-field")
            Button {
                searchFocused = false
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .pocketSystemGlassCircle(size: 36)
            }
            .accessibilityLabel(L10n.t("搜索会话"))
            .accessibilityIdentifier("session-search-button")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    var body: some View {
        List {
            if model.isDemoMode && !hideDemoBanner {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("演示模式")).font(.footnote.weight(.semibold))
                            Text(L10n.t("示例数据，未连接电脑")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.t("退出")) { model.exitDemoMode() }.font(.footnote)
                    }
                }
            }
            if let error = model.connection.errorMessage {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                        Spacer(minLength: 0)
                        Button(L10n.t("重试")) {
                            Task { await model.loadSessions() }
                        }
                        .font(.footnote)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                    if model.connection.addressNeedsRescan {
                        Button(L10n.t("重新选择连接地址")) { model.disconnect() }
                    }
                }
            }
            if model.sessionStore.sessions.isEmpty && !model.sessionStore.isLoadingSessions {
                ContentUnavailableView(L10n.t("还没有会话"), systemImage: "bubble.left.and.bubble.right", description: Text(L10n.t("创建会话后即可开始对话。")))
                    .layoutDebug("S10")
                    .listRowSeparator(.hidden)
            } else if filteredGroups.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(L10n.t("没有匹配的会话"), systemImage: "magnifyingglass", description: Text(L10n.t("换个词再搜。")))
                    .layoutDebug("S10")
                    .listRowSeparator(.hidden)
            }
            ForEach(filteredGroups) { group in
                if !group.title.isEmpty {
                    // 必须用 Button：onTapGesture 会吃掉 contextMenu 的长按（实测菜单不弹）。
                    // 拖动已改为面板方案，不需要再为 drag 让路。
                    Button {
                        toggleGroup(group.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text(group.title)
                                // 原来是 .caption（12pt），真机看着偏小；升到 .subheadline（15pt）。
                                // 用语义字号而不是 .system(size:15)，跟随用户字号设置。
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                                .layoutDebug("S3", text: LayoutDebug.font(.subheadline))
                            if isCollapsed(group.id) {
                                Text("\(group.sessions.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .layoutDebug("S5", text: LayoutDebug.font(.caption2))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isCollapsed(group.id) ? -90 : 0))
                                .layoutDebug("S4", text: LayoutDebug.font(.caption2))
                        }
                        .contentShape(Rectangle())
                        .layoutDebug("S1", text: LayoutDebug.font(.caption))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    // 长按分组标题拖动调整工作区顺序。置顶组与「其他会话」不是工作区，不参与。
                    // 长按分组头 → 调整顺序（不用直接拖：List 行内的 drag/drop 与 tap/滚动冲突，实测不可用）。
                    .contextMenu {
                        if isWorkspaceGroup(group) {
                            Button {
                                openWorkspaceReorder()
                            } label: {
                                Label(L10n.t("调整工作区顺序"), systemImage: "arrow.up.arrow.down")
                            }
                        }
                    }
                }
                if !isCollapsed(group.id) {
                ForEach(group.sessions) { session in
                let finishedAwaiting = model.finishedAwaitingSessionIds.contains(session.sessionId)
                let isPinned = model.sessionStore.pinnedSessionIds.contains(session.sessionId)
                NavigationLink(value: session) {
                    HStack(spacing: 12) {
                        Image(systemName: session.running ? "ellipsis.bubble.fill" : (finishedAwaiting ? "bell.badge.fill" : "bubble.left"))
                            .foregroundStyle(session.running ? .green : (finishedAwaiting ? .red : .secondary))
                            .frame(width: 28)
                            .layoutDebug("S2")
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(session.displayTitle).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                                    .layoutDebug("S7", text: LayoutDebug.font(.body))
                                if isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundStyle(PocketChrome.brandText)
                                        .accessibilityLabel(L10n.t("已置顶"))
                                }
                            }
                            Text(finishedAwaiting ? L10n.t("已完成，等待你的回复")
                                 : (session.running ? L10n.t("正在运行") : L10n.t("对话记录")))
                                .font(.caption)
                                .layoutDebug("S8", text: LayoutDebug.font(.caption))
                                .foregroundStyle(finishedAwaiting ? Color.red : .secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if session.running {
                            Circle().fill(.green).frame(width: 7, height: 7)
                        } else if finishedAwaiting {
                            Circle().fill(.red).frame(width: 7, height: 7)
                        }
                    }
                    // S6 = 会话行整体。行高 = 标题 + 状态两行 + 上下各 7pt；
                    // 觉得「某一类会话行偏高」时报 S6 就能定位。
                    .layoutDebug("S6", gap: "上下 7pt", text: LayoutDebug.font(.body))
                    // 行高：标题 + 状态两行本身约 42 点，上下各留 7 点 → 约 56 点。
                    // 不再吃 List 默认的上下各 11 点（那样会到 68 点左右，显得松）。
                    // 大字号下高度仍随文字自动长，不写死。
                    .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                }
                .listRowBackground(isPinned ? Color(red: 0.08, green: 0.48, blue: 0.37).opacity(0.05) : Color.clear)
                // 整行读成一句：标题 + 状态（+ 置顶）。红绿点只是视觉，状态必须有文字。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AccessibilityLabels.sessionRow(
                    title: session.displayTitle,
                    status: finishedAwaiting ? L10n.t("已完成，等待你的回复")
                          : (session.running ? L10n.t("正在运行") : L10n.t("对话记录")),
                    isPinned: isPinned
                ))
                .contextMenu {
                    Button {
                        Task { await model.togglePin(session) }
                    } label: {
                        Label(model.sessionStore.pinnedSessionIds.contains(session.sessionId) ? L10n.t("取消置顶") : L10n.t("置顶"),
                              systemImage: model.sessionStore.pinnedSessionIds.contains(session.sessionId) ? "pin.slash" : "pin")
                    }
                    Button {
                        // 等 contextMenu 收起再弹 sheet，避免转场叠加。
                        let target = session
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            renamingSession = target
                        }
                    } label: {
                        Label(L10n.t("重命名"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Task { await model.archive(session) }
                    } label: {
                        Label(L10n.t("归档"), systemImage: "archivebox")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        Task { await model.togglePin(session) }
                    } label: {
                        Label(model.sessionStore.pinnedSessionIds.contains(session.sessionId) ? L10n.t("取消置顶") : L10n.t("置顶"),
                              systemImage: "pin")
                    }
                    .tint(Color(red: 0.08, green: 0.48, blue: 0.37))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await model.archive(session) }
                    } label: {
                        Label(L10n.t("归档"), systemImage: "archivebox")
                    }
                }
                }
                }
            }
        }
        .listStyle(.plain)
        .overlay { if model.sessionStore.isLoadingSessions { ProgressView() } }
        .overlay(alignment: .bottom) {
            if model.lastArchivedSession != nil {
                archiveUndoBanner
            }
        }
        .refreshable { await model.loadSessions() }
        .safeAreaInset(edge: .bottom) { searchBar }
        // 搜索框在底部固定条里，不在 List 内部，scrollDismissesKeyboard 管不到；
        // 改听 List 自己的滚动阶段：一开滚就收键盘。
        .pocketScrollPhaseChange { phase in
            // 只要不是「静止」，就说明用户开始滚了 → 收键盘。
            guard searchFocused, phase != .idle else { return }
            searchFocused = false
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // 截图模式不显示「退出演示」——那是调试入口，不该进宣传图。
                if model.isDemoMode, !DebugLaunch.storeShots {
                    Button { model.exitDemoMode() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.t("退出演示模式"))
                }
            }
            // 显式指定 SF Pro（无衬线）而不是靠继承：换语言/换系统字号后
            // 导航标题的默认样式会变，品牌标题要保持一致。
            ToolbarItem(placement: .principal) {
                Text("DSH Pocket")
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .tracking(0.2)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                // 完成提醒开关已移到「设置」里，这里不再放第二个入口。
                Button { showingPlugins = true } label: {
                    Image(systemName: "puzzlepiece.extension")
                }
                .accessibilityLabel(L10n.t("插件"))
                Button { openWorkspacePicker() } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                }
                .pocketSystemGlassButton()
                .accessibilityLabel(L10n.t("新建会话"))
            }
        }
        .sheet(isPresented: $showingPlugins) {
            // 地址无效时不打开（例如还没连上），避免弹一个必然失败的空白页。
            if let baseURL = try? ConnectionModel.serverURL(from: model.connection.serverAddress) {
                PluginPanelSheet(baseURL: baseURL)
            }
        }
        .sheet(isPresented: $showsWorkspacePicker) {
            WorkspacePickerSheet(
                workspaces: WorkspaceParsing.orderedForPicker(workspaceOptions, defaultId: defaultWorkspaceId),
                preselectedId: selectedWorkspaceIdForPicker,
                isLoading: isLoadingWorkspaces,
                onCancel: { showsWorkspacePicker = false },
                onCreate: { chosen in
                    showsWorkspacePicker = false
                    if let chosen { lastWorkspaceId = chosen }
                    Task { await model.createSession(in: chosen) }
                }
            )
        }
        .sheet(isPresented: $showsWorkspaceReorder) {
            WorkspaceReorderSheet(
                workspaces: reorderOptions,
                onMove: { fromId, beforeId in
                    Task { await model.moveWorkspace(fromId, before: beforeId) }
                },
                onClose: { showsWorkspaceReorder = false }
            )
        }
        // 品牌名，不翻译：进本地化表反而会让各语言显示不同名字。
        .navigationTitle("DSH Pocket")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $renamingSession) { session in
            RenameSessionSheet(
                originalTitle: session.displayTitle,
                onSave: { newTitle in
                    renamingSession = nil
                    Task { await model.rename(session, to: newTitle) }
                },
                onCancel: { renamingSession = nil }
            )
        }

        .navigationDestination(for: PocketSession.self) { session in
            ConversationView(model: model, session: session)
                // onAppear 在部分 iOS 版本上不会对同一目的地类型重复触发，
                // 用 task(id:) 确保进入/切换会话时一定重新打开对应会话。
                .task(id: session.sessionId) {
                    // 可见会话由模型的 open() 维护，视图不再直接写。
                    model.open(session)
                }
                .onAppear { ConversationViewLifetime.liveCount += 1 }
                .onDisappear {
                    ConversationViewLifetime.liveCount = max(0, ConversationViewLifetime.liveCount - 1)
                    TextSelectionDismisser.clear()
                    model.leave(session)
                }
        }
        .task {
            await model.loadSessions(silently: !model.sessionStore.sessions.isEmpty)
            // 预加载工作区：等列表出来后再拉，不挡首屏。
            // 连接刚就绪时首次握手容易失败，这里赶在用户点开设置/新建之前先试一次，
            // 失败也无所谓——打开面板时还会再试。
            if model.workspaces.isEmpty {
                _ = await model.loadWorkspaces()
            }
#if DEBUG
            if !didAutoOpen, let id = DebugLaunch.sessionId,
               let session = model.sessionStore.sessions.first(where: { $0.sessionId == id }) {
                didAutoOpen = true
                model.sessionStore.navigationPath = [session]
            }
#endif
        }
    }

    /// 点 + ：先读工作区再弹选择器。
    ///
    /// 读列表失败不阻断：选择器会显示「没读到工作区」并允许直接创建（落默认工作区）。
    /// 打开排序面板：按会话列表当前的分组顺序传入，用户看到的就是现在的样子。
    private func openWorkspaceReorder() {
        let orderedPaths = filteredGroups.filter { !$0.isPinned }.map(\.id)
        let byPath = Dictionary(model.workspaces.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        reorderOptions = orderedPaths.compactMap { byPath[$0] } + model.workspaces.filter { w in
            !orderedPaths.contains(w.path)
        }
        showsWorkspaceReorder = true
    }

    private func openWorkspacePicker() {
        showsWorkspacePicker = true
        isLoadingWorkspaces = true
        workspaceOptions = []
        Task {
            let list = await model.loadWorkspaces()
            let fallbackDefault = await model.defaultWorkspaceId()
            await MainActor.run {
                workspaceOptions = list
                defaultWorkspaceId = fallbackDefault ?? ""
                isLoadingWorkspaces = false
            }
        }
    }

    /// 选择器默认勾选哪一项。
    ///
    /// 直接取排序后的第一项：`orderedForPicker` 保证默认工作区在第一位，
    /// 所以不需要再依赖 `defaultWorkspaceId` 是否取到（它来自另一个 RPC，可能失败）。
    /// 曾经因为 `defaultWorkspaceId` 为空而走不到「勾选默认工作区」分支，实测未勾选。
    private var selectedWorkspaceIdForPicker: String? {
        WorkspaceParsing.orderedForPicker(workspaceOptions, defaultId: defaultWorkspaceId).first?.workspaceId
    }

    /// 该分组是不是一个真实工作区（置顶组和「其他会话」不是）。
    private func isWorkspaceGroup(_ group: ConnectionModel.SessionGroup) -> Bool {
        !group.isPinned
            && group.id != SessionGrouping.otherGroupId
            && model.workspaces.contains { $0.path == group.id }
    }

    /// 把一个工作区拖到另一个工作区之前。
    ///
    /// 分组 id 是 cwd 路径，`workspace/insertBefore` 要的是 workspaceId，这里做一次映射。
    private func handleWorkspaceDrop(from: String, to: String) {
        guard from != to else { return }
        guard let fromWorkspace = model.workspaces.first(where: { $0.path == from }),
              let toWorkspace = model.workspaces.first(where: { $0.path == to }) else { return }
        Task { await model.moveWorkspace(fromWorkspace.workspaceId, before: toWorkspace.workspaceId) }
    }
}
