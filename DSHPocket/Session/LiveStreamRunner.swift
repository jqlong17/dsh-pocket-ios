// LiveStreamRunner

import Foundation
import DSHKit

/// `session/follow` 的建连与重连循环：发 open 帧、心跳、收帧、断线退避重连。
///
/// 边界（spec/12）：
/// - 只负责「连接与收帧」，帧内容交给 `onItem`（由 LiveFrameApplier 处理）；
/// - 不碰消息列表、发件箱、过程步骤；
/// - 所有时序参数来自 `LiveStreamPolicy`（心跳、假死阈值、退避），不要在别处写魔法数字。
///
/// 依赖全部注入：它需要知道「当前是不是这条会话」「是否在生成中」「断线该不该重新登录」，
/// 但这些判断属于模型，不该被搬到流循环里。
final class LiveStreamRunner {
    struct Providers {
        var isDemoMode: () -> Bool
        /// 当前 WebSocket 地址（每次重连重新取，地址可能变）。
        var socketURL: () throws -> URL
        /// 这一帧/这个循环是否仍属于当前会话。
        var isCurrentSession: (String) -> Bool
        var setFollowing: (Bool) -> Void
        var setConnection: (LiveConnectionState) -> Void
        var conversationError: () -> String?
        var setConversationError: (String?) -> Void
        var isTurnRunning: () -> Bool
        var record: (String) -> Void
        var log: (String) -> Void
        var logError: (String) -> Void
        /// 收到一帧（已确认 streamId 匹配）。
        var onItem: ([String: Any], String) -> Void
        /// 实时流恢复后：把断网暂存一并补发。
        var flushQueued: () -> Void
        var loadHistory: () async -> Void
        /// 重连多次失败后探测登录态；返回 true 表示已失效。
        var authExpired: () async -> Bool
        var onAuthExpired: () -> Void
        var maxMessages: Int
    }

    var providers: Providers?

    func run(sessionId: String) async {
        guard let providers, !providers.isDemoMode() else { return }
        defer { providers.setFollowing(false) }
        let socketURL: URL
        do {
            socketURL = try providers.socketURL()
        } catch {
            providers.record("实时连接未启动：地址无效")
            return
        }
        providers.setFollowing(true)
        var retryDelay: Duration = LiveStreamPolicy.initialReconnectDelay
        var retryCount = 0
        var receivedSnapshot = false
        var usedHistoryFallback = false

        while !Task.isCancelled, providers.isCurrentSession(sessionId) {
            providers.setConnection(.connecting)
            let socket = URLSession.shared.webSocketTask(with: socketURL)
            socket.resume()
            providers.record("实时连接：发起连接")
            providers.log("follow connecting session=\(sessionId) url=\(socketURL.absoluteString)")
            let streamId = UUID().uuidString
            let open = StreamOpen(type: "open", streamId: streamId, endpoint: "session/follow",
                                  payload: ["args": ["request": [
                                    "address": ["kind": "session", "sessionId": sessionId],
                                    "maxMessages": providers.maxMessages
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
                                                            isTurnRunning: providers.isTurnRunning())
                    guard let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
                          let value = StreamFrames.itemValue(object, streamId: streamId) else {
                        NSLog("DSH_DIAG ignored frame type=%@ streamMatch=%@",
                              String(describing: (try? JSONSerialization.jsonObject(with: frame) as? [String: Any])?["type"]),
                              "?")
                        continue
                    }
                    if value["type"] as? String == "snapshot" { receivedSnapshot = true }
                    providers.setConnection(.connected)
                    if providers.conversationError()?.hasPrefix("实时连接") == true {
                        providers.setConversationError(nil)
                    }
                    // 实时流一恢复就把各会话的断网暂存一并补发。
                    providers.flushQueued()
                    retryDelay = LiveStreamPolicy.initialReconnectDelay
                    providers.onItem(value, sessionId)
                }
                if !Task.isCancelled { throw ConnectionError.remote("实时连接已结束") }
            } catch {
                socket.cancel(with: .goingAway, reason: nil)
                guard !Task.isCancelled else { break }
                providers.setConnection(.reconnecting(attempt: retryCount))
                if (error as? URLError)?.code == .cancelled { return }
                providers.setConversationError("实时连接中断，正在重连：\(error.localizedDescription)")
                providers.record("实时连接中断，\(Int(retryDelay.components.seconds)) 秒后重试：\(error.localizedDescription)")
                providers.logError("follow failed: \(error.localizedDescription)")
                if !receivedSnapshot && !usedHistoryFallback {
                    usedHistoryFallback = true
                    await providers.loadHistory()
                }
                // 重连多次仍失败时探测登录态：DSH 重启后 browser-auth cookie 会失效，
                // WS 只会一直重连，必须回到连接页重新输入密码。
                if retryCount >= 1, await providers.authExpired() {
                    providers.onAuthExpired()
                    return
                }
                do { try await Task.sleep(for: retryDelay) } catch { break }
                retryDelay = LiveStreamPolicy.nextReconnectDelay(after: retryDelay)
                retryCount += 1
            }
        }
        if providers.isCurrentSession(sessionId) {
            providers.setConnection(.disconnected(reason: nil))
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
