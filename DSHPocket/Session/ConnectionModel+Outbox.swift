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

extension ConnectionModel {

    func loadOutboxIfNeeded() {
        guard !outboxLoaded else { return }
        outboxLoaded = true
        guard let data = UserDefaults.standard.data(forKey: Self.outboxDefaultsKey),
              let entries = try? JSONDecoder().decode([OutboxEntry].self, from: data) else { return }
        // 10 分钟内未确认视为历史遗留：steer 模式下服务端很快落库，长期 pending 只会造成"发送中"假象。
        let cutoff = Date().timeIntervalSince1970 - 10 * 60
        outboxEntries = entries.filter { $0.createdAt > cutoff }
            .map { OutboxEntry(id: $0.id.lowercased(), sessionId: $0.sessionId,
                               text: $0.text, createdAt: $0.createdAt) }
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
        if failedSendRpcIds.contains(rpcId) { return .failed }
        if queuedSendRpcIds.contains(rpcId) { return .queued }
        if ackedSendRpcIds.contains(rpcId) {
            return .acked(steered: activeConversation?.steeredRpcIds.contains(rpcId) ?? false)
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

    /// 网络恢复：把断网期间排队的消息按顺序补发。
    @MainActor
    func flushQueuedSends() {
        guard !isDemoMode, !isSending, selectedSession != nil else { return }
        loadOutboxIfNeeded()
        let pending = queuedSendRpcIds
        guard !pending.isEmpty else { return }
        recordDiagnostic("网络恢复，准备补发 \(pending.count) 条排队消息")
        Task { [weak self] in
            guard let self else { return }
            // outbox 里的顺序就是发送顺序。
            let ordered = await MainActor.run(body: {
                self.outboxEntries.filter { pending.contains($0.id) }.map(\.id)
            })
            for rpcId in ordered {
                let text = await MainActor.run(body: {
                    self.outboxEntries.first(where: { $0.id == rpcId })?.text
                })
                guard let text, !text.isEmpty else { continue }
                await MainActor.run {
                    self.queuedSendRpcIds.remove(rpcId)
                    if let old = self.messages.first(where: { $0.rpcId == rpcId }) {
                        self.messages.removeAll { $0.id == old.id }
                    }
                    self.removeOutbox(rpcIds: [rpcId])
                }
                await self.performSend(text: text, attachments: [])
                if await MainActor.run(body: { self.queuedSendRpcIds.contains(rpcId) }) {
                    // 还是没发出去，继续留着等下次。
                    break
                }
            }
        }
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
