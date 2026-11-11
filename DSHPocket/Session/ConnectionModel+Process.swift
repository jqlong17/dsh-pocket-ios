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
        for record in records {
            guard let event = record["event"] as? [String: Any] else { continue }
            applyStepEvent(event)
        }
    }

    /// 处理 tool/call、tool/result、turn/start、turn/end 等过程事件。
    @MainActor
    func applyStepEvent(_ event: [String: Any], storeBodies: Bool = false) {
        guard let type = event["type"] as? String,
              let sequence = (event["seq"] as? NSNumber)?.intValue else { return }
        let data = event["data"] as? [String: Any] ?? [:]
        switch type {
        case "tool/call":
            guard let callId = data["callId"] as? String,
                  let name = data["name"] as? String else { return }
            guard !steps.contains(where: { $0.id == callId }) else { return }
            let turn = (data["turn"] as? NSNumber)?.intValue ?? 0
            let number = (data["step"] as? NSNumber)?.intValue ?? 0
            let arguments = (data["arguments"] as? String).flatMap {
                try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
            } ?? [:]
            let step = PocketStep(id: callId, sequence: sequence, turn: turn, number: number,
                                  name: name, detail: Self.stepDetail(name: name, arguments: arguments))
            steps.append(step)
            steps.sort { $0.sequence < $1.sequence }
            recordDiagnostic("过程：\(step.label)\(step.detail.isEmpty ? "" : "（\(step.detail)）")")
        case "tool/result":
            let message = data["message"] as? [String: Any] ?? [:]
            guard let callId = (message["toolCallId"] as? String) ?? (data["callId"] as? String),
                  let index = steps.firstIndex(where: { $0.id == callId }) else { return }
            let content = message["content"] as? [[String: Any]] ?? []
            steps[index].isError = message["isError"] as? Bool ?? false
            steps[index].finished = true
            // 过程正文默认不进内存。展开时 storeBodies=true 再填。
            guard storeBodies else { return }
            steps[index].resultText = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined()
            steps[index].images = content.compactMap { block -> PocketImageRef? in
                guard block["type"] as? String == "image",
                      let attachment = block["attachment"] as? [String: Any] else { return nil }
                return PocketImageRef(json: attachment)
            }
            steps[index].detailsLoaded = true
        case "turn/start":
            if !turnStarts.contains(sequence) { turnStarts.append(sequence) }
            isTurnRunning = true
            let time = (event["time"] as? NSNumber)?.doubleValue ?? 0
            turnStartedAt = time > 0 ? Date(timeIntervalSince1970: time / 1000) : Date()
        case "turn/end":
            recordTurnFailure(sequence: sequence, failure: DSHDecoding.turnFailure(from: data))
        case "session/title":
            if let title = data["title"] as? String, !title.isEmpty {
                updateSessionTitle(title)
            }
        default:
            break
        }
    }

    static func stepDetail(name: String, arguments: [String: Any]) -> String {
        switch name {
        case "bash":
            let command = (arguments["command"] as? String) ?? ""
            let first = command.split(separator: "\n").first.map(String.init) ?? command
            return String(first.prefix(80))
        case "read", "read_image", "write", "edit":
            guard let path = arguments["file_path"] as? String else { return "" }
            return URL(fileURLWithPath: path).lastPathComponent
        case "web_search":
            return (arguments["queries"] as? [String])?.joined(separator: " / ").prefix(80).description ?? ""
        case "web_fetch":
            return (arguments["url"] as? String) ?? ""
        case "ask_user_question":
            return "等待你的回答"
        default:
            return ""
        }
    }

    /// 读取电脑端附件库里的图片（带内存缓存）。
    @MainActor
    func loadImage(_ ref: PocketImageRef) async -> UIImage? {
        if let cached = ImageMemory.shared.image(forKey: ref.attachmentId) { return cached }
        guard let session = selectedSession else { return nil }
        do {
            let value = try await rpc("session/attachment", args: ["request": [
                "sessionId": session.sessionId,
                "attachment": ref.requestJSON
            ]])
            guard let base64 = value["data"] as? String,
                  let data = Data(base64Encoded: base64),
                  let image = ImageMemory.thumbnail(data: data) else { return nil }
            ImageMemory.shared.store(image, forKey: ref.attachmentId)
            return image
        } catch {
            return nil
        }
    }

    /// 订阅这条会话的后台任务名单。`job/list` 是整份替换的流，断线重连后第一帧就是真相。
    @MainActor
    func startJobRoster(for conversation: ConversationState, session: PocketSession) {
        conversation.jobsTask?.cancel()
        conversation.jobsStarted = true
        conversation.jobsTask = Task { [weak self] in
            await self?.runJobRoster(conversation: conversation, session: session)
        }
    }

    func runJobRoster(conversation: ConversationState, session: PocketSession) async {
        var retryDelay: Duration = .seconds(2)
        while !Task.isCancelled {
            guard let base = URL(string: serverAddress),
                  let socketURL = Self.webSocketURL(from: base, path: "api/remote.mux") else { return }
            let socket = URLSession.shared.webSocketTask(with: socketURL)
            socket.resume()
            let streamId = UUID().uuidString
            let open = StreamOpen(type: "open", streamId: streamId, endpoint: "job/list",
                                  payload: ["args": ["request": ["sessionId": session.sessionId]]])
            do {
                let data = try JSONEncoder().encode(open)
                guard let text = String(data: data, encoding: .utf8) else { throw ConnectionError.invalidPayload }
                try await socket.send(.string(text))
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let frameData: Data = {
                        if case .string(let s) = message { return s.data(using: .utf8) }
                        if case .data(let d) = message { return d }
                        return nil
                    }() else { continue }
                    guard let object = try JSONSerialization.jsonObject(with: frameData) as? [String: Any],
                          object["streamId"] as? String == streamId,
                          object["type"] as? String == "item",
                          let value = object["value"] as? [String: Any],
                          let rows = value["jobs"] as? [[String: Any]] else { continue }
                    let next = rows.compactMap(PocketJob.init(json:))
                    await MainActor.run {
                        guard self.activeConversation === conversation else { return }
                        conversation.jobs = next
                    }
                }
            } catch {
                if Task.isCancelled { break }
                socket.cancel(with: .goingAway, reason: nil)
                do { try await Task.sleep(for: retryDelay) } catch { break }
                retryDelay = min(retryDelay * 2, .seconds(20))
            }
        }
    }

    /// 退出会话页：停掉这条会话的实时流，避免反复进出时订阅和缓冲一直叠着。
    @MainActor
    func leave(_ session: PocketSession) {
        let leaveStarted = Date()
        guard let conversation = conversations[session.sessionId] else { return }
        conversation.liveTask?.cancel()
        conversation.fallbackTask?.cancel()
        conversation.coordinatorTask?.cancel()
        conversation.jobsTask?.cancel()
        conversation.liveTask = nil
        conversation.fallbackTask = nil
        conversation.coordinatorTask = nil
        conversation.jobsTask = nil
        conversation.jobsStarted = false
        conversation.jobs = []
        stopDiagnosticSampler()
        finishDiagnosticVisit(leaveMs: Int(Date().timeIntervalSince(leaveStarted) * 1000))
        conversation.coordinatorStarted = false
        conversation.isFollowing = false
        if let coordinator = conversation.coordinator {
            conversation.coordinator = nil
            Task { await coordinator.stop() }
        }
        if selectedSession?.sessionId == session.sessionId {
            selectedSession = nil
        }
        recordDiagnostic("离开会话：\(session.displayTitle) 内存 \(String(format: "%.1f", Self.memoryFootprintMB())) MB 会话页 \(ConversationViewLifetime.liveCount)")
    }

    /// 展开某一组过程时才拉取正文。分页按序号切开，不把整段历史再装进内存。
    @MainActor
    func loadProcessDetails(for group: PocketStepGroup) async {
        guard let session = selectedSession else { return }
        let first = group.steps.map(\.sequence).min() ?? group.sequence
        let last = group.steps.map(\.sequence).max() ?? group.sequence
        do {
            let page = try await rpc("session/page", args: ["request": [
                "address": ["kind": "session", "sessionId": session.sessionId],
                "throughSeq": last,
                "beforeSeq": last + 1,
                "maxMessages": 4
            ]])
            let records = page["records"] as? [[String: Any]] ?? []
            for record in records {
                guard let event = record["event"] as? [String: Any],
                      let seq = (event["seq"] as? NSNumber)?.intValue,
                      seq >= first, seq <= last else { continue }
                applyStepEvent(event, storeBodies: true)
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
    }
}
