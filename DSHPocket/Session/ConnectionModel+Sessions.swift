// 会话列表、历史和实时流

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

extension ConnectionModel {

    /// 用最新 session 列表更新 running 状态机，识别"运行中 → 已结束"的会话。
    @MainActor
    func detectSessionCompletions() {
        let latest = Dictionary(sessions.map { ($0.sessionId, $0.running) }, uniquingKeysWith: { first, _ in first })
        let completed = completionTracker.update(latest: latest)
        UserDefaults.standard.set(latest, forKey: Self.runningSnapshotKey)
        recordDiagnostic("可用会话刷新：\(latest.count) 个，完成事件 \(completed.count) 个")

        // 重新开始运行的会话不再算"等待回复"。
        for session in sessions where session.running {
            finishedAwaitingSessionIds.remove(session.sessionId)
        }

        guard !completed.isEmpty else { return }
        for sessionId in completed {
            guard let session = sessions.first(where: { $0.sessionId == sessionId }) else { continue }
            let viewing = visibleSessionId == sessionId && isAppActive
            if viewing {
                finishedAwaitingSessionIds.remove(sessionId)
            } else {
                finishedAwaitingSessionIds.insert(sessionId)
                if completionAlertsEnabled { playCompletionFeedback(for: session) }
            }
        }
        persistFinishedAwaiting()
    }

    @MainActor
    func markFinishedAwaitingRead(_ sessionId: String) {
        if finishedAwaitingSessionIds.remove(sessionId) != nil {
            persistFinishedAwaiting()
        }
    }

    @MainActor
    func toggleCompletionAlerts() {
        completionAlertsEnabled.toggle()
        UserDefaults.standard.set(completionAlertsEnabled, forKey: Self.completionAlertKey)
        if completionAlertsEnabled,
           ProcessInfo.processInfo.environment["DSH_NO_NOTIF_PROMPT"] != "1" {
            CompletionNotifier.shared.requestPermission()
            Task { await syncPushRegistration() }
        } else if let token = pushToken {
            Task { _ = try? await rpcClient.rpcAdapted("push.unregister", args: ["token": token]) }
        }
        recordDiagnostic("完成提醒：\(completionAlertsEnabled ? "开启" : "关闭")")
    }

    @MainActor
    func playCompletionFeedback(for session: PocketSession) {
        CompletionNotifier.shared.notify(sessionId: session.sessionId, title: session.displayTitle)
        // 通知被关闭时也有声音兜底。
        AudioServicesPlaySystemSound(1007)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        recordDiagnostic("完成提醒：\(session.displayTitle)")
    }

    @MainActor
    func persistFinishedAwaiting() {
        UserDefaults.standard.set(Array(finishedAwaitingSessionIds), forKey: Self.finishedAwaitingKey)
    }

    @MainActor
    func loadSessions(silently: Bool = false) async {
        if isDemoMode { return }
        guard !isLoadingSessions else { return }
        if !silently { isLoadingSessions = true }
        defer { isLoadingSessions = false }
        do {
            sessions = try await fetchSessions()
            syncSelectedSessionMetadata()
            detectSessionCompletions()
            errorMessage = nil
            recordDiagnostic("会话列表刷新：\(sessions.count) 个，隐藏归档 \(archivedSessionIds.count) 个")
            // 能拉到列表说明网络通了：把各会话的断网暂存按写入顺序一并补发。
            flushQueuedSends()
        } catch {
            // 处置规则在 DSHKit（可测）：取消→忽略、401→回连接页、地址失效→报错、
            // 抖动且已有列表→静默重试、其余→提示。
            let isCancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
            // 收到 401 时 `ConnectionError` 可能是 .invalidPin（适配层按「密码错」给的），
            // 必须用 isUnauthorized 统一判断，否则永远不会触发重新配对。
            let unauthorized = (error as? ConnectionError)?.isUnauthorized ?? false
            let transient = Self.isTransientNetworkError(error)
            let action = SessionListFailurePolicy.action(
                isCancelled: isCancelled,
                isUnauthorized: unauthorized,
                isStaleTunnel: isStaleTunnelError(error),
                isTransient: transient,
                isSilent: silently,
                hasExistingSessions: !sessions.isEmpty,
                message: transient ? "连接电脑超时，正在重试…" : "无法读取会话：\(error.localizedDescription)"
            )
            switch action {
            case .ignore:
                return
            case .reauthenticate:
                recordDiagnostic("会话列表 401：登录已失效")
                handleAuthExpired()
            case .showAddressError:
                recordDiagnostic("会话列表刷新失败：\(error.localizedDescription)")
                applyConnectError(error)
            case .retryQuietly:
                recordDiagnostic("会话列表刷新遇到网络抖动，保留当前列表")
            case .showMessage(let message):
                recordDiagnostic("会话列表刷新失败：\(error.localizedDescription)")
                errorMessage = message
                scheduleSessionListRetry()
            }
        }
    }

