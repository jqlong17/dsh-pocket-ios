// SessionAPI

import Foundation
import DSHKit

/// 会话列表的只读网络访问：拉摘要、拉工作区标记（归档/置顶）。
///
/// 边界（spec/12）：**只读、只返回结果**，不写任何模型状态。
/// 归档与置顶集由调用方写回 SessionStore——否则这里会反向依赖模型。
///
/// 依赖通过闭包注入：客户端工厂与 WebSocket 地址都随当前服务器地址变化。
final class SessionAPI {
    struct Providers {
        /// 当前可用的 RPC 客户端（地址无效时抛错）。
        var client: () throws -> DSHClient
        /// `api/remote.mux` 的 WebSocket 地址（由服务器地址推导）。
        var socketURL: () throws -> URL
    }

    var providers: Providers?

    /// 列表结果：可见会话 + 需要写回的归档/置顶标记。
    struct Listing {
        let sessions: [PocketSession]
        let archived: Set<String>
        let pinned: [String]
    }

    /// 拉取会话摘要。**不写状态**，由调用方决定怎么落库。
    @MainActor
    func fetchListing() async throws -> Listing {
        guard let providers else { throw ConnectionError.invalidPayload }
        // 列表只拉一份摘要，20 秒还没回来基本就是连不上，早点交给重试。
        let value = try await providers.client()
            .rpcAdapted("session/list", args: ["_request": ["excludeArchived": true]], timeout: 20)
        let items = value["items"] as? [[String: Any]] ?? []
        let sessions = items.compactMap(PocketSession.init(json:))
        // 服务端已排除归档时不必再拉工作区标记。
        guard value["archivedSessionsExcluded"] as? Bool != true else {
            return Listing(sessions: sessions.filter(visible), archived: [], pinned: [])
        }
        let flags = try await fetchWorkspaceFlags()
        return Listing(sessions: sessions.filter { !flags.archived.contains($0.sessionId) && visible($0) },
                       archived: flags.archived,
                       pinned: flags.pinned)
    }

    /// 与 DSH 桌面端侧边栏保持一致：隐藏已归档、subagent 子会话和空会话。
    private func visible(_ session: PocketSession) -> Bool {
        !session.isSubagent && !session.isHiddenFromList
    }

    /// 从 `workspace/follow` 的首帧基线读出归档与置顶。
    @MainActor
    func fetchWorkspaceFlags() async throws -> (archived: Set<String>, pinned: [String]) {
        guard let providers else { throw ConnectionError.invalidPayload }
        let socket = URLSession.shared.webSocketTask(with: try providers.socketURL())
        let streamId = UUID().uuidString
        let open = StreamOpen(type: "open", streamId: streamId, endpoint: "workspace/follow",
                              payload: ["args": [:]])
        // 5 秒拿不到基线就当失败：列表刷新不该被一个后台流拖住。
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer {
            timeout.cancel()
            socket.cancel(with: .goingAway, reason: nil)
        }
        socket.resume()
        let encoded = try JSONEncoder().encode(open)
        guard let requestText = String(data: encoded, encoding: .utf8) else {
            throw ConnectionError.invalidPayload
        }
        try await socket.send(.string(requestText))
        while true {
            let frame = try await socket.receive()
            let data: Data
            switch frame {
            case .data(let bytes): data = bytes
            case .string(let text): data = Data(text.utf8)
            @unknown default: continue
            }
            // 帧结构判断在 DSHKit（可测）；这里只处理结果。
            switch WorkspaceBaseline.decode(frame: data, streamId: streamId) {
            case .skip:
                continue
            case .malformed:
                throw ConnectionError.invalidPayload
            case .baseline(let decoded):
                return (decoded.archived, decoded.pinned)
            }
        }
    }
}
