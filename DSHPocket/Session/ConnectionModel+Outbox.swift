// 发件箱和断网排队

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

enum HeldOfflineDelivery {
    case acked
    case stillOffline
    case auth
    case failed
}

extension ConnectionModel {

    func loadOutboxIfNeeded() { outbox.loadIfNeeded() }

    func persistOutbox() { outbox.persist() }

    @MainActor
    func addOutbox(sessionId: String, rpcId: String, text: String,
                   images: [PocketDraftImage] = []) {
        guard !text.isEmpty || !images.isEmpty else { return }
        // 图片一起落盘：数量与总大小按策略卡住，超了就只排文字并提示。
        var stored: [OutboxAttachment] = []
        if !images.isEmpty {
            let bytes = images.reduce(0) { $0 + $1.data.count }
            let withinMessage = OutboxAttachmentPolicy.canHold(imageCount: images.count, totalBytes: bytes)
            let withinBudget = OutboxAttachmentPolicy.fits(currentTotalBytes: OutboxImageStore.totalBytes(),
                                                           adding: bytes)
            if withinMessage && withinBudget {
                stored = OutboxImageStore.save(images, rpcId: rpcId)
            } else {
                recordDiagnostic("图片未排队：超出暂存上限（\(images.count) 张 / \(bytes) 字节）")
            }
        }
        outbox.append(OutboxEntry(id: rpcId.lowercased(), sessionId: sessionId, text: text,
                                  createdAt: Date().timeIntervalSince1970,
                                  attachments: stored))
    }

    /// 断网暂存写盘。正文在 `addOutbox` 时已经落盘，这里只补上「等联网一并发送」标记。
    @MainActor
    func markOutboxHeldOffline(rpcId: String) {
        updateOutbox(rpcId: rpcId) { entry in
            guard !entry.heldOffline || entry.sendFailed || entry.accepted else { return nil }
            entry.heldOffline = true
            entry.sendFailed = false
            entry.accepted = false
            return entry
        }
    }

    /// 非网络错误：正文留下，记下失败，不再当成断网暂存反复补发。
    @MainActor
    func markOutboxSendFailed(rpcId: String) {
        updateOutbox(rpcId: rpcId) { entry in
            guard entry.heldOffline || !entry.sendFailed || entry.accepted else { return nil }
            entry.heldOffline = false
            entry.sendFailed = true
            entry.accepted = false
            return entry
        }
    }

    @MainActor
    func markOutboxAccepted(rpcId: String) {
        updateOutbox(rpcId: rpcId) { entry in
            guard entry.heldOffline || entry.sendFailed || !entry.accepted else { return nil }
            entry.heldOffline = false
            entry.sendFailed = false
            entry.accepted = true
            return entry
        }
    }

    @MainActor
    func clearOutboxHeldOffline(rpcId: String) {
        updateOutbox(rpcId: rpcId) { entry in
            guard entry.heldOffline else { return nil }
            entry.heldOffline = false
            return entry
        }
    }

    @MainActor
    private func updateOutbox(rpcId: String, _ change: (inout OutboxEntry) -> OutboxEntry?) {
        outbox.update(rpcId: rpcId, change)
    }

    /// 打开会话或补回气泡时，把磁盘上的断网/失败标记灌进该会话的内存状态。
    @MainActor
    func applyOutboxFlags(to conversation: ConversationState, sessionId: String) {
        loadOutboxIfNeeded()
        for entry in outboxEntries where entry.sessionId == sessionId {
            let id = entry.id.lowercased()
            if entry.heldOffline { conversation.queuedRpcIds.insert(id) }
            if entry.sendFailed { conversation.failedRpcIds.insert(id) }
            if entry.accepted { conversation.ackedRpcIds.insert(id) }
        }
    }

    @MainActor
    func confirmOutbox(rpcIds: Set<String>) {
        outbox.remove(rpcIds: rpcIds)
    }

    /// 发件箱里已发出、但列表里没有对应消息的条目：补成 pending 气泡，避免"发了但看不见"。
    @MainActor
    func restoreMissingOutboxMessages() {
        guard !isDemoMode, let session = selectedSession else { return }
        loadOutboxIfNeeded()
        let representedRpcIds = Set(messages.compactMap(\.rpcId).map { $0.lowercased() })
        let missing = outboxEntries.filter {
            $0.sessionId == session.sessionId && (!$0.text.isEmpty || !$0.attachments.isEmpty)
                && !representedRpcIds.contains($0.id.lowercased())
        }
        guard !missing.isEmpty else { return }
        for entry in missing {
            messages.append(PocketMessage(pendingText: entry.text, rpcId: entry.id))
        }
        if let conversation = activeConversation {
            applyOutboxFlags(to: conversation, sessionId: session.sessionId)
        }
        messages.sort { $0.sequence < $1.sequence }
        recordDiagnostic("补回未确认消息 \(missing.count) 条")
    }

    @MainActor
    func removeOutbox(rpcIds: Set<String>) {
        guard !rpcIds.isEmpty else { return }
        outbox.remove(rpcIds: rpcIds)
    }

