// ConversationView

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


struct ConversationView: View {
    @Bindable var model: ConnectionModel
    let session: PocketSession
    /// 是否停在底部（followsLatest）：在底部才自动跟随新消息，否则只累计未读。
    @State private var isAtBottom = true
    /// 离开底部时的最后一条已确认序号。之后到达的助手回复才算未读。
    @State private var unreadSinceSequence: Int?
    /// 上一次已经播报过的未读数，避免同一条回复反复念。
    @State private var announcedUnread = 0
    /// 「回到底部」按钮的显示状态：延迟出现，避免发送后程序化滚动期间闪烁并盖住消息。
    @State private var scrollButtonVisible = false
    @State private var scrollButtonTask: Task<Void, Never>?
    /// 是否仍"跟随最新"：用户主动上滑后置 false；回到底部/点箭头后置 true。
    @State private var followsLatest = true
    /// 用户上滑时递增，用于让待执行的补滚任务失效。
    @State private var scrollGeneration = 0
    @State private var didAutoSend = false
    @State private var expandedGroupIDs: Set<String> = []
    @State private var loadingGroupIDs: Set<String> = []
    /// 展开/收起「过程」后短时间内抑制"自动贴底"，避免一点击就被拽到底部。
    @State private var suppressAutoScrollUntil = Date.distantPast
    /// 手指正在拖动列表。拖动期间一律不自动贴底，否则用户上滑会被按住。
    @State private var userDragging = false
    /// 这次拖动的方向。往上带就要立刻停止跟随，不能因为还贴着底又把跟随打开。
    @State private var dragIntent: ScrollDragIntent = .none
    /// 分页加载冷却，避免滚动到顶部时连续翻页。
    @State private var olderCooldownUntil = Date.distantPast
    /// 触发加载时是否已经贴在最顶部：此时加载完直接展示新一页，不做位置锚定。
    @State private var olderLoadWasAtTop = false
    @State private var showingJobs = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @FocusState private var composerFocused: Bool
    @State private var copiedLogPath: String?
    @State private var showingModelPicker = false

    private struct TimelineEntry: Identifiable {
        let id: String
        let sortKey: Int      // 展示排序键（排队消息会被推迟到 turn 结束之后）
        let sequence: Int     // 原始 seq，二级排序保证同一 turn 内排队消息的先后顺序
        let message: PocketMessage?
        let group: PocketStepGroup?
        let failure: TurnFailureNotice?
    }

    /// 是否已经切到本页要显示的会话。切换完成前不渲染，避免首帧闪出上一条的内容。
    private var isSwitchedToSession: Bool {
        model.activeSessionId == session.sessionId
    }

    private var entries: [TimelineEntry] {
        guard isSwitchedToSession else { return [] }
        var result: [TimelineEntry] = model.messages.map {
            TimelineEntry(id: $0.id, sortKey: model.displaySortKey(for: $0), sequence: $0.sequence, message: $0, group: nil, failure: nil)
        }
        for group in model.stepGroups {
            result.append(TimelineEntry(id: group.id, sortKey: group.sequence, sequence: group.sequence, message: nil, group: group, failure: nil))
        }
        for failure in model.turnFailures {
            result.append(TimelineEntry(id: failure.id, sortKey: failure.sequence, sequence: failure.sequence, message: nil, group: nil, failure: failure))
        }
        return result.sorted { lhs, rhs in
            if lhs.sortKey != rhs.sortKey { return lhs.sortKey < rhs.sortKey }
            // 同一排序键（同一 turn 内排队的多条消息）用原始 seq 保持发送先后。
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            switch (lhs.message, rhs.message) {
            case let (.some(l), .some(r)):
                if l.isPending != r.isPending { return !l.isPending }
                // 两条都在等地发送：按本地发送顺序，不要用随机 id。
                if l.localOrder != r.localOrder { return l.localOrder < r.localOrder }
                return l.id < r.id
            case (.some, nil):
                return true
            case (nil, .some), (nil, nil):
                return lhs.id < rhs.id
            }
        }
    }

    /// 离开底部之后到达的助手回复条数（用户自己的消息不算）。
    private var unreadReplies: Int {
        guard let mark = unreadSinceSequence else { return 0 }
        return model.messages.filter { !$0.isUser && !$0.isPending && $0.sequence > mark }.count
    }

