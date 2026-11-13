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
    /// 读取工作区列表（带重试）。
    ///
    /// WebSocket 首连有握手延迟：用户第一次点「调整工作区顺序」时连接可能还没就绪，
    /// 单次尝试会失败并显示空列表；隔一会儿再点就好了（实测）。所以这里重试三次。
    @MainActor
    func loadWorkspaces() async -> [PocketWorkspace] {
        var last: [PocketWorkspace] = []
        for attempt in 0..<3 {
            last = await loadWorkspacesOnce()
            if !last.isEmpty { return last }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        return last
    }

    @MainActor
    private func loadWorkspacesOnce() async -> [PocketWorkspace] {
        guard !isDemoMode else {
            DiagFileLog.log("ws-load skip demo")
            lastWorkspaceLoadError = "演示模式"
            return []
        }
        guard let client = try? rpcClient else {
            DiagFileLog.log("ws-load FAIL no client")
            lastWorkspaceLoadError = "客户端不可用（地址无效）"
            return []
        }
        guard let url = client.webSocketURL() else {
            DiagFileLog.log("ws-load FAIL no url")
            lastWorkspaceLoadError = "WebSocket 地址构造失败"
            return []
        }
        DiagFileLog.log("ws-load start url=\(url.absoluteString)")
        // 必须用 shared：WebSocket 建连要带登录后的认证 cookie，
        // 而 ephemeral session 不共享 cookie storage → 认证失败 → 连不上（踩过）。
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
                guard let message = await Self.receiveWithTimeout(socket, seconds: 3) else {
                    lastWorkspaceLoadError = "读帧超时（3 秒）"
                    return []
                }
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
                    let detail = String(describing: error)
                    imageLog.error("workspace/follow 报错: \(detail, privacy: .public)")
                    DiagFileLog.log("ws-load FAIL server error: \(detail)")
                    lastWorkspaceLoadError = "服务端拒绝：" + detail
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
                DiagFileLog.log("ws-load OK count=\(list.count)")
                lastWorkspaceLoadError = list.isEmpty ? "服务端返回空列表" : nil
                workspaces = list
                if workspaceOrder.isEmpty { workspaceOrder = list.map(\.path) }
                return list
            }
            DiagFileLog.log("ws-load FAIL 20 frames without baseline")
            lastWorkspaceLoadError = "读到 20 帧都不是 baseline"
            return []
        } catch {
            imageLog.error("workspace/follow 连接失败: \(error.localizedDescription, privacy: .public)")
            DiagFileLog.log("ws-load FAIL connect: \(error.localizedDescription)")
            lastWorkspaceLoadError = "连接失败：" + error.localizedDescription
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

    /// `socket.receive()` 本身没有超时：连接没就绪时会一直挂着，用户看到的就是「点了没反应」。
    /// 用 race 包一层，超时返回 nil 让调用方重试。
    private static func receiveWithTimeout(_ socket: URLSessionWebSocketTask,
                                           seconds: Int) async -> URLSessionWebSocketTask.Message? {
        await withTaskGroup(of: URLSessionWebSocketTask.Message?.self) { group in
            group.addTask {
                try? await socket.receive()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }


}
