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

    func loadOutboxIfNeeded() {
        guard !outboxLoaded else { return }
        outboxLoaded = true
        guard let data = UserDefaults.standard.data(forKey: Self.outboxDefaultsKey),
              let entries = try? JSONDecoder().decode([OutboxEntry].self, from: data) else { return }
        // 不按时间删除。断网暂存和未确认正文一直留到服务端历史确认。
        outboxEntries = entries.map {
            OutboxEntry(id: $0.id.lowercased(), sessionId: $0.sessionId,
                        text: $0.text, createdAt: $0.createdAt,
                        heldOffline: $0.heldOffline, sendFailed: $0.sendFailed,
                        accepted: $0.accepted)
        }
        persistOutbox()
    }

    func persistOutbox() {
        if let data = try? JSONEncoder().encode(outboxEntries) {
            UserDefaults.standard.set(data, forKey: Self.outboxDefaultsKey)
        }
    }

    @MainActor
    func addOutbox(sessionId: String, rpcId: String, text: String) {
        guard !text.isEmpty else { return }
        loadOutboxIfNeeded()
        outboxEntries.append(OutboxEntry(id: rpcId.lowercased(), sessionId: sessionId, text: text,
                                         createdAt: Date().timeIntervalSince1970))
        persistOutbox()
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
        loadOutboxIfNeeded()
        let id = rpcId.lowercased()
        guard let index = outboxEntries.firstIndex(where: { $0.id.lowercased() == id }) else { return }
        var entry = outboxEntries[index]
        guard let updated = change(&entry) else { return }
        outboxEntries[index] = updated
        persistOutbox()
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
        guard !rpcIds.isEmpty else { return }
        let ids = Set(rpcIds.map { $0.lowercased() })
        loadOutboxIfNeeded()
        let before = outboxEntries.count
        outboxEntries.removeAll { ids.contains($0.id.lowercased()) }
        if outboxEntries.count != before { persistOutbox() }
    }

    /// 发件箱里已发出、但列表里没有对应消息的条目：补成 pending 气泡，避免"发了但看不见"。
    @MainActor
    func restoreMissingOutboxMessages() {
        guard !isDemoMode, let session = selectedSession else { return }
        loadOutboxIfNeeded()
        let representedRpcIds = Set(messages.compactMap(\.rpcId).map { $0.lowercased() })
        let missing = outboxEntries.filter {
            $0.sessionId == session.sessionId && !$0.text.isEmpty && !representedRpcIds.contains($0.id.lowercased())
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
        loadOutboxIfNeeded()
        let ids = Set(rpcIds.map { $0.lowercased() })
        outboxEntries.removeAll { ids.contains($0.id.lowercased()) }
        persistOutbox()
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
        if failedSendRpcIds.contains(rpcId) || failedSendRpcIds.contains(id)
            || outboxEntries.contains(where: { $0.id.lowercased() == id && $0.sendFailed }) {
            return .failed
        }
        if queuedSendRpcIds.contains(rpcId) || queuedSendRpcIds.contains(id)
            || outboxEntries.contains(where: { $0.id.lowercased() == id && $0.heldOffline }) {
            return .queued
        }
        if ackedSendRpcIds.contains(rpcId) || ackedSendRpcIds.contains(id)
            || outboxEntries.contains(where: { $0.id.lowercased() == id && $0.accepted }) {
            return .acked(steered: (activeConversation?.steeredRpcIds.contains(rpcId) ?? false)
                          || (activeConversation?.steeredRpcIds.contains(id) ?? false))
        }
        return .sending
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
        let pending = outboxEntries.filter(\.heldOffline).sorted { $0.createdAt < $1.createdAt }
        guard !pending.isEmpty else { return }
        offlineFlushInFlight = true
        recordDiagnostic("网络恢复，准备一并补发 \(pending.count) 条断网暂存")
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor [weak self] in self?.offlineFlushInFlight = false } }
            for entry in pending {
                let stillHeld = await MainActor.run {
                    self.outboxEntries.contains { $0.id.lowercased() == entry.id.lowercased() && $0.heldOffline }
                }
                guard stillHeld else { continue }
                let outcome = await self.deliverHeldOffline(entry)
                let stop = await MainActor.run { () -> Bool in
                    switch outcome {
                    case .acked:
                        self.noteHeldOfflineAccepted(entry)
                        return false
                    case .stillOffline:
                        self.recordDiagnostic("补发仍无网络，剩余断网暂存留在本机：\(entry.id)")
                        return true
                    case .auth:
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
            await MainActor.run { self.offlineFlushInFlight = false }
        }
    }

    /// 用原 rpcId 补发。服务端按 requestId 去重，重复补发不会变成两条。
    func deliverHeldOffline(_ entry: OutboxEntry) async -> HeldOfflineDelivery {
        let mode = await MainActor.run { () -> String in
            let running = self.selectedSession?.sessionId == entry.sessionId
                ? self.isTurnRunning
                : (self.sessions.first { $0.sessionId == entry.sessionId }?.running ?? false)
            return running ? "steer" : "queue"
        }
        do {
            _ = try await rpcWithRetry("session/prompt", args: ["request": [
                "requestId": entry.id,
                "sessionId": entry.sessionId,
                "mode": mode,
                "content": [["type": "text", "text": entry.text]],
                "clientTimeZone": TimeZone.current.identifier
            ]])
            return .acked
        } catch {
            if let authError = error as? ConnectionError, case .server(401) = authError {
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