    /// 消息列表的垂直节奏：同人连续 8、换角色 18、过程行相邻 10、turn 切换 24。
    private static func messageSpacing(previous: TimelineEntry, current: TimelineEntry) -> CGFloat {
        if previous.group != nil || current.group != nil || previous.failure != nil || current.failure != nil { return 10 }
        guard let prevMessage = previous.message, let currentMessage = current.message else { return 10 }
        if prevMessage.isUser != currentMessage.isUser { return 18 }
        return 8
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.draftImages.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.conversationError {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.red.opacity(0.06))
            }
#if DEBUG
            let showsDemoBanner = model.isDemoMode && !DebugLaunch.hideDemoBanner
#else
            let showsDemoBanner = model.isDemoMode
#endif
            if showsDemoBanner || (!model.isDemoMode && model.liveConnection != .connected) {
                HStack(spacing: 6) {
                    if model.isDemoMode {
                        Image(systemName: "play.circle").font(.caption2).foregroundStyle(.secondary)
                        Text(L10n.t("演示模式 · 示例数据，未连接电脑")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        Circle().fill(Self.liveStateColor(model.liveConnection)).frame(width: 6, height: 6)
                        Text(model.liveConnection.label).font(.caption2).foregroundStyle(.secondary)
                        if model.liveConnection.isDisconnected {
                            Button(L10n.t("重连")) { model.manualReconnect() }
                                .font(.caption2.weight(.semibold))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal).padding(.vertical, 4)
                .transition(.opacity)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    // 用 VStack 而非 LazyVStack：MarkdownUI/图片/表格行高度动态变化，
                    // LazyVStack 会缓存旧高度导致行重叠；会话窗口只有 30 条消息，直接布局代价可忽略。
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 1).id(Self.topAnchorID)
                        if model.isLoadingOlder {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text(L10n.t("加载更早消息…")).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                        }
                        if model.isLoadingConversation && model.messages.isEmpty && model.steps.isEmpty {
                            ProgressView().padding(.top, 36)
                        }
                        // 切换完成前不要显示空态，否则会闪一下「开始对话」。
                        if entries.isEmpty && !model.isLoadingConversation, isSwitchedToSession {
                            ContentUnavailableView(L10n.t("开始对话"), systemImage: "text.bubble", description: Text(L10n.t("发送第一条消息。")))
                        }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            let topGap = index == 0 ? 0 : Self.messageSpacing(previous: entries[index - 1], current: entry)
                            if let message = entry.message {
                                MessageRow(message: message, model: model).id(entry.id).padding(.top, topGap)
                            } else if let failure = entry.failure {
                                TurnFailureRow(failure: failure).id(entry.id).padding(.top, topGap)
                            } else if let group = entry.group {
                                ProcessRow(group: group, expanded: expandedGroupIDs.contains(group.id), loading: loadingGroupIDs.contains(group.id), model: model) {
                                    let plan = ProcessTogglePlan.make(
                                        isExpanded: expandedGroupIDs.contains(group.id),
                                        needsDetails: group.steps.contains { !$0.detailsLoaded }
                                    )
                                    // 展开会把这一行撑高。滚不滚、要不要拉正文，由 ProcessTogglePlan 决定。
                                    if !plan.followLatest { followsLatest = false }
                                    scrollGeneration &+= 1
                                    if plan.suppressAutoScroll > 0 {
                                        suppressAutoScrollUntil = Date().addingTimeInterval(plan.suppressAutoScroll)
                                    }
                                    if plan.opening {
                                        expandedGroupIDs.insert(group.id)
                                        if plan.loadDetails {
                                            loadingGroupIDs.insert(group.id)
                                            let target = group
                                            Task {
                                                await model.loadProcessDetails(for: target)
                                                loadingGroupIDs.remove(target.id)
                                            }
                                        }
                                    } else if plan.dropDetails {
                                        expandedGroupIDs.remove(group.id)
                                        model.dropProcessDetails(for: group)
                                    }
                                    if plan.scrollToRowTop {
                                        DispatchQueue.main.async {
                                            proxy.scrollTo(group.id, anchor: .top)
                                        }
                                    }
                                }.id(entry.id).padding(.top, topGap)
                            }
                        }
                        // 底部锚点：滚动到它比"最后一条消息"更可靠（能带上后面的过程行/占位）。
                        Color.clear.frame(height: 1).id(Self.bottomAnchorID)
                    }
                    .padding()
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ConversationHeightKey.self, value: geo.size.height)
                        }
                    )
                }
                .onPreferenceChange(ConversationHeightKey.self) { _ in
                    // 行高异步变化（Textual 表格/图片晚渲染）会让内容变高；只要仍在跟随最新，
                    // 就补一次贴底，避免"最后一条消息下方留出空白"。
                    // 展开/收起「过程」后的 0.5 秒内不贴底，否则点击会被拽到底部。
                    guard Date() >= suppressAutoScrollUntil else { return }
                    guard !userDragging else { return }
                    guard followsLatest else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                    }
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded {
                    composerFocused = false
                    TextSelectionDismisser.clear()
                })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            // 用户一旦主动拖动，立刻取消"刚进会话时的多次补滚"，不要跟手指抢滚动。
                            scrollGeneration &+= 1
                            userDragging = true
                            // 滑动方向：往上带 >2 点就算在读历史
                            if value.translation.height > 2 {
                                dragIntent = .up
                                followsLatest = false
                            } else if value.translation.height < -2 {
                                dragIntent = .down
                            }
                        }
                        .onEnded { _ in
                            // 手指抬起才允许恢复自动贴底；拖动期间任何贴底都会把用户按住。
                            userDragging = false
                            dragIntent = .none
                        }
                )
                // 视图刚出现时先补滚一次（打开会话的 tick 可能早于 onChange 订阅）。
                .onAppear {
                    // 进页面不再手动滚：ScrollView 已用 .defaultScrollAnchor(.bottom) 定位。
                    // 两者叠加会先手动滚一次、锚点再校正一次，肉眼就是「贴到超出底部」的过冲。
#if DEBUG
                    if DebugLaunch.expandSteps {
                        expandedGroupIDs = Set(model.stepGroups.map(\.id))
                    }
                    if DebugLaunch.scrollToTop {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            scrollGeneration &+= 1
                            proxy.scrollTo(Self.topAnchorID, anchor: .top)
                        }
                    }
