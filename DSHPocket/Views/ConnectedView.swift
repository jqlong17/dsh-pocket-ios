// ConnectedView

import SwiftUI
import Security
import Textual
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
    @State private var showingDisconnectConfirm = false
    @AppStorage("dsh-pocket.collapsed-groups") private var collapsedGroupsRaw = ""
    @State private var renamingSession: PocketSession?
    @State private var renameDraft = ""
    @State private var didAutoOpen = false
    @State private var searchText = ""
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
                        Button("重新选择连接地址") { model.disconnect() }
                    }
                }
            }
            if model.sessionStore.sessions.isEmpty && !model.sessionStore.isLoadingSessions {
                ContentUnavailableView(L10n.t("还没有会话"), systemImage: "bubble.left.and.bubble.right", description: Text(L10n.t("创建会话后即可开始对话。")))
                    .listRowSeparator(.hidden)
            } else if filteredGroups.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(L10n.t("没有匹配的会话"), systemImage: "magnifyingglass", description: Text(L10n.t("换个词再搜。")))
                    .listRowSeparator(.hidden)
            }
            ForEach(filteredGroups) { group in
                if !group.title.isEmpty {
                    Button {
                        toggleGroup(group.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                            if isCollapsed(group.id) {
                                Text("\(group.sessions.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isCollapsed(group.id) ? -90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(session.displayTitle).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
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
                        renamingSession = session
                        renameDraft = session.displayTitle
                    } label: {
                        Label(L10n.t("重命名"), systemImage: "pencil")
                    }
                    Button {
                        Task { await model.togglePin(session) }
                    } label: {
                        Label(model.sessionStore.pinnedSessionIds.contains(session.sessionId) ? L10n.t("取消置顶") : L10n.t("置顶"),
                              systemImage: model.sessionStore.pinnedSessionIds.contains(session.sessionId) ? "pin.slash" : "pin")
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
        .onScrollPhaseChange { _, phase in
            guard searchFocused else { return }
            switch phase {
            case .tracking, .interacting, .decelerating:
                searchFocused = false
            default:
                break
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if model.isDemoMode {
                    Button { model.exitDemoMode() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("退出演示模式")
                } else {
                    Button { showingDisconnectConfirm = true } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityLabel(L10n.t("断开连接"))
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.toggleCompletionAlerts() } label: {
                    Image(systemName: model.completionAlertsEnabled ? "bell" : "bell.slash")
                }
                .accessibilityLabel(model.completionAlertsEnabled ? "关闭完成提醒" : "开启完成提醒")
                Button { Task { await model.createSession() } } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                }
                .pocketSystemGlassButton()
                .accessibilityLabel("新建会话")
            }
        }
        .navigationTitle(L10n.t("会话"))
        .alert(L10n.t("重命名会话"), isPresented: Binding(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        ), presenting: renamingSession) { session in
            TextField(L10n.t("会话名称"), text: $renameDraft)
            Button(L10n.t("保存")) {
                Task { await model.rename(session, to: renameDraft) }
                renamingSession = nil
            }
            Button(L10n.t("取消"), role: .cancel) { renamingSession = nil }
        } message: { _ in
            Text(L10n.t("会同步到电脑端的会话标题。"))
        }
        .alert(L10n.t("断开与电脑的连接？"), isPresented: $showingDisconnectConfirm) {
            Button(L10n.t("断开连接"), role: .destructive) { model.disconnect() }
            Button(L10n.t("取消"), role: .cancel) {}
        } message: {
            Text(L10n.t("断开后需要重新扫码配对（或输入访问密码）才能再次连接。"))
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
#if DEBUG
            if !didAutoOpen, let id = DebugLaunch.sessionId,
               let session = model.sessionStore.sessions.first(where: { $0.sessionId == id }) {
                didAutoOpen = true
                model.sessionStore.navigationPath = [session]
            }
#endif
        }
    }
}