    func restoreOutboxPending(for session: PocketSession) -> [PocketMessage] {
        loadOutboxIfNeeded()
        return outboxEntries
            .filter { $0.sessionId == session.sessionId && !$0.text.isEmpty }
            .map { PocketMessage(pendingText: $0.text, rpcId: $0.id) }
    }

    func pendingSendState(for message: PocketMessage) -> PendingSendState? {
        guard message.isPending, let rpcId = message.rpcId else { return nil }
        let id = rpcId.lowercased()
        let failed = failedSendRpcIds.contains(rpcId) || failedSendRpcIds.contains(id)
            || outboxEntries.contains(where: { $0.id.lowercased() == id && $0.sendFailed })
        let acked = ackedSendRpcIds.contains(rpcId) || ackedSendRpcIds.contains(id)
            || outboxEntries.contains(where: { $0.id.lowercased() == id && $0.accepted })
        let queued = queuedSendRpcIds.contains(rpcId) || queuedSendRpcIds.contains(id)
            || outboxEntries.contains(where: { $0.id.lowercased() == id && $0.heldOffline })
        // 优先级在 DSHKit（可测）：失败 > 已确认 > 断网 > 发送中。
        // 「已确认」必须压过残留的断网标记，否则已受理的消息会显示「现在断网」。
        switch PendingSendStatePriority.resolve(failed: failed, acked: acked, queued: queued) {
        case .failed:
            return .failed
        case .acked:
            return .acked(steered: (activeConversation?.steeredRpcIds.contains(rpcId) ?? false)
                          || (activeConversation?.steeredRpcIds.contains(id) ?? false))
        case .queued:
            return .queued
        case .sending:
            return .sending
        }
    }

    /// 失败消息重发：从发件箱取回文本，作为新消息重新发送。
    @MainActor
    func retryPendingMessage(_ message: PocketMessage) {
        guard let rpcId = message.rpcId, let session = selectedSession,
              let entry = outboxEntries.first(where: { $0.id == rpcId }) else { return }
        failedSendRpcIds.remove(rpcId)
        ackedSendRpcIds.remove(rpcId)
        queuedSendRpcIds.remove(rpcId)
        messages.removeAll { $0.id == message.id }
        // 图片改回草稿，重发时一起带上。
        let restored = OutboxImageStore.load(entry.attachments, rpcId: entry.id)
        if !restored.isEmpty, let ui = restored.compactMap({ UIImage(data: $0.data) }) as [UIImage]? {
            for (item, image) in zip(restored, ui) {
                draftImages.append(PocketDraftImage(data: item.data, mediaType: item.attachment.mediaType,
                                                    name: item.attachment.name, uiImage: image))
            }
        }
        removeOutbox(rpcIds: [rpcId])
        draft = entry.text
        sendMessage(in: session)
    }

