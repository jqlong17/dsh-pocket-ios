// 工作区（新建会话时选择）

import Foundation
import DSHKit

/// 工作区列表与「默认工作区」的读取。
///
/// 为什么单独一个 extension：`workspace/follow` 是 **stream**，要拿首帧后立刻断开，
/// 这套「订阅 + 取消」的时序和普通的请求/响应不一样，挤进 SessionActions 会让那个文件
/// 同时管两种调用形态。
extension ConnectionModel {
    /// 读取全部工作区（只取 `workspace/follow` 的基线帧，拿到即断开）。
    ///
    /// 失败返回空数组——选择器会退回「不传 workspaceId」的旧行为，不会阻止新建会话。
    @MainActor
    func loadWorkspaces() async -> [PocketWorkspace] {
        guard !isDemoMode else { return [] }
        guard let client = try? rpcClient,
              let url = client.webSocketURL() else { return [] }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }

        let streamId = UUID().uuidString
        let open = StreamOpen(type: "open", streamId: streamId, endpoint: "workspace/follow",
                              payload: ["args": [:]] as [String: Any])
        guard let encoded = try? JSONEncoder().encode(open),
              let text = String(data: encoded, encoding: .utf8) else { return [] }
        do {
            try await socket.send(.string(text))
            // 首帧可能是 stream 的 open 确认（type=open）而不是 baseline，
            // 所以要一直读到「type=item 且 streamId 匹配」的那一帧。最多等 20 帧/3 秒。
            for _ in 0..<20 {
                let message = try await socket.receive()
                let frameData: Data? = {
                    if case .string(let s) = message { return s.data(using: .utf8) }
                    if case .data(let d) = message { return d }
                    return nil
                }()
                guard let frameData,
                      let object = try JSONSerialization.jsonObject(with: frameData) as? [String: Any] else {
                    continue
                }
                if let error = object["error"] {
                    imageLog.error("workspace/follow 报错: \(String(describing: error), privacy: .public)")
                    return []
                }
                guard let value = StreamFrames.itemValue(object, streamId: streamId) else { continue }
                var list = WorkspaceParsing.summaries(fromBaselineFrame: value)
                // 工作区自身没有「最后活跃时间」，按 path 从会话里取最新的一条。
                let latestByCwd = Dictionary(
                    sessionStore.sessions.compactMap { session -> (String, TimeInterval)? in
                        guard let cwd = session.cwd, !cwd.isEmpty else { return nil }
                        return (cwd, session.updatedAt)
                    },
                    uniquingKeysWith: { max($0, $1) }
                )
                for index in list.indices {
                    list[index].lastActiveAt = latestByCwd[list[index].path]
                }
                imageLog.info("workspace/follow 拿到 \(list.count) 个工作区")
                workspaces = list
                if workspaceOrder.isEmpty { workspaceOrder = list.map(\.path) }
                return list
            }
            return []
        } catch {
            imageLog.error("workspace/follow 连接失败: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// 默认工作区 id（`workspace/initializeDefault`）。
    @MainActor
    func defaultWorkspaceId() async -> String? {
        guard !isDemoMode else { return nil }
        guard let client = try? rpcClient,
              let value = try? await client.rpcAdapted("workspace/initializeDefault", args: [:]) else {
            return nil
        }
        return WorkspaceParsing.defaultWorkspaceId(fromInitialize: value)
    }

    /// 工作区的手动顺序（目录路径）：拖动后先更新它，界面立即生效。
    /// 与 DSH 桌面端一致——顺序落库在服务端，不只是本地视图。
    @MainActor
    func moveWorkspace(_ workspaceId: String, before beforeWorkspaceId: String?) async {
        guard !isDemoMode else { return }
        // 乐观更新：先记下旧顺序，失败回滚。
        let previousOrder = workspaceOrder
        let known = workspaces
        if let from = known.firstIndex(where: { $0.workspaceId == workspaceId }) {
            var reordered = known
            let moved = reordered.remove(at: from)
            let insertAt: Int
            if let beforeWorkspaceId,
               let target = reordered.firstIndex(where: { $0.workspaceId == beforeWorkspaceId }) {
                insertAt = target
            } else {
                insertAt = reordered.count
            }
            reordered.insert(moved, at: insertAt)
            workspaces = reordered
            workspaceOrder = reordered.map(\.path)
        }

        do {
            let client = try rpcClient
            var request: [String: Any] = ["workspaceId": workspaceId]
            if let beforeWorkspaceId { request["beforeWorkspaceId"] = beforeWorkspaceId }
            _ = try await client.rpcAdapted("workspace/insertBefore", args: ["request": request])
            lastWorkspaceMoveError = nil
        } catch {
            // 回滚到拖动前的顺序，并把失败原因交给界面提示。
            workspaces = known
            workspaceOrder = previousOrder
            lastWorkspaceMoveError = L10n.t("调整顺序失败")
        }
    }
}
