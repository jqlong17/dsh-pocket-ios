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
    /// 自动贴底的最小间隔：行高变化会连着触发好几次（消息追加 → 过程行插入 →
    /// Markdown 异步渲染完成），每次都 scrollTo 就是用户看到的「发送时抖一下」。
    @State private var lastAutoScrollAt = Date.distantPast
    /// 手指正在拖动列表。拖动期间一律不自动贴底，否则用户上滑会被按住。
    @State private var userDragging = false
    /// 这次拖动的方向。往上带就要立刻停止跟随，不能因为还贴着底又把跟随打开。
    @State private var dragIntent: ScrollDragIntent = .none
    /// 用户这次会话里是否上划过。上划是"我要看历史"的意图，物理位置回弹到 0 也不该撤销它；
    /// 只有下划或点「回到底部」才清掉。
    @State private var hasSwipedUp = false
    /// 分页加载冷却，避免滚动到顶部时连续翻页。
    @State private var olderCooldownUntil = Date.distantPast
    /// 触发加载时是否已经贴在最顶部：此时加载完直接展示新一页，不做位置锚定。
    @State private var olderLoadWasAtTop = false
    @State private var showingJobs = false
    /// DEBUG 自动化：`DSH_DEV_OPEN=plugins` 时启动就弹出插件面板，
    /// 让截图/端到端验证不必人工点。正式包里恒为 false（见 ConnectionModel.debugOpenPlugins）。
    @State private var showingPlugins = ConnectionModel.debugOpenPlugins
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @FocusState private var composerFocused: Bool
    /// 复制后的短暂提示文字（2 秒消失）。nil 表示不显示。
    @State private var copiedToast: String?
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

    /// 最近几条消息保持完整渲染，其余只做纯文本摘要。
    ///
    /// 这是**正式行为**（2026-11-21 用户拍板，不再作为实验）。
    /// 依据：他明确只关心最近几条；实测精简后滚动体感明显更顺。
    private static let fullRenderRecentCount = 3

    /// 这条消息是否属于「更早的历史」（走精简渲染）。
    ///
    /// 按**消息**而不是按时间/顺序：工具步骤不占「条数」，避免把最新 3 条
    /// 全算成 step group 而导致最新回复也被降级。
    private func isCompactMessage(_ entry: TimelineEntry) -> Bool {
        guard let messageId = entry.message?.id else { return false }
        let recentIds = messagesRecentFirst.prefix(Self.fullRenderRecentCount).map(\.id)
        return !recentIds.contains(messageId)
    }

    /// 消息按「新的在前」排列的 ID（只算消息，不含 process 行）。
    private var messagesRecentFirst: [PocketMessage] {
        model.messages.sorted { left, right in
            let l = model.displaySortKey(for: left)
            let r = model.displaySortKey(for: right)
            if l != r { return l > r }
            return (left.sequence ?? 0) > (right.sequence ?? 0)
        }
    }

    private var entries: [TimelineEntry] {
        guard isSwitchedToSession else { return [] }
        // 计时：把「一次重排要多久」量化出来，否则「卡不卡」只能凭感觉。
        let renderStarted = CFAbsoluteTimeGetCurrent()
        defer {
            model.lastRenderMs = (CFAbsoluteTimeGetCurrent() - renderStarted) * 1000
            model.lastRenderMessageCount = model.messages.count
            model.lastRenderStepGroupCount = model.stepGroups.count
        }
        // 排序规则在 DSHKit（可测）；这里只负责把元素映射成排序键、再映射回来。
        var byID: [String: TimelineEntry] = [:]
        var keys: [TimelineSortKey] = []
        for message in model.messages {
            let entry = TimelineEntry(id: message.id,
                                      sortKey: model.displaySortKey(for: message),
                                      sequence: message.sequence,
                                      message: message, group: nil, failure: nil)
            byID[entry.id] = entry
            keys.append(TimelineSortKey(id: entry.id, sortKey: entry.sortKey, sequence: entry.sequence,
                                        isMessage: true, isPending: message.isPending,
                                        localOrder: message.localOrder))
        }
        for group in model.stepGroups {
            let entry = TimelineEntry(id: group.id, sortKey: group.sequence, sequence: group.sequence,
                                      message: nil, group: group, failure: nil)
            byID[entry.id] = entry
            keys.append(TimelineSortKey(id: entry.id, sortKey: entry.sortKey,
                                        sequence: entry.sequence, isMessage: false))
        }
        for failure in model.turnFailures {
            let entry = TimelineEntry(id: failure.id, sortKey: failure.sequence, sequence: failure.sequence,
                                      message: nil, group: nil, failure: failure)
            byID[entry.id] = entry
            keys.append(TimelineSortKey(id: entry.id, sortKey: entry.sortKey,
                                        sequence: entry.sequence, isMessage: false))
        }
        return TimelineAssembly.ordered(keys).compactMap { byID[$0.id] }
    }

    /// 离开底部之后到达的助手回复条数（用户自己的消息不算）。
    private var unreadReplies: Int {
        guard let mark = unreadSinceSequence else { return 0 }
        // 计数规则在 DSHKit（可测）：用户消息与待发都不算。
        return UnreadCounter.replies(after: mark, messages: model.messages.map {
            (isUser: $0.isUser, isPending: $0.isPending, sequence: $0.sequence)
        })
    }

    /// 消息列表的垂直节奏：同人连续 8、换角色 18、过程行相邻 10、turn 切换 24。
    private static func messageSpacing(previous: TimelineEntry, current: TimelineEntry) -> CGFloat {
        // 节奏规则在 DSHKit（可测）：同人 8、换角色 18、过程行/失败卡 10。
        CGFloat(TimelineSpacing.between(
            previousIsGroup: previous.group != nil || previous.failure != nil,
            currentIsGroup: current.group != nil || current.failure != nil,
            previousIsUser: previous.message?.isUser,
            currentIsUser: current.message?.isUser
        ))
    }

    private var canSend: Bool {
        // 发送中必须禁止再点：`sendMessage` 在上一条未完成时是**直接丢弃**新消息的
        // （压测实测连发 8 条只成功 1 条）。置灰让用户明确知道要等，
        // 而不是以为发了其实没发。
        guard !model.isSending else { return false }
        return !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !model.draftImages.isEmpty
    }

    /// 复制成功：一次轻震动 + 一条「已复制」。
    private func showCopied() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(PocketMotion.animation(.easeOut(duration: 0.2))) {
            copiedToast = L10n.t("已复制")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 连接状态与错误提示已拆到 ConversationStatusViews.swift。
            ConversationStatusBanner(model: model)

            ScrollViewReader { proxy in
                ScrollView {
                    // 用 VStack，**不要换 LazyVStack**（2026-11-21 再次实验验证）。
                    //
                    // 实验过程与结论：
                    // - 动机：帧率埋点显示滚动 21-25ms/帧（40-48fps），数据层只 0.1ms，
                    //   怀疑是「24 条视图全部参与合成」。同赛道 Orbis 用 LazyVStack 跑富文本聊天。
                    // - 实测：换成 LazyVStack 后**滚动出现明显异常**（行重叠/跳动），
                    //   与 2026-11 首次踩到的一致；且帧率并未改善到 60fps。
                    // - 原因推断：`Textual` 的 Markdown 行高度与「容器实际宽度」耦合，
                    //   LazyVStack 按缓存高度布局，宽度/内容变化时缓存失效导致错位。
                    //   Orbis 能用是因为它自己算 row 高度（`transcript.rows` 预分组 + 固定行）。
                    //
                    // 所以：**要虚拟化就得像 Orbis 那样自己做行高**，不能直接换容器。
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
                                // 只有「最近 3 条消息」跑完整 Markdown，更早的降级成纯文本。
                                // 用户明确说不关注更早的（2026-11-21）；实测滚动时每帧 20ms，
                                // 富文本行数是主要成本，压到常数级就能回到 60fps。
                                MessageRow(message: message, model: model, isCompact: isCompactMessage(entry))
                                    .id(entry.id).padding(.top, topGap)
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
                        // 底部留白：滚动是把这个锚点贴到视口底部，所以留白必须长在锚点自己身上。
                        // 靠外层 padding 会被滚出屏幕，视觉上就是最后一条消息贴着输入栏（踩过）。
                        Color.clear.frame(height: Self.bottomBreathingRoom).id(Self.bottomAnchorID)
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
                    // 节流：一次发送会连着触发 3 次左右的高度变化（消息追加、过程行插入、
                    // Markdown 渲染完成）。不节流就是连续三次 scrollTo，视觉上就是「抖一下」。
                    // 120ms 足够让最后那次高度变化也能被追上。
                    let now = Date()
                    guard now.timeIntervalSince(lastAutoScrollAt) >= 0.12 else { return }
                    lastAutoScrollAt = now
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
                                hasSwipedUp = true
                            } else if value.translation.height < -2 {
                                dragIntent = .down
                                hasSwipedUp = false
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
                    // 压测：连发 N 条，验证顺序与丢失（每条间隔 30ms，远快于一次发送的往返）。
                    if DebugLaunch.sendBurst > 0 {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(600))
                            for index in 0..<DebugLaunch.sendBurst {
                                // 模拟真实 UI：按钮在发送中是置灰的，所以这里也要等，
                                // 否则测的是「程序化硬闯发送中的锁」，不是用户能触发的路径。
                                while self.model.isSending {
                                    try? await Task.sleep(for: .milliseconds(50))
                                }
                                self.model.draft = "连发测试 #\(index + 1)"
                                self.model.sendMessage()
                                try? await Task.sleep(for: .milliseconds(30))
                            }
                        }
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
                // 系统级「用户正在滚动」信号。DragGesture 有 6pt 门槛，
                // 而"轻微上划"（3-5pt）触发不了它 —— 那正是「滑一下就被弹回」漏掉的一段。
                .onScrollPhaseChange { _, newPhase in
                    switch newPhase {
                    case .interacting:
                        // 手指一碰列表就说明意图是"看别处"，立即停止跟随。
                        hasSwipedUp = true
                        followsLatest = false
                        scrollGeneration &+= 1
                        userDragging = true
                    case .idle:
                        userDragging = false
                    default:
                        break
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
                                                     followsLatest: followsLatest,
                                                     hasSwipedUp: hasSwipedUp) {
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
                            hasSwipedUp = false
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
            // 问答卡 / 生成状态 / 补发进度已拆到 ConversationStatusViews.swift。
            ConversationActivityBar(model: model)
            Divider()
            inputBar
            }
        }
        .navigationTitle(model.currentConversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PluginToolbarButton { showingPlugins = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // 菜单项已拆到 ConversationMoreMenu.swift。
                ConversationMoreMenu(model: model,
                                     showingModelPicker: $showingModelPicker,
                                     onCopied: { _ in showCopied() },
                                     onShowJobs: { showingJobs = true })
            }
        }
        // 复制只给一条短暂提示，不打断操作。
        // 之前是 alert：要用户点「好」，而复制是高频小动作，弹窗太重。
        .overlay(alignment: .top) {
            if let copiedToast {
                Text(copiedToast)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        // id 变化会取消上一次的计时，连续复制不会互相打断。
        .task(id: copiedToast) {
            guard copiedToast != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(PocketMotion.animation(.easeOut(duration: 0.2))) {
                copiedToast = nil
            }
        }
        .sheet(isPresented: $showingJobs) {
            JobsSheet(model: model)
        }
        .sheet(isPresented: $showingPlugins) {
            // 地址无效时不打开面板（例如还没连上），避免弹一个必然失败的空白页
            if let baseURL = try? ConnectionModel.serverURL(from: model.connection.serverAddress) {
                PluginPanelSheet(baseURL: baseURL)
            }
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
            // 发送方式偏好：设置页和「更多」菜单都读它，进会话时同步一次。
            await model.loadBusyEnterPreference()
        }
        .onAppear {
            // 只在这个页面测帧率——它是唯一会大量绘制富文本的地方。
            model.frameMonitor.start()
        }
        .onDisappear {
            model.frameMonitor.stop()
            composerFocused = false
            TextSelectionDismisser.clear()
            // 退出裁剪不在视图层做（onDisappear 在 NavigationStack 返回时不触发），
            // 统一放在 model.leave(session) 里。
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

    /// 输入栏已拆到 ComposerBar.swift（引用条/草稿图/输入行）。
    private var inputBar: some View {
        ComposerBar(model: model,
                    session: session,
                    showingPhotoPicker: $showingPhotoPicker,
                    showingCamera: $showingCamera,
                    focused: $composerFocused)
    }

    private static let bottomAnchorID = "conversation-bottom-anchor"
    /// 最后一条消息与输入栏之间的留白。原生消息类 App 也有这一段，不然会显得被裁掉。
    private static let bottomBreathingRoom: CGFloat = 20
    private static let topAnchorID = "conversation-top-anchor"
    /// 输入栏里加号、输入框、发送三者统一的高度。改一处，三者一起变。
    private static let composerControlHeight: CGFloat = 36

    private static func liveStateColor(_ state: LiveConnectionState) -> Color {
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

}
