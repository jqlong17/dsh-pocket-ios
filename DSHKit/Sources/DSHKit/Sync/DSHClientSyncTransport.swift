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

    /// 更早一页：beforeSeq 是排他上界，返回 hasMore 标识是否还有更早消息。
    public func olderPage(sessionId: String, beforeSeq: Int, maxMessages: Int) async throws -> DSHSessionPage {
        try await page(sessionId: sessionId, maxMessages: maxMessages, beforeSeq: beforeSeq)
    }
}
