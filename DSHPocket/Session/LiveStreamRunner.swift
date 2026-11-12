// 实时流

import Foundation
import DSHKit

/// `session/follow` 的建连与重连循环：发 open 帧、心跳、收帧、断线退避重连。
///
/// 边界（spec/12）：
/// - 只负责「连接与收帧」，帧内容交给 `onItem`（由 LiveFrameApplier 处理）；
/// - 不碰消息列表、发件箱、过程步骤；
/// - 所有时序参数来自 `LiveStreamPolicy`（心跳、假死阈值、退避），不要在别处写魔法数字。
///
/// 用 extension 而非独立类型（spec/2026-11-12-2257）：自有状态为 0，
/// 原 17 个闭包注入没有换来可测性（App 层无测试 target），只增加间接层。
extension ConnectionModel {
    @MainActor
    func runLiveStream(sessionId: String) async {
        guard !isDemoMode else { return }
        defer { activeConversation?.isFollowing = false }
        // 每次进入循环前重新取地址（地址可能在重连期间被改）。
        guard let base = URL(string: connection.serverAddress),
              let socketURL = Self.webSocketURL(from: base, path: "api/remote.mux") else {
            recordDiagnostic("实时连接未启动：地址无效")
            return
        }
        activeConversation?.isFollowing = true
        var retryDelay: Duration = LiveStreamPolicy.initialReconnectDelay
        var retryCount = 0
        var receivedSnapshot = false
        var usedHistoryFallback = false

        while !Task.isCancelled, (activeConversation?.sessionId == sessionId && sessionStore.selected?.sessionId == sessionId) {
            liveConnection = .connecting
            let socket = URLSession.shared.webSocketTask(with: socketURL)
            socket.resume()
            recordDiagnostic("实时连接：发起连接")
            pocketLogger.info("follow connecting session=\(sessionId) url=\(socketURL.absoluteString)")
            let streamId = UUID().uuidString
            let open = StreamOpen(type: "open", streamId: streamId, endpoint: "session/follow",
                                  payload: ["args": ["request": [
                                    "address": ["kind": "session", "sessionId": sessionId],
                                    "maxMessages": Self.conversationMessageLimit
                                  ]]])
            do {
                let data = try JSONEncoder().encode(open)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ConnectionError.invalidPayload
                }
                try await socket.send(.string(text))
                let heartbeat = Task {
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(for: LiveStreamPolicy.heartbeatInterval)
                            try await Self.sendPing(socket)
                        } catch {
                            if !Task.isCancelled { socket.cancel(with: .abnormalClosure, reason: nil) }
                            return
                        }
                    }
                }
                defer { heartbeat.cancel() }
                while !Task.isCancelled {
                    let frame = try await Self.receiveFrame(socket: socket,
                                                            isTurnRunning: isTurnRunning)
                    guard let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
                          let value = StreamFrames.itemValue(object, streamId: streamId) else {
                        NSLog("DSH_DIAG ignored frame type=%@ streamMatch=%@",
                              String(describing: (try? JSONSerialization.jsonObject(with: frame) as? [String: Any])?["type"]),
                              "?")
                        continue
                    }
                    if value["type"] as? String == "snapshot" { receivedSnapshot = true }
                    liveConnection = .connected
                    if conversationError?.hasPrefix("实时连接") == true {
                        conversationError = nil
                    }
                    // 实时流一恢复就把各会话的断网暂存一并补发。
                    flushQueuedSends()
                    retryDelay = LiveStreamPolicy.initialReconnectDelay
                    acceptLive(value, sessionId: sessionId)
                }
                if !Task.isCancelled { throw ConnectionError.remote("实时连接已结束") }
            } catch {
                socket.cancel(with: .goingAway, reason: nil)
                guard !Task.isCancelled else { break }
                liveConnection = .reconnecting(attempt: retryCount)
                if (error as? URLError)?.code == .cancelled { return }
                conversationError = "实时连接中断，正在重连：\(error.localizedDescription)"
                recordDiagnostic("实时连接中断，\(Int(retryDelay.components.seconds)) 秒后重试：\(error.localizedDescription)")
                pocketLogger.error("follow failed: \(error.localizedDescription)")
                if !receivedSnapshot && !usedHistoryFallback {
                    usedHistoryFallback = true
                    if let s = sessionStore.selected { await loadHistory(s) }
                }
                // 重连多次仍失败时探测登录态：DSH 重启后 browser-auth cookie 会失效，
                // WS 只会一直重连，必须回到连接页重新输入密码。
                if retryCount >= 1, await probeAuthExpired() {
                    handleAuthExpired()
                    return
                }
                do { try await Task.sleep(for: retryDelay) } catch { break }
                retryDelay = LiveStreamPolicy.nextReconnectDelay(after: retryDelay)
                retryCount += 1
            }
        }
        if (activeConversation?.sessionId == sessionId && sessionStore.selected?.sessionId == sessionId) {
            liveConnection = .disconnected(reason: nil)
        }
    }

    /// 重连多次仍失败时探测登录态：DSH 重启后 browser-auth cookie 会失效，
    /// WS 只会一直重连，必须回到连接页重新输入密码。
    @MainActor
    func probeAuthExpired() async -> Bool {
        do {
            _ = try await fetchSessions()
            return false
        } catch let error as ConnectionError {
            return error.isUnauthorized
        } catch {
            return false
        }
    }

    /// 收一帧。生成中要求持续有事件：静默超过阈值即认定假死（公网隧道常见），主动断开重连。
    private static func receiveFrame(socket: URLSessionWebSocketTask,
                                     isTurnRunning: Bool) async throws -> Data {
        let message: URLSessionWebSocketTask.Message
        if isTurnRunning {
            message = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
                group.addTask {
                    try await withTaskCancellationHandler {
                        try await socket.receive()
                    } onCancel: {
                        socket.cancel(with: .goingAway, reason: nil)
                    }
                }
                group.addTask {
                    try await Task.sleep(for: LiveStreamPolicy.runningIdleTimeout)
                    throw ConnectionError.remote("生成中 \(LiveStreamPolicy.runningIdleTimeout) 无实时数据，主动重连")
                }
                guard let first = try await group.next() else {
                    throw ConnectionError.remote("实时连接无数据")
                }
                group.cancelAll()
                return first
            }
        } else {
            message = try await withTaskCancellationHandler {
                try await socket.receive()
            } onCancel: {
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
        switch message {
        case .data(let bytes): return bytes
        case .string(let text): return Data(text.utf8)
        @unknown default: return Data()
        }
    }

    private static func sendPing(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