#endif
                }
                // 打开会话、历史/快照到达：模型递增 tick，视图统一滚到底部。
                .onChange(of: model.focusComposerTick) { _, _ in
#if DEBUG
            if DebugLaunch.noFocus { return }
#endif
            composerFocused = true
        }
#if DEBUG
        .onChange(of: model.stepGroups.count) { _, _ in
            if DebugLaunch.expandSteps {
                expandedGroupIDs = Set(model.stepGroups.map(\.id))
            }
        }
#endif
        .onChange(of: model.scrollToBottomTick) { _, _ in
                    // 已经贴底就不用再滚：再滚一次会和 defaultScrollAnchor(.bottom) 叠加，出现过冲。
                    guard !isAtBottom else { return }
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: model.messages.count) { oldCount, newCount in
                    timingLog("ui_messages_changed old=\(oldCount) new=\(newCount)")
                    guard newCount != oldCount else { return }
                    if userDragging {
                        // 手指在滑：不抢滚动，未读由 unreadReplies 现算。
                        if unreadReplies > announcedUnread {
                            AccessibilityAnnouncer.announce(AccessibilityLabels.newReplyAnnouncement(unreadReplies: unreadReplies))
                            announcedUnread = unreadReplies
                        }
                        return
                    }
                    if followsLatest {
                        // 已在底部：跟着滚，不播报，交给 VoiceOver 正常读新内容。
                        scrollToBottom(proxy: proxy, force: true)
                    } else {
                        if unreadReplies > announcedUnread {
                            AccessibilityAnnouncer.announce(
                                AccessibilityLabels.newReplyAnnouncement(unreadReplies: unreadReplies))
                            announcedUnread = unreadReplies
                        }
                        if UnreadBadgePolicy.shouldShowBadge(assistantReplies: unreadReplies),
                           !scrollButtonVisible {
                            withAnimation(PocketMotion.animation(.easeOut(duration: 0.18))) { scrollButtonVisible = true }
                        }
                    }
                }
                .onChange(of: model.steps.count) { oldCount, newCount in
                    guard newCount != oldCount, Date() >= suppressAutoScrollUntil, !userDragging else { return }
                    if followsLatest { scrollToBottom(proxy: proxy, force: true) }
                }
                .onChange(of: model.olderLoadTick) { _, _ in
                    olderCooldownUntil = Date().addingTimeInterval(1.5)
                    // 已经在最顶部时：让新加载的一页直接出现在顶部（用户继续上滑即可看到更早内容）。
                    // 只有用户停在中间时，才把原来的首条消息锚回顶部，避免内容跳动。
                    if olderLoadWasAtTop {
                        olderLoadWasAtTop = false
                        return
                    }
                    guard let anchor = model.olderAnchorID else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, topOffset in
                    guard topOffset < 80,
                          model.hasMoreOlder,
                          !model.isLoadingOlder,
                          !model.messages.isEmpty,
                          Date() >= olderCooldownUntil else { return }
                    olderCooldownUntil = Date().addingTimeInterval(1.5)
                    olderLoadWasAtTop = topOffset <= 2
                    model.loadOlderMessages()
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height - geometry.containerSize.height - geometry.contentOffset.y
                } action: { _, distance in
                    guard Date() >= suppressAutoScrollUntil else { return }
                    // 判定全部交给 DSHKit：只有贴底才跟随，手指在屏上不抢。
                    let atBottom = ScrollFollowPolicy.isAtBottom(distanceFromBottom: distance)
                    switch ScrollFollowPolicy.action(distanceFromBottom: distance,
                                                     drag: userDragging ? dragIntent : .none,
                                                     followsLatest: followsLatest) {
                    case .follow:
                        isAtBottom = true
                        unreadSinceSequence = nil
                        announcedUnread = 0
                        followsLatest = true
                        scrollButtonTask?.cancel()
                        scrollButtonVisible = false
                    case .stopFollow:
                        scrollGeneration &+= 1
                        isAtBottom = false
                        // 记下离开底部那一刻的最后一条已确认序号，之后只数它的助手回复。
                        if unreadSinceSequence == nil {
                            unreadSinceSequence = model.messages
                                .filter { !$0.isPending }
                                .map(\.sequence)
                                .max()
                        }
                    case .pinToBottom:
                        scrollToBottom(proxy: proxy, force: true)
                    case .keep:
                        break
                    }
                    if !atBottom, !scrollButtonVisible {
                        scrollButtonTask?.cancel()
                        scrollButtonTask = Task { @MainActor in
                            // 只延迟一点点，避免还在拖动时闪出来。
                            try? await Task.sleep(for: .seconds(0.25))
                            guard !Task.isCancelled, !isAtBottom else { return }
                            withAnimation(PocketMotion.animation(.easeOut(duration: 0.18))) { scrollButtonVisible = true }
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
#if DEBUG
                    let hideScrollButton = DebugLaunch.hideDemoBanner
#else
                    let hideScrollButton = false
#endif
                    if scrollButtonVisible,
                       UnreadBadgePolicy.shouldShowBadge(assistantReplies: unreadReplies),
                       !entries.isEmpty, !hideScrollButton {
                        Button {
                            unreadSinceSequence = nil
                            isAtBottom = true
                            followsLatest = true
                            scrollButtonTask?.cancel()
                            scrollButtonVisible = false
                            scrollToBottom(proxy: proxy, force: true)
                        } label: {
                            HStack(spacing: 4) {
                                // 原生做法：离开底部就出现；有未读时把条数带上。
                                Image(systemName: "arrow.down")
                                    .font(.footnote.weight(.semibold))
                                if let badge = UnreadBadgePolicy.badgeText(for: unreadReplies) {
                                    Text(badge)
                                        .font(.caption2.weight(.semibold))
                                        .monospacedDigit()
                                }
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .accessibilityLabel(AccessibilityLabels.backToBottom(unreadReplies: unreadReplies))
                        .accessibilityIdentifier("back-to-bottom")
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                    }
                }
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
            if let question = model.pendingQuestion {
                UserQuestionCard(request: question, model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.isTurnRunning {
                // 生成状态放在输入栏上方左侧：等待时视线就在这里。
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(L10n.t("深度求索中")) · \(elapsed(since: model.turnStartedAt, now: context.date))")
                            .font(.caption)
                            .foregroundStyle(PocketChrome.brandText)
                            .monospacedDigit()
                    }
                    Spacer()
                    Button { Task { await model.cancelTurn() } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                            Text(L10n.t("停止"))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("停止生成")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .background(.background)
            }
            Divider()
            inputBar
            }
        }
        .navigationTitle(model.currentConversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                JobsToolbarButton { showingJobs = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = model.sessionAddress
                        copiedLogPath = model.sessionAddress
                    } label: {
                        Label(L10n.t("复制会话地址"), systemImage: "link")
                    }
                    Button {
                        if let path = model.sessionLogPath {
                            UIPasteboard.general.string = path
                            copiedLogPath = path
                        }
                    } label: {
                        Label(L10n.t("复制会话日志路径"), systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button {
                        showingModelPicker = true
                    } label: {
                        Label(model.selectedModelLabel.map { L10n.t("选择模型") + "：" + $0 } ?? L10n.t("选择模型"),
                              systemImage: "cpu")
                    }
                    Button {
                        UIPasteboard.general.string = model.diagnosticReport()
                        copiedLogPath = model.diagnosticReport()
                    } label: {
                        Label(L10n.t("复制诊断信息"), systemImage: "stethoscope")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(L10n.t("更多"))
            }
        }
        .alert(L10n.t("已复制"), isPresented: Binding(
            get: { copiedLogPath != nil },
            set: { if !$0 { copiedLogPath = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(copiedLogPath ?? "")
        }
        .sheet(isPresented: $showingJobs) {
            JobsSheet(model: model)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in model.addDraftImage(image) }.ignoresSafeArea()
        }
        // 菜单里只切换状态，真正的相册选择器挂在页面上。
        // 把 PhotosPicker 直接塞进 Menu 里，iOS 不会弹出选择器，表现为「点了没反应」。
        .photosPicker(isPresented: $showingPhotoPicker,
                      selection: $photoItems,
                      maxSelectionCount: 9,
                      selectionBehavior: .ordered,
                      matching: .images,
                      photoLibrary: .shared())
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerSheet(model: model)
        }
        .task {
            if model.modelGroups.isEmpty { await model.loadModelCatalog() }
        }
        .onDisappear {
            composerFocused = false
            TextSelectionDismisser.clear()
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                // 支持一次多选多张：按选择顺序逐张加载，全部加入草稿后清空选择状态。
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        model.addDraftImage(image)
                    }
                }
                photoItems = []
            }
        }
        .task {
#if DEBUG
            if DebugLaunch.quoteDemo {
                try? await Task.sleep(for: .seconds(1.5))
                if let target = model.messages.last(where: { !$0.isUser && !$0.isPending }) {
                    model.beginQuote(target)
                    if DebugLaunch.storeShots {
                        model.draft = LanguageStore.shared.isEnglish
                            ? "Change the button to Copy address, and shorten the pairing note."
                            : "按钮改成「复制地址」，配对说明再短一点。"
                    }
                }
            }
            if !didAutoSend, let text = DebugLaunch.sendText {
                didAutoSend = true
                if let path = DebugLaunch.attachPath {
                    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : documents.appendingPathComponent(path)
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) { model.addDraftImage(image) }
                }
                try? await Task.sleep(for: .seconds(2))
                model.draft = text
                model.sendMessage()
            }
#endif
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let quote = model.pendingQuote {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(L10n.t("引用")) \(quote.sender) · #\(quote.sequence)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PocketChrome.brandText)
                        Text(quote.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color(red: 0.08, green: 0.48, blue: 0.37)).frame(width: 3)
                    }
                    Spacer(minLength: 0)
                    Button { model.cancelQuote() } label: {
                        Image(systemName: "xmark.circle.fill").font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消引用")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if !model.draftImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.draftImages) { image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image.uiImage).resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Button {
                                    model.draftImages.removeAll { $0.id == image.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.callout)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                    }.padding(.horizontal).padding(.top, 6)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button { showingPhotoPicker = true } label: {
                        Label("相册", systemImage: "photo")
                    }
                    Button { showingCamera = true } label: {
                        Label("拍照", systemImage: "camera")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .pocketSystemGlassCircle(size: Self.composerControlHeight)
                }
                .accessibilityLabel("添加图片或拍照")
                TextField(L10n.t("发送消息"), text: $model.draft, axis: .vertical).lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: Self.composerControlHeight)
                    .pocketSystemGlassField(cornerRadius: Self.composerControlHeight / 2)
                    .accessibilityIdentifier("composer-field")
                Button {
                    composerFocused = false
                    model.sendMessage(in: session)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .pocketSystemGlassCircle(size: Self.composerControlHeight)
                }
                .disabled(!canSend)
                .accessibilityLabel("发送消息")
                .accessibilityIdentifier("send-button")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(.bar)
    }

    private static let bottomAnchorID = "conversation-bottom-anchor"
    private static let topAnchorID = "conversation-top-anchor"
    /// 输入栏里加号、输入框、发送三者统一的高度。改一处，三者一起变。
    private static let composerControlHeight: CGFloat = 36

    private static func liveStateColor(_ state: ConnectionModel.LiveConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        case .idle, .demo: return .gray
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, force: Bool = false) {
        // 手指在屏上不抢滚动；其余情况只认「在跟随」或显式要求。
        guard ScrollFollowPolicy.canAutoScroll(isDragging: userDragging,
                                              followsLatest: followsLatest,
                                              force: force) else { return }
        let generation = scrollGeneration
        // 一次定位（force 多补一帧）。不再有稳定期反复补滚。
        let delays: [Double] = force ? [0, 0.15] : [0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // 用户已上滑（generation 递增）或会话已切换：放弃这次补滚。
                guard generation == scrollGeneration else { return }
                guard force || followsLatest else { return }
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func elapsed(since start: Date?, now: Date) -> String {
        guard let start else { return "计算中" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}
