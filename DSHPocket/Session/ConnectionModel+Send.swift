// 发送路径

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

/// 发送路径：组请求、写入发件箱、失败分型、核验与兜底轮询。
///
/// 从 ConnectionModel+Live 拆出来（纯文件搬迁，逻辑一字未改）：
/// 实时流与发送是两条独立链路，混在同一个 800+ 行文件里改一处要读两套上下文。
/// 架构规范对 extension 的判据是「拆了但职责没分开才算假拆分」，
/// 这里职责确实分开了：本文件只在「发消息」这条路径上被调用。
extension ConnectionModel {

    @MainActor
    func pollForReply(_ session: PocketSession, after text: String, afterSequence: Int) async {
        let started = Date()
        timingLog("history_poll_start text=\(text.debugDescription)")
        for _ in 0..<LiveStreamPolicy.historyPollAttempts {
            if Task.isCancelled { return }
            try? await Task.sleep(for: LiveStreamPolicy.historyPollInterval)
            if Task.isCancelled { return }
            guard sessionStore.selected?.sessionId == session.sessionId else { return }
            // 实时 follow 已经把回复送到时就不必再轮询分页了；轮询只作为断流兜底。
            if messages.contains(where: { !$0.isUser && !$0.isPending && $0.sequence > afterSequence }) {
                timingLog("reply_available source=follow total_elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                return
            }
            do {
                let address: [String: Any] = ["kind": "session", "sessionId": session.sessionId]
                let page = try await rpcClient.rpcAdapted("session/page", args: ["request": ["address": address, "maxMessages": Self.conversationMessageLimit]])
                // await 期间可能已切换会话，返回后必须再校验，否则旧会话消息会串进当前会话。
                guard !Task.isCancelled,
                      activeConversation?.sessionId == session.sessionId,
                      sessionStore.selected?.sessionId == session.sessionId else { return }
                let records = page["records"] as? [[String: Any]] ?? []
                let incoming = records.compactMap(PocketMessage.init(record:))
                timingLog("history_poll_result messages=\(incoming.count) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                mergeMessages(incoming)
                mergeSteps(from: records)
                confirmInboxOutbox(in: records)
                if let reply = incoming.first(where: { !$0.isUser && !$0.isPending && $0.sequence > afterSequence }) {
                    timingLog("reply_available source=history seq=\(reply.sequence) chars=\(reply.text.count) total_elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                    recordDiagnostic("历史轮询找到本次助手回复，等待 \(Int(Date().timeIntervalSince(started) * 1000)) 毫秒；内容：\(reply.text)")
                    return
                }
            } catch { }
        }
        recordDiagnostic("历史轮询超时：30 次内未找到本次助手回复")
    }


    @MainActor
    func sendMessage(in session: PocketSession) {
        if sessionStore.selected?.sessionId != session.sessionId {
            recordDiagnostic("发送前纠正会话：期望 \(session.displayTitle)")
            sessionStore.selected = session
            open(session)
            // 继续发送，避免"点了发送但输入框内容还在、也没发出去"。
            sendMessage()
            return
        }
        sendMessage()
    }


    @MainActor
    func sendMessage() {
        if isSending {
            recordDiagnostic("发送被忽略：上一条仍在发送中")
            return
        }
        if isDemoMode {
            // sendDemoMessage 自己会清空草稿；这里不能先清，否则它读不到文本。
            sendTask = Task { await self.sendDemoMessage() }
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = draftImages
        guard (!text.isEmpty || !attachments.isEmpty), sessionStore.selected != nil else {
            recordDiagnostic("发送被忽略：文本为空或未打开会话")
            return
        }
        sendTask?.cancel()
        // 有引用时把原文作为 Markdown 引用块前置（DSH 协议层只接受文本/图片块）。
        var outgoingText = text
        if let quote = pendingQuote {
            outgoingText = quotedPrefix(for: quote) + text
            recordDiagnostic("发送带引用：引用 #\(quote.sequence)")
            pendingQuote = nil
        }
        // 立刻清空：不等异步 performSend 的 guard，也避免中文输入法把 marked text 留在框里。
        clearDraftImmediately()
        sendTask = Task { await self.performSend(text: outgoingText, attachments: attachments) }
    }


    @MainActor
    func clearDraftImmediately() {
        let conversation = activeConversation
        let sessionId = conversation?.sessionId ?? sessionStore.selected?.sessionId
        conversation?.draft = ""
        conversation?.draftImages = []
        draft = ""
        draftImages = []
        if let sessionId { DraftStore.save("", for: sessionId) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.activeConversation === conversation || conversation == nil {
                self.draft = ""
                self.draftImages = []
            }
        }
    }


    @MainActor
    func cancelSend() {
        guard isSending else { return }
        sendTask?.cancel()
        sendTask = nil
        if let id = pendingSendID { messages.removeAll { $0.id == id } }
        if let rpcId = pendingSendRpcId {
            removeOutbox(rpcIds: [rpcId])
            ackedSendRpcIds.remove(rpcId)
            failedSendRpcIds.remove(rpcId)
        }
        pendingSendID = nil
        pendingSendRpcId = nil
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = cancelledDraft
            draftImages = cancelledImages
        }
        cancelledDraft = ""
        cancelledImages = []
        isSending = false
        conversationError = nil
        recordDiagnostic("已取消发送")
    }


    @MainActor
    func performSend(text: String, attachments: [PocketDraftImage]) async {
        guard let session = sessionStore.selected, !isSending else { return }
        let sendConversation = sessionStore.conversations[session.sessionId]
        let lastSequence = messages.filter { !$0.isPending }.map(\.sequence).max() ?? -1
        let requestId = UUID().uuidString.lowercased()
        let sortAnchor = TimelineOrdering.pendingAnchor(
            messageMax: lastSequence,
            stepMax: steps.map(\.sequence).max() ?? -1
        )
        let pending = PocketMessage(pendingText: text, localImages: attachments.map(\.uiImage), rpcId: requestId, sortSequence: sortAnchor)
        let sendStarted = Date()
        timingLog("send_typed chars=\(text.count) images=\(attachments.count)")
        recordDiagnostic("用户点击发送：\(text.count) 字，图片 \(attachments.count) 张")
        messages.append(pending)
        pendingSendID = pending.id
        pendingSendRpcId = requestId
        addOutbox(sessionId: session.sessionId, rpcId: requestId, text: text, images: attachments)
        cancelledDraft = text
        cancelledImages = attachments
        draft = ""
        draftImages = []
        if let sendConversation {
            sendConversation.draft = ""
            sendConversation.draftImages = []
        }
        DraftStore.save("", for: session.sessionId)
        DraftImageStore.clear(sessionId: session.sessionId)
        isSending = true
        defer {
            isSending = false
            pendingSendID = nil
            pendingSendRpcId = nil
            cancelledDraft = ""
            cancelledImages = []
        }
        // 发送前预判：已知网络不可达就别白等三次重试（实测原本要 18 秒才切到「断网暂存」）。
        // 注意顺序——必须在「写入发件箱」之后，否则预判后 return 会丢掉用户输入。
        if SendPreflightPolicy.action(isReachable: networkWatcher.isReachable) == .holdOffline {
            queuedSendRpcIds.insert(requestId)
            failedSendRpcIds.remove(requestId)
            markOutboxHeldOffline(rpcId: requestId)
            conversationError = nil
            recordDiagnostic("发送前预判网络不可达，直接写入断网暂存：\(requestId)")
            return
        }
        do {
            timingLog("prompt_start chars=\(text.count) images=\(attachments.count)")
            // 请求体结构在 DSHKit（可测）：空文本不产生 text block、图片字段名固定。
            let payloadImages = attachments.map {
                PromptPayload.Image(mediaType: $0.mediaType,
                                    base64: $0.data.base64EncodedString(),
                                    name: $0.name)
            }
            // 只有「确认过实时 turn 事件、且确实在跑」才用 steer 打断；
            // 没见到实时事件时按 queue 处理——queue 最多排到本轮之后，steer 会打断正在做的事。
            let promptMode = PromptPolicy.liveMode(isRunning: isTurnRunning).rawValue
            recordDiagnostic("发送模式：\(promptMode)（生成中=\(isTurnRunning)）")
            _ = try await rpcClient.rpcWithRetryAdapted("session/prompt", args: ["request": [
                "requestId": requestId,
                "sessionId": session.sessionId,
                "mode": promptMode,
                "content": PromptPayload.content(text: text, images: payloadImages),
                "clientTimeZone": TimeZone.current.identifier
            ]])
            timingLog("prompt_ack elapsed_ms=\(Int(Date().timeIntervalSince(sendStarted) * 1000))")
            recordDiagnostic("服务端已确认发送，耗时 \(Int(Date().timeIntervalSince(sendStarted) * 1000)) 毫秒")
            ackedSendRpcIds.insert(requestId)
            markOutboxAccepted(rpcId: requestId)
            if promptMode == "steer" { activeConversation?.steeredRpcIds.insert(requestId) }
            Task { await activeConversation?.coordinator?.setExpectingActivity(true) }
            conversationError = nil
            // 服务端已受理：立刻结束"发送中"状态，恢复发送按钮；若为 steer，服务端会打断当前轮。
            isSending = false
            pendingSendID = nil
            cancelledDraft = ""
            cancelledImages = []
            // 先用服务端真实用户消息替换本地待确认消息，保证"用户消息在上、助手回复在下"的顺序；
            // 否则实时回复先到、轮询提前退出时，待确认消息会带着临时序号排在回复后面。
            await loadHistory(session)
            await pollForReply(session, after: text, afterSequence: lastSequence)
            // 服务端 ACK 后如果还没收到确认，先主动核验一次（网络抖动时 WS/轮询可能错过确认），
            // 核验不到再标记失败，避免误报吓人。
            if ackedSendRpcIds.contains(requestId) && promptMode == "steer" {
                // steer 进入 agent inbox，后续会被注入成 user/message；
                // 此阶段核验不到是正常现象，绝不能标失败（显示"已送达，排队等待处理"）。
                if case .landed = await verifySendLanded(session: session, requestId: requestId) {
                    confirmOutbox(rpcIds: [requestId])
                    ackedSendRpcIds.remove(requestId)
                    failedSendRpcIds.remove(requestId)
                    conversationError = nil
                    recordDiagnostic("steer 已落库确认：\(requestId)")
                } else {
                    conversationError = nil
                    recordDiagnostic("steer 已 ACK，等待注入为 user/message：\(requestId)")
                }
            } else if ackedSendRpcIds.contains(requestId) {
                switch await verifySendLanded(session: session, requestId: requestId) {
                case .landed:
                    confirmOutbox(rpcIds: [requestId])
                    ackedSendRpcIds.remove(requestId)
                    failedSendRpcIds.remove(requestId)
                    conversationError = nil
                    recordDiagnostic("发送核验成功：\(requestId)")
                case .absent:
                    failedSendRpcIds.insert(requestId)
                    ackedSendRpcIds.remove(requestId)
                    markOutboxSendFailed(rpcId: requestId)
                    conversationError = "这条消息服务端没有收到，点消息下方「重新发送」可重试（按 requestId 去重，不会重复）。"
                    recordDiagnostic("发送核验失败（服务端无此消息）：\(requestId)")
                case .unreachable:
                    // 网络抖动导致核验请求本身失败：不能误报失败，保持"已发出，等待处理"，后台再核验。
                    recordDiagnostic("发送核验网络不可达，稍后重试：\(requestId)")
                    scheduleSendReverification(session: session, requestId: requestId, attempt: 1)
                }
            }
        } catch {
            // 处置优先级在 DSHKit（可测）：取消 > 登录失效 > 网络不通 > 其它失败。
            let isCancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
            let unauthorized: Bool = {
                if (error as? ConnectionError)?.isUnauthorized == true { return true }
                return false
            }()
            let action = SendFailurePolicy.action(isCancelled: isCancelled,
                                                  isUnauthorized: unauthorized,
                                                  isTransient: isTransientNetworkError(error),
                                                  isStaleTunnel: isStaleTunnelError(error))
            switch action {
            case .returnToComposer:
                // 用户取消：正文退回输入框，再删本机副本；否则留着等重发。
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft = pending.text
                }
                if OutboxRetentionPolicy.canRemove(cause: .userCancelled) {
                    removeOutbox(rpcIds: [requestId])
                    messages.removeAll { $0.id == pending.id }
                } else {
                    failedSendRpcIds.insert(requestId)
                    markOutboxSendFailed(rpcId: requestId)
                }
            case .reauthenticate:
                // 登录失效不等于这条消息该丢：正文留在发件箱并标失败，重新登录后可重发。
                if OutboxRetentionPolicy.canRemove(cause: .authExpired) {
                    removeOutbox(rpcIds: [requestId])
                    messages.removeAll { $0.id == pending.id }
                } else {
                    failedSendRpcIds.insert(requestId)
                    markOutboxSendFailed(rpcId: requestId)
                    recordDiagnostic("登录失效，正文保留在发件箱：\(requestId)")
                }
                handleAuthExpired()
            case .holdOffline:
                queuedSendRpcIds.insert(requestId)
                failedSendRpcIds.remove(requestId)
                markOutboxHeldOffline(rpcId: requestId)
                conversationError = nil
                recordDiagnostic("网络不可达，已写入断网暂存，联网后一并发送：\(requestId)")
            case .markFailed:
                // 其它错误：正文留在发件箱，标记失败，用户可直接重发。
                failedSendRpcIds.insert(requestId)
                markOutboxSendFailed(rpcId: requestId)
                conversationError = "发送失败：\(error.localizedDescription)（点消息气泡下方「重新发送」可重试）"
            }
        }
    }


    @MainActor
    func verifySendLanded(session: PocketSession, requestId: String) async -> SendVerification {
        var sawReachableResponse = false
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(attempt == 1 ? 1 : attempt == 2 ? 2 : 4))
            }
            guard let value = try? await rpcClient.rpcAdapted("session/page", args: ["request": [
                "address": ["kind": "session", "sessionId": session.sessionId],
                "maxMessages": 30
            ]]) else { continue }
            sawReachableResponse = true
            let records = value["records"] as? [[String: Any]] ?? []
            // 扫描规则在 DSHKit（可测）：user/message 或 agent/inbox/spliced 都算已送达。
            if SendLandedScan.landed(inRecords: records, requestId: requestId) { return .landed }
        }
        return sawReachableResponse ? .absent : .unreachable
    }

}
