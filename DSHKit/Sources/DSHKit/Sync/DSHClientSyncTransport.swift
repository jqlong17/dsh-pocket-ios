import Foundation

/// 让 `DSHClient` 作为同步传输使用（模块 02 的生产实现）。
extension DSHClient: SyncTransport {
    public func snapshotPage(sessionId: String, maxMessages: Int) async throws -> DSHSessionPage {
        try await page(sessionId: sessionId, maxMessages: maxMessages)
    }

    public func openFollow(sessionId: String, maxMessages: Int) async throws -> DSHWebSocketConnection {
        let connection = try await connectWebSocket()
        let streamId = UUID().uuidString
        let open = StreamFrames.openFrame(streamId: streamId, sessionId: sessionId, maxMessages: maxMessages)
        let data = try JSONSerialization.data(withJSONObject: open)
        guard let text = String(data: data, encoding: .utf8) else { throw DSHError.invalidPayload }
        try await connection.send(text: text)
        return connection
    }

    /// 历史分页：当前 DSH 版本的分页游标语义待确认，先用同一页接口兜底（去重合并保证幂等）。
    public func olderPage(sessionId: String, beforeSeq: Int, maxMessages: Int) async throws -> DSHSessionPage {
        try await page(sessionId: sessionId, maxMessages: maxMessages)
    }
}
