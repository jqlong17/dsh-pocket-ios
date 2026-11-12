// JobRoster

import Foundation
import DSHKit

/// `job/list` 订阅器：建连、持续接收整份名单、断线指数退避重连。
///
/// 边界（重要）：**不持有名单本身**。名单是会话数据（`ConversationState.jobs`），
/// 本类型只负责「订阅」这件事——因此它是服务而非状态对象，没有业务字段。
/// 同一时刻只维护一条订阅（界面上只有一个可见会话），切换会话时先停再起。
final class JobRoster {
    private var task: Task<Void, Never>?
    private var subscribedSessionId: String?

    /// 当前是否有活跃订阅。
    var isRunning: Bool { task != nil }

    /// 开始订阅。重复调用同一会话是幂等的；换会话会先停掉旧订阅。
    ///
    /// - Parameters:
    ///   - socketURL: 由调用方按当前服务器地址构造（本类型不知道地址从哪来）。
    ///   - sessionId: 订阅哪个会话的任务名单。
    ///   - onRows: 每次收到整份名单时回调（主线程），由调用方写入会话状态。
    @MainActor
    func start(sessionId: String, socketURL: URL,
               onRows: @escaping @MainActor ([PocketJob]) -> Void) {
        if subscribedSessionId == sessionId, task != nil { return }
        stop()
        subscribedSessionId = sessionId
        task = Task { [weak self] in
            await self?.run(sessionId: sessionId, socketURL: socketURL, onRows: onRows)
        }
    }

    @MainActor
    func stop() {
        task?.cancel()
        task = nil
        subscribedSessionId = nil
    }

    private func run(sessionId: String, socketURL: URL,
                     onRows: @escaping @MainActor ([PocketJob]) -> Void) async {
        var retryDelay: Duration = .seconds(2)
        while !Task.isCancelled {
            let socket = URLSession.shared.webSocketTask(with: socketURL)
            socket.resume()
            let streamId = UUID().uuidString
            let open = StreamOpen(type: "open", streamId: streamId, endpoint: "job/list",
                                  payload: ["args": ["request": ["sessionId": sessionId]]])
            do {
                let data = try JSONEncoder().encode(open)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ConnectionError.invalidPayload
                }
                try await socket.send(.string(text))
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let frameData: Data = {
                        if case .string(let s) = message { return s.data(using: .utf8) }
                        if case .data(let d) = message { return d }
                        return nil
                    }() else { continue }
                    guard let object = try JSONSerialization.jsonObject(with: frameData) as? [String: Any],
                          let value = StreamFrames.itemValue(object, streamId: streamId),
                          let rows = DSHJobRoster.rows(fromValue: value) else { continue }
                    let next = rows.map(PocketJob.init(row:))
                    await MainActor.run { onRows(next) }
                }
            } catch {
                if Task.isCancelled { break }
                socket.cancel(with: .goingAway, reason: nil)
                do { try await Task.sleep(for: retryDelay) } catch { break }
                retryDelay = min(retryDelay * 2, .seconds(20))
            }
        }
    }
}
