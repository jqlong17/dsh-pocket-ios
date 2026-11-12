// 过程展开、任务名单

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

    @MainActor
    func mergeSteps(from records: [[String: Any]]) {
        // 分页记录统一在 DSHKit 里分发：步骤走 applyStep，标题单独落，其余忽略。
        applyRecords(DSHDecoding.records(fromRecords: records))
    }

    @MainActor
    func applyRecords(_ records: [DSHRecord]) {
        for record in records {
            switch record {
            case .step(let step):
                applyStep(step)
            case .title(_, let title):
                if !title.isEmpty { updateSessionTitle(title) }
            case .message, .unknown:
                break
            }
        }
    }

    /// 处理 tool/call、tool/result、turn/start、turn/end。
    /// 解析全在 DSHKit（DSHDecoding）；这里只把结果落到会话状态上。
    @MainActor
    func applyStepEvent(_ event: [String: Any], storeBodies: Bool = false) {
        if let step = DSHDecoding.stepEvent(fromEvent: event) {
            applyStep(step, storeBodies: storeBodies,
                      startedAt: DSHDecoding.eventTimestamp(fromEvent: event))
            return
        }
        // 不是过程事件时，标题变更也要能落到界面。
        if case .title(_, let title) = DSHDecoding.record(fromEvent: event), !title.isEmpty {
            updateSessionTitle(title)
        }
    }

    @MainActor
    func applyStep(_ event: DSHStepEvent, storeBodies: Bool = false, startedAt: Date? = nil) {
        switch event {
        case .toolCall(let sequence, let turn, _, let name, let detail, _):
            let callId = Self.callId(of: event)
            guard !callId.isEmpty, !steps.contains(where: { $0.id == callId }) else { return }
            // 未知工具时 DSHKit 会把工具名当 detail：与标题重复，界面上不再显示一遍。
            let shownDetail = detail == name ? "" : detail
            let step = PocketStep(id: callId, sequence: sequence, turn: turn, number: 0,
                                  name: name, detail: shownDetail)
            steps.append(step)
            steps.sort { $0.sequence < $1.sequence }
            recordDiagnostic("过程：\(step.label)\(step.detail.isEmpty ? "" : "（\(step.detail)）")")
        case .toolResult(_, _, let callId, let text, let isError, let images):
            guard let index = steps.firstIndex(where: { $0.id == callId }) else { return }
            steps[index].isError = isError
            steps[index].finished = true
            // 过程正文默认不进内存。展开时 storeBodies=true 再填。
            guard storeBodies else { return }
            steps[index].resultText = text
            steps[index].images = images.map {
                PocketImageRef(attachmentId: $0.attachmentId,
                               mediaType: $0.mediaType,
                               bytes: $0.bytes ?? 0,
                               width: $0.width,
                               height: $0.height,
                               name: $0.name)
            }
            steps[index].detailsLoaded = true
            if !images.isEmpty {
                recordDiagnostic("工具结果包含图片：\(images.count) 张")
            }
        case .turnStart(let sequence, _):
            if !turnStarts.contains(sequence) { turnStarts.append(sequence) }
            isTurnRunning = true
            turnStartedAt = startedAt ?? Date()
        case .turnEnd(let sequence, _, let failure):
            recordTurnFailure(sequence: sequence, failure: failure)
        }
    }

    /// 一轮结束时，把这一轮里还没等到结果的步骤收尾。
    /// 典型场景：ask_user_question 被中断、没有 tool/result 回来，
    /// 界面会一直停在「正在等待你的选择…」。
    @MainActor
    func markUnfinishedStepsEnded(turn: Int) {
        var changed = false
        for index in steps.indices where !steps[index].finished {
            // turn 为 0 表示事件没带轮次，按「全部收尾」处理。
            guard turn == 0 || steps[index].turn == turn else { continue }
            steps[index].finished = true
            changed = true
        }
        if changed { recordDiagnostic("过程收尾：第 \(turn) 轮未完成的步骤已标记结束") }
    }

    /// 事件里带 callId 的只有 toolCall，单独取出来避免在模式匹配里塞参数。
    static func callId(of event: DSHStepEvent) -> String {
        switch event {
        case .toolCall(_, _, let callId, _, _, _): return callId
        case .toolResult(_, _, let callId, _, _, _): return callId
        case .turnStart, .turnEnd: return ""
        }
    }

    /// 读取电脑端附件库里的图片（带内存缓存）。
    @MainActor
    func loadImage(_ ref: PocketImageRef) async -> UIImage? {
        await loadImage(ref, tier: .thumbnail)
    }

    /// 全屏与保存到相册用：按需拉高清（2048），别再把 640 的缩略图放大。
    func loadFullImage(_ ref: PocketImageRef) async -> UIImage? {
        await loadImage(ref, tier: .full)
    }

    func loadImage(_ ref: PocketImageRef, tier: ImagePipeline.Tier) async -> UIImage? {
        guard let session = sessionStore.selected else { return nil }
        let screenLongSide = Int(max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
                                 * UIScreen.main.scale)
        // 全屏按屏幕像素取（1:1 不放大）；缩略图仍是 640。
        let maxPixel: CGFloat = tier == .full
            ? CGFloat(ImageFetchPolicy.fullMaxPixel(screenLongSide: screenLongSide))
            : CGFloat(ImageFetchPolicy.thumbnailMaxPixel)
        let source = AttachmentByteSource(
            attachmentId: ref.attachmentId,
            sessionId: session.sessionId,
            requestJSON: ref.requestJSON,
            knownBytes: ref.bytes,
            rpc: { [weak self] method, args in
                guard let self else { throw ConnectionError.invalidURL("") }
                return try await self.rpcClient.rpcAdapted(method, args: args)
            }
        )
        let image = await ImagePipeline.shared.image(source: source, tier: tier, maxPixel: maxPixel)
        // 附件不存在：清掉本地缓存，避免一直占着预算。
        if image == nil, ref.bytes > 0 {
            ImagePipeline.shared.forget(cacheKey: source.cacheKey)
        }
        return image
    }

    /// 打开任务面板时才订阅。重复调用无副作用。
    @MainActor
    func ensureJobRoster() {
        guard !isDemoMode, let session = sessionStore.selected,
              let conversation = sessionStore.conversations[session.sessionId] else { return }
        guard !jobRoster.isRunning else { return }
        guard let base = URL(string: connection.serverAddress),
              let socketURL = Self.webSocketURL(from: base, path: "api/remote.mux") else { return }
        jobRoster.start(sessionId: session.sessionId, socketURL: socketURL) { [weak conversation] rows in
            // 名单写回会话状态；订阅器本身不持有业务数据（见 JobRoster 注释）。
            conversation?.jobs = rows
        }
    }

    /// 关掉任务面板就取消订阅，别让不可见的界面一直占着连接。
    @MainActor
    func stopJobRoster() {
        jobRoster.stop()
        activeConversation?.jobs = []
    }

    /// 退出会话页：停掉这条会话的实时流，避免反复进出时订阅和缓冲一直叠着。
    @MainActor
    func leave(_ session: PocketSession) {
        let leaveStarted = Date()
        guard let conversation = sessionStore.conversations[session.sessionId] else { return }
        conversation.liveTask?.cancel()
        conversation.fallbackTask?.cancel()
        conversation.coordinatorTask?.cancel()
        jobRoster.stop()
        conversation.liveTask = nil
        conversation.fallbackTask = nil
        conversation.coordinatorTask = nil
        conversation.jobs = []
        stopDiagnosticSampler()
        finishDiagnosticVisit(leaveMs: Int(Date().timeIntervalSince(leaveStarted) * 1000))
        conversation.coordinatorStarted = false
        conversation.isFollowing = false
        if let coordinator = conversation.coordinator {
            conversation.coordinator = nil
            Task { await coordinator.stop() }
        }
        if sessionStore.selected?.sessionId == session.sessionId {
            sessionStore.selected = nil
        }
        // 退出后不再有可见会话；未读/回到底部据此判断。
        if visibleSessionId == session.sessionId {
            visibleSessionId = nil
        }
        recordDiagnostic("离开会话：\(session.displayTitle) 内存 \(String(format: "%.1f", Diagnostics.memoryFootprintMB())) MB 会话页 \(ConversationViewLifetime.liveCount)")
    }

    /// 展开某一组过程时才拉取正文。分页按序号切开，不把整段历史再装进内存。
    @MainActor
    func loadProcessDetails(for group: PocketStepGroup) async {
        guard let session = sessionStore.selected else { return }
        let first = group.steps.map(\.sequence).min() ?? group.sequence
        let last = group.steps.map(\.sequence).max() ?? group.sequence
        do {
            let page = try await rpcClient.rpcAdapted("session/page", args: ["request": [
                "address": ["kind": "session", "sessionId": session.sessionId],
                "throughSeq": last,
                "beforeSeq": last + 1,
                "maxMessages": 4
            ]])
            let records = page["records"] as? [[String: Any]] ?? []
            for step in DSHDecoding.stepEvents(fromRecords: records)
            where step.sequence >= first && step.sequence <= last {
                applyStep(step, storeBodies: true)
            }
            recordDiagnostic("过程详情已加载：seq \(first)-\(last)")
        } catch {
            recordDiagnostic("过程详情加载失败：\(error.localizedDescription)")
        }
    }

    /// 收起后丢掉正文，只留一行摘要。
    @MainActor
    func dropProcessDetails(for group: PocketStepGroup) {
        let ids = Set(group.steps.map(\.id))
        for index in steps.indices where ids.contains(steps[index].id) {
            steps[index].resultText = ""
            steps[index].images = []
            steps[index].detailsLoaded = false
        }
    }

    /// 网络恢复后继续核验（最多 5 次，退避 5/10/20/40/60s）。
    func scheduleSendReverification(session: PocketSession, requestId: String, attempt: Int) {
        guard attempt <= 5 else { return }
        let delay = [5.0, 10.0, 20.0, 40.0, 60.0][attempt - 1]
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            guard await MainActor.run(body: { self.ackedSendRpcIds.contains(requestId) }) else { return }
            switch await self.verifySendLanded(session: session, requestId: requestId) {
            case .landed:
                await MainActor.run {
                    self.confirmOutbox(rpcIds: [requestId])
                    self.ackedSendRpcIds.remove(requestId)
                    self.failedSendRpcIds.remove(requestId)
                    self.conversationError = nil
                    self.recordDiagnostic("发送延迟核验成功：\(requestId)")
                }
            case .absent:
                await MainActor.run {
                    self.failedSendRpcIds.insert(requestId)
                    self.conversationError = "这条消息服务端没有收到，点消息下方「重新发送」可重试。"
                }
            case .unreachable:
                self.scheduleSendReverification(session: session, requestId: requestId, attempt: attempt + 1)
            }
        }
    }

    /// 把照片/相机图片压缩成待发送附件。
    @MainActor
    func addDraftImage(_ image: UIImage) {
        guard let prepared = Self.prepareImage(image) else { return }
        draftImages.append(prepared)
        if let id = sessionStore.selected?.sessionId {
            DraftImageStore.save(draftImages, sessionId: id)
        }
    }

    /// 删除一张草稿图，并把落盘的那份一起更新。
    @MainActor
    func removeDraftImage(id: UUID) {
        draftImages.removeAll { $0.id == id }
        if let id = sessionStore.selected?.sessionId {
            DraftImageStore.save(draftImages, sessionId: id)
        }
    }

    /// 当前会话里全部 Markdown 内嵌图片（按消息顺序），供全屏左右翻页。
    ///
    /// 只收 `.image` 段：文本段里的行内图片在 Markdown 解析阶段就已经是图片段了。
    var conversationMarkdownImageURLs: [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for message in messages where !message.isPending {
            for segment in markdownSegments(message.text) {
                if case .image(let url, _) = segment, !seen.contains(url.absoluteString) {
                    seen.insert(url.absoluteString)
                    urls.append(url)
                }
            }
        }
        return urls
    }
}