    /// 网络恢复：按发件箱写入顺序，把所有会话的断网暂存一并补发。
    /// 补发使用原来的 rpcId，成功前不从磁盘删除；服务端历史确认后才移除。
    @MainActor
    func flushQueuedSends() {
        guard !isDemoMode, !offlineFlushInFlight else { return }
        loadOutboxIfNeeded()
        if let conversation = activeConversation, let sessionId = selectedSession?.sessionId {
            applyOutboxFlags(to: conversation, sessionId: sessionId)
        }
        // 候选 = 断网暂存 + 首次失败的（SendRetryPolicy 决定）。
        let pending = outbox.resendCandidates()
        guard !pending.isEmpty else { return }
        offlineFlushInFlight = true
        let total = pending.count
        var sent = 0
        offlineFlushNote = "正在补发 0/\(total)"
        recordDiagnostic("网络恢复，准备一并补发 \(total) 条断网暂存")
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor [weak self] in self?.offlineFlushInFlight = false } }
            for entry in pending {
                // 发送前先标记「自动重试过」：失败也只会重试这一次。
                let isFailedEntry = entry.sendFailed
                if isFailedEntry {
                    await MainActor.run { self.outbox.markAutoRetried(rpcId: entry.id) }
                }
                let stillPending = await MainActor.run {
                    self.outbox.resendCandidates().contains { $0.id.lowercased() == entry.id.lowercased() }
                        || self.outbox.contains(rpcId: entry.id) { $0.accepted }
                }
                guard stillPending else { continue }
                let outcome = await self.deliverHeldOffline(entry)
                // 条与条之间留一点间隔，避开服务端限流。
                try? await Task.sleep(for: OfflineDeliveryPolicy.interMessageDelay)
                let stop = await MainActor.run { () -> Bool in
                    switch outcome {
                    case .acked:
                        self.noteHeldOfflineAccepted(entry)
                        sent += 1
                        self.offlineFlushNote = "正在补发 \(sent)/\(total)"
                        return false
                    case .stillOffline:
                        self.offlineFlushNote = "已补发 \(sent)/\(total)，网络又断了，剩余 \(total - sent) 条仍在手机上"
                        self.recordDiagnostic("补发仍无网络，剩余断网暂存留在本机：\(entry.id)")
                        return true
                    case .auth:
                        self.offlineFlushNote = "已补发 \(sent)/\(total)，登录失效，剩余 \(total - sent) 条仍在手机上"
                        self.handleAuthExpired()
                        return true
                    case .failed:
                        self.noteHeldOfflineFailed(entry)
                        return false
                    }
                }
                if stop { break }
            }
            if let session = await MainActor.run(body: { self.selectedSession }) {
                await self.loadHistory(session)
            }
            await MainActor.run {
                self.offlineFlushInFlight = false
                if sent == total {
                    self.offlineFlushNote = nil
                } else if self.offlineFlushNote == nil {
                    self.offlineFlushNote = "已补发 \(sent)/\(total)，剩余留在手机上"
                }
            }
        }
    }

    /// 用原 rpcId 补发。服务端按 requestId 去重，重复补发不会变成两条。
    ///
    /// 两条接收侧规则：
    /// - 一律 queue，不打断正在跑的轮次（积压是「排着说」，不是「打断」）；
    /// - 延迟超过 5 分钟的，正文前标出原发送时间，避免 AI 把旧话当成刚说的。
    func deliverHeldOffline(_ entry: OutboxEntry) async -> HeldOfflineDelivery {
        let now = Date()
        let createdAt = Date(timeIntervalSince1970: entry.createdAt)
        let text = OfflineDeliveryPolicy.annotatedText(entry.text, createdAt: createdAt, now: now)
        var content: [[String: Any]] = []
        if !text.isEmpty { content.append(["type": "text", "text": text]) }
        for item in OutboxImageStore.load(entry.attachments, rpcId: entry.id) {
            content.append([
                "type": "image",
                "mediaType": item.attachment.mediaType,
                "data": item.data.base64EncodedString(),
                "name": item.attachment.name
            ])
        }
        do {
            _ = try await rpcClient.rpcWithRetryAdapted("session/prompt", args: ["request": [
                "requestId": entry.id,
                "sessionId": entry.sessionId,
                "mode": PromptPolicy.backlogMode.rawValue,
                "content": content,
                "clientTimeZone": TimeZone.current.identifier,
                "clientSentAt": entry.createdAt
            ]])
            return .acked
        } catch {
            if let authError = error as? ConnectionError, authError.isUnauthorized {
                return .auth
            }
            if isTransientNetworkError(error), !isStaleTunnelError(error) {
                return .stillOffline
            }
            return .failed
        }
    }

    @MainActor
    func noteHeldOfflineAccepted(_ entry: OutboxEntry) {
        markOutboxAccepted(rpcId: entry.id)
        let id = entry.id.lowercased()
        if let conversation = conversations[entry.sessionId] {
            conversation.queuedRpcIds.remove(id)
            conversation.failedRpcIds.remove(id)
            conversation.ackedRpcIds.insert(id)
        }
        recordDiagnostic("断网暂存已送达，等历史确认：\(id)")
    }

    @MainActor
    func noteHeldOfflineFailed(_ entry: OutboxEntry) {
        markOutboxSendFailed(rpcId: entry.id)
        let id = entry.id.lowercased()
        conversations[entry.sessionId]?.queuedRpcIds.remove(id)
        conversations[entry.sessionId]?.failedRpcIds.insert(id)
        recordDiagnostic("断网暂存补发失败，正文仍留在本机：\(id)")
    }

    @MainActor
    func requestScrollToBottom() {
        scrollToBottomTick &+= 1
    }

    @MainActor
    func updateSessionTitle(_ title: String) {
        guard let id = selectedSession?.sessionId else { return }
        if let index = sessions.firstIndex(where: { $0.sessionId == id }) {
            sessions[index] = sessions[index].withTitle(title)
        }
        if let current = selectedSession {
            selectedSession = current.withTitle(title)
        }
    }

    /// 列表刷新后，把已打开会话的标题/运行状态同步过来。
    @MainActor
    func syncSelectedSessionMetadata() {
        guard let id = selectedSession?.sessionId,
              let fresh = sessions.first(where: { $0.sessionId == id }) else { return }
        selectedSession = fresh
    }
}

extension ConnectionModel {
    /// 启动网络恢复监听（幂等）。网络一恢复就补发 + 静默刷新列表。
    ///
    /// 为什么需要：补发原先只靠「列表刷新成功」（10 秒轮询）和「实时流收到帧」（要先重连上 WS）。
    /// 断网恢复后若两者都没到点，消息会一直停在「等联网时将一并发送」。
    @MainActor
    func installNetworkWatcher() {
        guard !networkWatcherStarted else { return }
        networkWatcherStarted = true
        networkWatcher.onBecomeReachable = { [weak self] in
            guard let self else { return }
            // 地址还没配置（首启/刚装）时不要触发刷新，否则会每两秒重试刷屏。
            guard (try? Self.serverURL(from: self.serverAddress)) != nil else { return }
            self.recordDiagnostic("网络恢复（路径监听），立即补发并刷新列表")
            self.flushQueuedSends()
            Task { await self.loadSessions(silently: true) }
        }
        networkWatcher.start()
    }
}