    /// 超时/断连这类抖动：自动退避重试，成功就把红字清掉。
    @MainActor
    func scheduleSessionListRetry() {
        sessionListRetryTask?.cancel()
        sessionListRetryTask = Task { [weak self] in
            for delay in [2.0, 4.0, 8.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                await self.loadSessions(silently: true)
                if await MainActor.run(body: { self.errorMessage == nil }) { return }
            }
        }
    }

    static func isTransientNetworkError(_ error: Error) -> Bool {
        DSHNetworkErrorPolicy.isTransient(error)
    }

    /// 拉列表并把归档/置顶写回 store（只读访问与解析在 SessionAPI）。
    func fetchSessions() async throws -> [PocketSession] {
        let listing = try await sessionAPI.fetchListing()
        archivedSessionIds = listing.archived
        pinnedSessionIds = listing.pinned
        return listing.sessions
    }

    func fetchWorkspaceSessionFlags() async throws -> (archived: Set<String>, pinned: [String]) {
        try await sessionAPI.fetchWorkspaceFlags()
    }

    /// 装配 SessionAPI 的依赖（幂等）。
    @MainActor
    func installSessionAPIProviders() {
        guard sessionAPI.providers == nil else { return }
        sessionAPI.providers = SessionAPI.Providers(
            client: { [weak self] in
                guard let self else { throw ConnectionError.invalidURL("") }
                return try self.rpcClient
            },
            socketURL: { [weak self] in
                guard let self,
                      let base = URL(string: self.serverAddress),
                      let url = Self.webSocketURL(from: base, path: "api/remote.mux") else {
                    throw ConnectionError.invalidURL(self?.serverAddress ?? "")
                }
                return url
            }
        )
    }

    /// 只保留最近打开过的几条会话内容，其余只留 ID（草稿另存在 DraftStore）。
    /// 原生不会把聊过的每条会话都摊在内存里；我们也别一直涨。
    @MainActor
    func trimRetainedConversations(keeping sessionId: String, limit: Int = ConversationCachePolicy.defaultLimit) {
        guard conversations.count > limit else { return }
        let active = activeConversation?.sessionId ?? sessionId
        let refs = conversations.values.map {
            CachedConversationRef(id: $0.sessionId, lastOpenedAt: $0.lastOpenedAt)
        }
        // 淘汰谁交给 DSHKit；当前会话和正在看的会话永不淘汰。
        let doomed = ConversationCachePolicy.evictions(from: refs,
                                                       keeping: [active, sessionId],
                                                       limit: limit)
        guard !doomed.isEmpty else { return }
        for id in doomed {
            guard let conversation = conversations[id] else { continue }
            conversation.liveTask?.cancel()
            conversation.fallbackTask?.cancel()
            conversation.coordinatorTask?.cancel()
            jobRoster.stop()
            conversations.removeValue(forKey: id)
        }
        recordDiagnostic("会话缓存回收 \(doomed.count) 条，剩 \(conversations.count) 条")
    }

    // MARK: 单条会话操作（实现在 SessionActions）

    @MainActor func rename(_ session: PocketSession, to rawTitle: String) async {
        await sessionActions.rename(session, to: rawTitle)
    }
    @MainActor func loadModelCatalog() async { await sessionActions.loadModelCatalog() }
    @MainActor func selectModel(_ option: ModelOption) async { await sessionActions.selectModel(option) }
    @MainActor func dismissArchiveUndo() { sessionActions.dismissArchiveUndo() }
    @MainActor func undoArchive() async { await sessionActions.undoArchive() }
    @MainActor func togglePin(_ session: PocketSession) async { await sessionActions.togglePin(session) }
    @MainActor func archive(_ session: PocketSession) async { await sessionActions.archive(session) }
    @MainActor func createSession() async { await sessionActions.createSession() }

    /// 装配会话操作的依赖（幂等）。
    @MainActor
    func installSessionActionProviders() {
        guard sessionActions.providers == nil else { return }
        sessionActions.providers = SessionActions.Providers(
            client: { [weak self] in
                guard let self else { throw ConnectionError.invalidURL("") }
                return try self.rpcClient
            },
            store: sessionStore,
            isDemoMode: { [weak self] in self?.isDemoMode ?? false },
            reportError: { @MainActor [weak self] message in self?.errorMessage = message },
            record: { @MainActor [weak self] message in self?.recordDiagnostic(message) },
            reload: { @MainActor [weak self] in await self?.loadSessions() },
            modelGroups: { [weak self] in self?.modelGroups ?? [] },
            setModelGroups: { @MainActor [weak self] groups in self?.modelGroups = groups },
            selectedModelLabel: { [weak self] in self?.selectedModelLabel },
            setSelectedModelLabel: { @MainActor [weak self] label in self?.selectedModelLabel = label },
            lastArchived: { [weak self] in self?.lastArchivedSession },
            setLastArchived: { @MainActor [weak self] session in self?.lastArchivedSession = session },
            open: { @MainActor [weak self] session in self?.open(session) }
        )
    }


    static func homeDirectory(for cwd: String) -> String {
        let parts = cwd.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0] == "Users" { return "/Users/\(parts[1])" }
        if parts.count >= 2, parts[0] == "home" { return "/home/\(parts[1])" }
        return "~"
    }

    /// 从历史记录里提取 steer 的 inbox rpcId（agent/inbox/spliced），用于确认发件箱。
    func inboxRpcIds(in records: [[String: Any]]) -> Set<String> {
        var ids = Set<String>()
        for record in records {
            guard let event = record["event"] as? [String: Any],
                  event["type"] as? String == "agent/inbox/spliced",
                  let data = event["data"] as? [String: Any],
                  let inserted = data["inserted"] as? [[String: Any]] else { continue }
            for item in inserted {
                if let rpcId = (item["source"] as? [String: Any])?["rpcId"] as? String, !rpcId.isEmpty {
                    ids.insert(rpcId.lowercased())
                }
            }
        }
        return ids
    }

    @MainActor
    func confirmInboxOutbox(in records: [[String: Any]]) {
        let ids = inboxRpcIds(in: records)
        guard !ids.isEmpty else { return }
        // 先登记为"已确认但消息体尚未落库"，mergeMessages 会保留本地 pending，
        // 等真实 user/message 出现再替换；否则消息会闪一下消失。
        acknowledgedSendRpcIds.formUnion(ids)
        confirmOutbox(rpcIds: ids)
        ackedSendRpcIds.subtract(ids)
        failedSendRpcIds.subtract(ids)
        if conversationError?.contains("服务端没有收到") == true { conversationError = nil }
        recordDiagnostic("历史中确认 steer 已送达（\(ids.count) 条）")
    }

    /// 不再按时间删除发件箱。未确认正文留到服务端历史确认，或用户取消发送。
    @MainActor
    func pruneStaleOutbox() {
        loadOutboxIfNeeded()
    }

    /// 消息展示排序键：服务端 seq 即唯一真相。
    /// 曾按 turn 区间把"生成中发送的用户消息"重排到本轮回复之后，但 steer 模式下这些消息
    /// 本身会打断当前轮、seq 就在回复之前；重排反而把用户消息和回复顺序弄反，故移除该启发式。
    func displaySortKey(for message: PocketMessage) -> Int {
        // 待发消息不能用 Int.max（会沉到「过程」行下面）；用发送时最后一条已确认消息的位置，
        // 这样它排在旧消息之后、发送之后产生的工具步骤之前。
        TimelineOrdering.sortKey(sequence: message.sequence,
                                 localSortKey: message.localSortKey,
                                 isPending: message.isPending)
    }
}
