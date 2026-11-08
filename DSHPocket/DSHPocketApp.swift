import SwiftUI
import VisionKit
import AVFoundation
import Observation
import os

private let pocketLogger = Logger(subsystem: "com.ruska.dsh-pocket-ios", category: "conversation")

private func timingLog(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) DSH_TIMING \(message)"
    NSLog("%@", line)
}

@main
struct DSHPocketApp: App {
    @State private var model = ConnectionModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.light)
        }
    }
}

@Observable
final class ConnectionModel {
    private static let savedServerAddressKey = "dsh-pocket.server-address"
    var serverAddress = UserDefaults.standard.string(forKey: savedServerAddressKey) ?? "http://"
    var pin = ""
    var isConnecting = false
    var errorMessage: String?
    var isConnected = false
    var sessions: [PocketSession] = []
    var archivedSessionIds: Set<String> = []
    var isLoadingSessions = false
    var selectedSession: PocketSession?
    var messages: [PocketMessage] = []
    var draft = ""
    var isSending = false
    var isLoadingConversation = false
    var conversationError: String?
    var liveConnectionState = "未连接"
    var liveDiagnosticHistory: [String] = []
    var liveTask: Task<Void, Never>?

    @MainActor
    func recordDiagnostic(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)"
        liveDiagnosticHistory.append(line)
        if liveDiagnosticHistory.count > 30 { liveDiagnosticHistory.removeFirst(liveDiagnosticHistory.count - 30) }
        NSLog("DSH_DIAG %@", line)
        Self.appendDiagnosticFile(line)
    }

    /// 设备日志不可靠（idevicesyslog 过滤/断连），同时落盘到 App 沙盒，
    /// 可通过 `devicectl device copy from --domain-type appDataContainer` 直接拉取。
    private static func appendDiagnosticFile(_ line: String) {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = directory.appendingPathComponent("diagnostics.log")
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func diagnosticReport() -> String { liveDiagnosticHistory.joined(separator: "\n") }

    @discardableResult
    func useScannedAddress(_ value: String) -> Bool {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host != nil else {
            errorMessage = "二维码中没有有效的 HTTP 或 HTTPS 地址。"
            return false
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        serverAddress = components.string ?? value
        errorMessage = nil
        return true
    }

    @MainActor
    func connect() async {
        errorMessage = nil
        let url: URL
        do {
            url = try Self.serverURL(from: serverAddress)
            serverAddress = url.absoluteString
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "地址格式无效。"
            recordDiagnostic("地址校验失败：\(serverAddress.debugDescription)")
            return
        }
        recordDiagnostic("开始连接：\(url.absoluteString)")
        guard !pin.isEmpty else {
            errorMessage = "请输入访问密码"
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        // 登录请求需要跟随 302 回到 `/?dsh-pocket-auth=1`，代理会借此完成 dsh web 的
        // 启动 token 握手并写入 dsh-auth cookie；因此必须跟随重定向，只是要记录是否发生过。
        let recorder = LoginRedirectRecorder()
        let loginSession = URLSession(configuration: .default, delegate: recorder, delegateQueue: nil)
        defer { loginSession.finishTasksAndInvalidate() }
        do {
            var request = URLRequest(url: url.appending(path: "pocket-login"))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body = URLComponents()
            body.queryItems = [URLQueryItem(name: "token", value: pin)]
            request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            request.httpShouldHandleCookies = true
            let (_, response) = try await loginSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ConnectionError.unexpectedResponse }
            let hasPocketCookie = HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name == "dsh_pocket_token" } ?? false
            recordDiagnostic("登录响应：HTTP \(http.statusCode)，重定向=\(recorder.redirected ? "是" : "否")，pocket cookie=\(hasPocketCookie ? "有" : "无")")
            if http.statusCode == 429 {
                let retryAfter = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
                throw ConnectionError.rateLimited(retryAfter)
            }
            if http.statusCode == 401 || http.statusCode == 403 { throw ConnectionError.invalidPin }
            guard (200..<400).contains(http.statusCode) else { throw ConnectionError.server(http.statusCode) }
            // DSH Pocket 协议：密码正确 → 302 到 `/?dsh-pocket-auth=1` 并种 dsh_pocket_token
            // cookie；密码错误 → 200 + 登录页。以前把 200 当成功，导致错误密码也"连上"
            // 然后在 session/list 上撞 401，提示完全误导。
            guard recorder.redirected || hasPocketCookie else { throw ConnectionError.invalidPin }
            sessions = try await fetchSessions()
            isConnected = true
            UserDefaults.standard.set(serverAddress, forKey: Self.savedServerAddressKey)
            pin = ""
            recordDiagnostic("连接成功：会话 \(sessions.count) 个")
        } catch {
            recordDiagnostic("连接失败：\(error.localizedDescription)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 整理用户输入：去掉首尾空白和零宽字符，缺少协议时补 `http://`。
    private static func normalizedAddress(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        value.removeAll { character in
            character == "\u{200B}" || character == "\u{200C}" || character == "\u{200D}" || character == "\u{FEFF}"
        }
        if !value.contains("://") { value = "http://" + value }
        return value
    }

    private static func serverURL(from rawValue: String) throws -> URL {
        let value = normalizedAddress(rawValue)
        guard !value.isEmpty,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let url = components.url else {
            throw ConnectionError.invalidURL(rawValue)
        }
        return url
    }

    /// 构造 `ws(s)://host[:port]/path`。关键点：`URLComponents.url` 在 path 不以 "/"
    /// 开头时会返回 nil，而 `appendingPathComponent` 对空 path 恰好拼出 "api/remote.mux"。
    /// 这个 nil 曾导致实时 follow 静默不启动、归档查询抛 invalidURL，务必显式补斜杠。
    private static func webSocketURL(from base: URL, path: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let secure = components.scheme == "https"
        components.scheme = secure ? "wss" : "ws"
        var target = components.path
        if !target.hasPrefix("/") { target = "/" + target }
        if target.hasSuffix("/") { target.removeLast() }
        components.path = target + "/" + path
        return components.url
    }

    @MainActor
    func restoreConnection() async {
#if DEBUG
        if let server = DebugLaunch.server {
            serverAddress = server
            if let pin = DebugLaunch.pin { self.pin = pin }
            recordDiagnostic("Debug 自动连接：\(server)")
            await connect()
            return
        }
#endif
        guard UserDefaults.standard.string(forKey: Self.savedServerAddressKey) != nil,
              (try? Self.serverURL(from: serverAddress)) != nil else { return }
        do {
            sessions = try await fetchSessions()
            isConnected = true
            errorMessage = nil
        } catch {
            isConnected = false
            errorMessage = "无法恢复上次连接（\(error.localizedDescription)），请重新输入访问密码。"
        }
    }

    @MainActor
    func disconnect() {
        liveTask?.cancel()
        liveTask = nil
        selectedSession = nil
        messages = []
        sessions = []
        archivedSessionIds = []
        liveConnectionState = "未连接"
        isConnected = false
    }

    @MainActor
    func loadSessions() async {
        guard !isLoadingSessions else { return }
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            sessions = try await fetchSessions()
        } catch {
            errorMessage = "无法读取会话：\(error.localizedDescription)"
        }
    }

    private func fetchSessions() async throws -> [PocketSession] {
        let value = try await rpc("session/list", args: ["_request": ["excludeArchived": true]])
        let items = value["items"] as? [[String: Any]] ?? []
        let sessions = items.compactMap(PocketSession.init(json:))
        if value["archivedSessionsExcluded"] as? Bool == true {
            archivedSessionIds = []
            return sessions
        }
        archivedSessionIds = try await fetchArchivedSessionIds()
        return sessions.filter { !archivedSessionIds.contains($0.sessionId) }
    }

    private func fetchArchivedSessionIds() async throws -> Set<String> {
        guard let base = try? Self.serverURL(from: serverAddress),
              let socketURL = Self.webSocketURL(from: base, path: "api/remote.mux") else {
            throw ConnectionError.invalidURL(serverAddress)
        }
        let socket = URLSession.shared.webSocketTask(with: socketURL)
        let streamId = UUID().uuidString
        let open = StreamOpen(type: "open", streamId: streamId, endpoint: "workspace/follow", payload: ["args": [:]])
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
        guard let requestText = String(data: encoded, encoding: .utf8) else { throw ConnectionError.invalidPayload }
        try await socket.send(.string(requestText))
        while true {
            let frame = try await socket.receive()
            let data: Data
            switch frame {
            case .data(let bytes): data = bytes
            case .string(let text): data = Data(text.utf8)
            @unknown default: continue
            }
            guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  envelope["streamId"] as? String == streamId,
                  envelope["type"] as? String == "item",
                  let value = envelope["value"] as? [String: Any] else { continue }
            guard value["type"] as? String == "baseline",
                  let baseline = value["value"] as? [String: Any],
                  let archived = baseline["archivedSessionIds"] as? [String] else {
                throw ConnectionError.invalidPayload
            }
            return Set(archived)
        }
    }

    @MainActor
    func createSession() async {
        do {
            var request: [String: Any] = [:]
            if let initialized = try? await rpc("workspace/initializeDefault", args: [:]),
               let workspace = initialized["workspace"] as? [String: Any],
               let workspaceId = workspace["workspaceId"] as? String {
                request["workspaceId"] = workspaceId
            }
            let value = try await rpc("session/create", args: ["request": request])
            guard let id = value["sessionId"] as? String else { throw ConnectionError.invalidPayload }
            let session = PocketSession(sessionId: id, updatedAt: Date().timeIntervalSince1970, running: false, blank: true)
            await loadSessions()
            if !sessions.contains(where: { $0.sessionId == id }) { sessions.insert(session, at: 0) }
            open(session)
        } catch {
            errorMessage = "无法创建会话：\(error.localizedDescription)"
        }
    }

    @MainActor
    func open(_ session: PocketSession) {
        liveTask?.cancel()
        selectedSession = session
        liveConnectionState = "正在连接"
        messages = []
        conversationError = nil
        liveTask = Task { await loadConversation(session) }
    }

    @MainActor
    private func loadConversation(_ session: PocketSession) async {
        isLoadingConversation = true
        await follow(session)
        if selectedSession?.sessionId == session.sessionId, isLoadingConversation {
            isLoadingConversation = false
        }
    }

    @MainActor
    private func loadHistory(_ session: PocketSession) async {
        do {
            let address: [String: Any] = ["kind": "session", "sessionId": session.sessionId]
            let page = try await rpc("session/page", args: ["request": ["address": address, "maxMessages": 100]])
            guard selectedSession?.sessionId == session.sessionId else { return }
            let records = page["records"] as? [[String: Any]] ?? []
            let history = records.compactMap(PocketMessage.init(record:))
            mergeMessages(history)
            isLoadingConversation = false
        } catch {
            if error is CancellationError { return }
            guard selectedSession?.sessionId == session.sessionId, messages.isEmpty else { return }
            conversationError = "无法读取历史对话：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func mergeMessages(_ incoming: [PocketMessage]) {
        var bySequence = Dictionary(uniqueKeysWithValues: messages.filter { !$0.isPending }.map { ($0.sequence, $0) })
        for message in incoming where !message.isPending { bySequence[message.sequence] = message }
        let incomingUserTexts = Set(incoming.filter(\.isUser).map(\.text))
        let pending = messages.filter { $0.isPending && !incomingUserTexts.contains($0.text) }
        messages = (Array(bySequence.values) + pending).sorted { $0.sequence < $1.sequence }
        timingLog("model_update incoming=\(incoming.count) total=\(messages.count)")
    }

    @MainActor
    private func pollForReply(_ session: PocketSession, after text: String, afterSequence: Int) async {
        let started = Date()
        timingLog("history_poll_start text=\(text.debugDescription)")
        for _ in 0..<30 {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            guard selectedSession?.sessionId == session.sessionId else { return }
            // 实时 follow 已经把回复送到时就不必再轮询分页了；轮询只作为断流兜底。
            if messages.contains(where: { !$0.isUser && !$0.isPending && $0.sequence > afterSequence }) {
                timingLog("reply_available source=follow total_elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                return
            }
            do {
                let address: [String: Any] = ["kind": "session", "sessionId": session.sessionId]
                let page = try await rpc("session/page", args: ["request": ["address": address, "maxMessages": 100]])
                let incoming = (page["records"] as? [[String: Any]] ?? []).compactMap(PocketMessage.init(record:))
                timingLog("history_poll_result messages=\(incoming.count) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                mergeMessages(incoming)
                if let reply = incoming.first(where: { !$0.isUser && !$0.isPending && $0.sequence > afterSequence }) {
                    timingLog("reply_available source=history seq=\(reply.sequence) chars=\(reply.text.count) total_elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                    recordDiagnostic("历史轮询找到本次助手回复，等待 \(Int(Date().timeIntervalSince(started) * 1000)) 毫秒；内容：\(reply.text)")
                    return
                }
            } catch { }
        }
        recordDiagnostic("历史轮询超时：30 次内未找到本次助手回复")
    }

    @MainActor
    private func follow(_ session: PocketSession) async {
        guard let base = URL(string: serverAddress),
              let socketURL = Self.webSocketURL(from: base, path: "api/remote.mux") else {
            recordDiagnostic("实时连接未启动：地址无效 \(serverAddress.debugDescription)")
            return
        }
        var retryDelay: Duration = .seconds(1)
        var receivedSnapshot = false
        var usedHistoryFallback = false
        while !Task.isCancelled, selectedSession?.sessionId == session.sessionId {
            liveConnectionState = "正在连接"
            let socket = URLSession.shared.webSocketTask(with: socketURL)
            socket.resume()
            recordDiagnostic("实时连接：发起连接")
            pocketLogger.info("follow connecting session=\(session.sessionId, privacy: .public) url=\(socketURL.absoluteString, privacy: .private)")
            let streamId = UUID().uuidString
            let open = StreamOpen(type: "open", streamId: streamId, endpoint: "session/follow", payload: ["args": ["request": ["address": ["kind": "session", "sessionId": session.sessionId], "maxMessages": 100]]])
            do {
                let data = try JSONEncoder().encode(open)
                guard let text = String(data: data, encoding: .utf8) else { throw ConnectionError.invalidPayload }
                try await socket.send(.string(text))
                let heartbeat = Task {
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(for: .seconds(25))
                            try await sendPing(socket)
                        } catch {
                            if !Task.isCancelled { socket.cancel(with: .abnormalClosure, reason: nil) }
                            return
                        }
                    }
                }
                defer { heartbeat.cancel() }
                while !Task.isCancelled {
                    let frame = try await withTaskCancellationHandler {
                        try await socket.receive()
                    } onCancel: {
                        socket.cancel(with: .goingAway, reason: nil)
                    }
                    let data: Data
                    switch frame {
                    case .data(let received): data = received
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: continue
                    }
                    NSLog("DSH_DIAG websocket frame bytes=%ld", data.count)
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          object["streamId"] as? String == streamId,
                          object["type"] as? String == "item",
                          let value = object["value"] as? [String: Any] else {
                        NSLog("DSH_DIAG ignored frame keys=%@ type=%@ streamMatch=%@", (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?.keys.sorted().joined(separator: ",") ?? "invalid", ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String) ?? "nil", (((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["streamId"] as? String) == streamId) ? "yes" : "no")
                        continue
                    }
                    let valueType = value["type"] as? String ?? "未知"
                    if valueType == "snapshot" { receivedSnapshot = true }
                    liveConnectionState = "已连接"
                    if conversationError?.hasPrefix("实时连接") == true { conversationError = nil }
                    retryDelay = .seconds(1)
                    pocketLogger.info("follow item valueType=\(valueType, privacy: .public) keys=\(value.keys.sorted().joined(separator: ","), privacy: .public)")
                    acceptLive(value, sessionId: session.sessionId)
                }
                if !Task.isCancelled { throw ConnectionError.remote("实时连接已结束") }
            } catch {
                socket.cancel(with: .goingAway, reason: nil)
                guard !Task.isCancelled else { break }
                liveConnectionState = "正在重连"
                conversationError = "实时连接中断，正在重连：\(error.localizedDescription)"
                recordDiagnostic("实时连接中断，\(Int(retryDelay.components.seconds)) 秒后重试：\(error.localizedDescription)")
                pocketLogger.error("follow failed: \(error.localizedDescription, privacy: .public)")
                if !receivedSnapshot && !usedHistoryFallback {
                    usedHistoryFallback = true
                    await loadHistory(session)
                }
                do { try await Task.sleep(for: retryDelay) } catch { break }
                retryDelay = min(retryDelay * 2, .seconds(15))
            }
        }
        if selectedSession?.sessionId == session.sessionId { liveConnectionState = "已断开" }
    }

    @MainActor
    private func acceptLive(_ value: [String: Any], sessionId: String) {
        guard selectedSession?.sessionId == sessionId else { return }
        if value["type"] as? String == "snapshot" {
            let records = value["records"] as? [[String: Any]] ?? []
            let history = records.compactMap(PocketMessage.init(record:))
            mergeMessages(history)
            recordDiagnostic("收到历史快照：\(history.count) 条消息")
            isLoadingConversation = false
        } else if let event = value["event"] as? [String: Any],
                  let message = PocketMessage(event: event) {
            pocketLogger.info("follow message kind=\(message.kind, privacy: .public) seq=\(message.sequence) chars=\(message.text.count)")
            if let pendingIndex = messages.firstIndex(where: { $0.isPending && $0.isUser && $0.text == message.text }) {
                messages.remove(at: pendingIndex)
            }
            if !messages.contains(where: { !$0.isPending && $0.sequence == message.sequence }) {
                messages.append(message)
                messages.sort { $0.sequence < $1.sequence }
            }
            timingLog("reply_available source=follow kind=\(message.kind) seq=\(message.sequence) chars=\(message.text.count) total_messages=\(messages.count)")
            recordDiagnostic("实时收到\(message.isUser ? "用户" : "助手")消息，序号 \(message.sequence)，\(message.text.count) 字；内容：\(message.text)")
            recordDiagnostic("解析并加入界面数据：\(message.isUser ? "用户" : "助手")消息，序号 \(message.sequence)，当前共 \(messages.count) 条")
        } else if value["type"] as? String == "event" {
            let event = value["event"] as? [String: Any]
            let eventType = event?["type"] as? String
            let eventData = event?["data"] as? [String: Any]
            let sourceKind = (eventData?["source"] as? [String: Any])?["kind"] as? String
            // runtime-context / skill-catalog / time-context 等注入型 user/message 是模型输入，
            // 设计上不显示，也不该写诊断；只有真实用户消息或助手消息解析失败才值得记录。
            if eventType == "assistant/message" || (eventType == "user/message" && sourceKind == "user") {
                recordDiagnostic("消息事件未解析：\(eventType ?? "未知")，source=\(sourceKind ?? "-")，键：\(event?.keys.sorted().joined(separator: ",") ?? "无")")
            }
        } else {
            recordDiagnostic("未识别 follow 数据：\(value.keys.sorted().joined(separator: ","))")
        }
    }

    private func sendPing(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    @MainActor
    func sendMessage() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let session = selectedSession, !isSending else { return }
        let lastSequence = messages.filter { !$0.isPending }.map(\.sequence).max() ?? -1
        let pending = PocketMessage(pendingText: text)
        let sendStarted = Date()
        timingLog("send_typed chars=\(text.count)")
        recordDiagnostic("用户点击发送：\(text.count) 字；内容：\(text)")
        messages.append(pending)
        draft = ""
        isSending = true
        defer { isSending = false }
        do {
            timingLog("prompt_start chars=\(text.count)")
            _ = try await rpc("session/prompt", args: ["request": [
                "requestId": UUID().uuidString,
                "sessionId": session.sessionId,
                "mode": "queue",
                "content": [["type": "text", "text": text]],
                "clientTimeZone": TimeZone.current.identifier
            ]])
            timingLog("prompt_ack elapsed_ms=\(Int(Date().timeIntervalSince(sendStarted) * 1000))")
            recordDiagnostic("服务端已确认发送，耗时 \(Int(Date().timeIntervalSince(sendStarted) * 1000)) 毫秒；内容：\(text)")
            conversationError = nil
            // 先用服务端真实用户消息替换本地待确认消息，保证"用户消息在上、助手回复在下"的顺序；
            // 否则实时回复先到、轮询提前退出时，待确认消息会带着临时序号排在回复后面。
            await loadHistory(session)
            await pollForReply(session, after: text, afterSequence: lastSequence)
        } catch {
            messages.removeAll { $0.id == pending.id }
            draft = text
            conversationError = "发送失败：\(error.localizedDescription)"
        }
    }

    private func rpc(_ endpoint: String, args: [String: Any]) async throws -> [String: Any] {
        let root = try Self.serverURL(from: serverAddress)
        let url = root.appending(path: "api/\(endpoint)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true
        let requestBody: [String: Any] = ["type": "client-request", "rpcId": UUID().uuidString, "method": endpoint, "payload": ["args": args]]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ConnectionError.server((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = envelope["result"] as? [String: Any] else { throw ConnectionError.invalidPayload }
        if result["ok"] as? Bool == false {
            let error = result["error"] as? [String: Any]
            throw ConnectionError.remote(error?["message"] as? String ?? "DSH 请求失败")
        }
        return result["value"] as? [String: Any] ?? [:]
    }
}

struct PocketSession: Identifiable, Hashable {
    let sessionId: String
    let updatedAt: TimeInterval
    let running: Bool
    let blank: Bool
    let title: String?
    let cwd: String?
    var id: String { sessionId }

    init(sessionId: String, updatedAt: TimeInterval, running: Bool, blank: Bool, title: String? = nil, cwd: String? = nil) {
        self.sessionId = sessionId
        self.updatedAt = updatedAt
        self.running = running
        self.blank = blank
        self.title = title
        self.cwd = cwd
    }

    init?(json: [String: Any]) {
        guard let id = json["sessionId"] as? String else { return nil }
        let projection = json["projections"] as? [String: Any]
        let values = projection?["values"] as? [String: Any]
        let title = values?["title"] as? String
        self.init(sessionId: id, updatedAt: json["updatedAt"] as? TimeInterval ?? 0,
                  running: json["running"] as? Bool ?? false, blank: json["blank"] as? Bool ?? false,
                  title: title, cwd: json["cwd"] as? String)
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if blank { return "新会话" }
        if let cwd {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            if !name.isEmpty { return name }
        }
        return "未命名会话"
    }
}

struct PocketMessage: Identifiable {
    let id: String
    let sequence: Int
    let kind: String
    let text: String
    let isUser: Bool
    let isPending: Bool

    init(pendingText: String) {
        self.id = "pending-\(UUID().uuidString)"
        self.sequence = Int.max
        self.kind = "user/message"
        self.text = pendingText
        self.isUser = true
        self.isPending = true
    }

    init?(record: [String: Any]) {
        guard let event = record["event"] as? [String: Any] else { return nil }
        self.init(event: event)
    }

    init?(event: [String: Any]) {
        guard let kind = event["type"] as? String,
              ["user/message", "assistant/message"].contains(kind),
              let sequence = (event["seq"] as? NSNumber)?.intValue,
              let data = event["data"] as? [String: Any] else { return nil }
        let message = (data["message"] as? [String: Any]) ?? data
        // DSH also stores injected runtime context as user/message events. Those
        // are model inputs, not messages the human sent, and must stay out of chat UI.
        if kind == "user/message" {
            let source = (message["source"] as? [String: Any]) ?? (data["source"] as? [String: Any])
            guard source?["kind"] as? String == "user" else { return nil }
        }
        let content = message["content"] as? [[String: Any]] ?? []
        let text = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined()
        guard !text.isEmpty else { return nil }
        self.id = "event-\(sequence)"
        self.sequence = sequence
        self.kind = kind
        self.text = text
        self.isUser = kind == "user/message"
        self.isPending = false
    }
}

private struct StreamOpen: Encodable {
    let type: String
    let streamId: String
    let endpoint: String
    let payload: [String: AnyEncodable]

    init(type: String, streamId: String, endpoint: String, payload: [String: Any]) {
        self.type = type
        self.streamId = streamId
        self.endpoint = endpoint
        self.payload = payload.mapValues(AnyEncodable.init)
    }
}

private struct AnyEncodable: Encodable {
    private let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = value as? String { try container.encode(value) }
        else if let value = value as? Int { try container.encode(value) }
        else if let value = value as? Bool { try container.encode(value) }
        else if let value = value as? [String: Any] { try container.encode(value.mapValues(AnyEncodable.init)) }
        else if let value = value as? [Any] { try container.encode(value.map(AnyEncodable.init)) }
        else { try container.encodeNil() }
    }
}

enum ConnectionError: LocalizedError {
    case invalidPin, unexpectedResponse, invalidPayload, invalidURL(String), server(Int), rateLimited(Int), remote(String)
    var errorDescription: String? {
        switch self {
        case .invalidPin: "密码不正确，请检查后重试。"
        case .unexpectedResponse: "服务器返回了无法识别的响应。"
        case .invalidPayload: "服务器响应格式无效。"
        case .invalidURL(let raw): "地址格式无效：\(raw.debugDescription)。请输入 http://192.0.2.10:3081 这样的地址。"
        case .server(let code): "服务器暂时无法连接（HTTP \(code)）。"
        case .rateLimited(let seconds): "尝试次数过多，请 \(max(seconds, 1)) 秒后再试。"
        case .remote(let message): message
        }
    }
}

/// 只用来记录登录请求是否发生过重定向，重定向本身仍然跟随。
private final class LoginRedirectRecorder: NSObject, URLSessionTaskDelegate {
    private(set) var redirected = false

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirected = true
        completionHandler(request)
    }
}

/// 仅 Debug 生效的自测入口，方便在真机/模拟器上自动连接与复现：
/// --dsh-server http://192.0.2.10:3081 --dsh-pin 12345678 --dsh-open <sessionId> --dsh-send 文本
#if DEBUG
enum DebugLaunch {
    static var server: String? { environment["DSH_SERVER"] ?? value(for: "--dsh-server") }
    static var pin: String? { environment["DSH_PIN"] ?? value(for: "--dsh-pin") }
    static var sessionId: String? { environment["DSH_OPEN"] ?? value(for: "--dsh-open") }
    static var sendText: String? { environment["DSH_SEND"] ?? value(for: "--dsh-send") }

    /// 模拟器用 `SIMCTL_CHILD_DSH_SERVER`，真机用 `DEVICECTL_CHILD_DSH_SERVER`，
    /// 由 simctl / devicectl 去掉前缀后注入进程环境。
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static func value(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif

struct RootView: View {
    @Bindable var model: ConnectionModel
    var body: some View {
        NavigationStack {
            Group {
                if model.isConnected {
                    ConnectedView(model: model)
                } else {
                    ConnectView(model: model)
                }
            }
            .navigationTitle("DSH Pocket")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Color(red: 0.08, green: 0.48, blue: 0.37))
        .task { await model.restoreConnection() }
    }
}

struct ConnectView: View {
    @Bindable var model: ConnectionModel
    @State private var showingScanner = false
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 28, weight: .medium)).foregroundStyle(.green).frame(width: 48, height: 48).background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("连接你的 DSH").font(.headline)
                        Text("输入电脑上的 DSH Pocket 地址和访问密码").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8).listRowBackground(Color.clear)
            }
            Section("主机") {
                HStack(spacing: 10) {
                    TextField("http://192.168.1.10:3081", text: $model.serverAddress).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.URL)
                    Button { showingScanner = true } label: { Image(systemName: "qrcode.viewfinder").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44) }.buttonStyle(.bordered).accessibilityLabel("扫描 Pocket 二维码")
                }
                SecureField("访问密码", text: $model.pin).textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if let error = model.errorMessage { Section { Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.subheadline) } }
            Section {
                Button { Task { await model.connect() } } label: {
                    HStack { Spacer(); if model.isConnecting { ProgressView().padding(.trailing, 6); Text("正在连接") } else { Image(systemName: "arrow.right.circle.fill"); Text("连接") }; Spacer() }.fontWeight(.semibold)
                }.disabled(model.isConnecting)
            }
        }
        .onAppear { model.errorMessage = nil }
        .onChange(of: model.serverAddress) { _, _ in model.errorMessage = nil }
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                QRScannerView { value in if model.useScannedAddress(value) { showingScanner = false } }
                    .navigationTitle("扫描二维码").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingScanner = false } } }
            }
        }
    }
}

struct QRScannerView: View {
    let onCode: (String) -> Void
    var body: some View {
        Group {
            if DataScannerViewController.isSupported {
                if DataScannerViewController.isAvailable { PocketCodeScanner(onCode: onCode).ignoresSafeArea(edges: .bottom) }
                else { ContentUnavailableView("相机暂不可用", systemImage: "camera.fill", description: Text("请在设置中允许 DSH Pocket 使用相机，然后重试。")) }
            } else { ContentUnavailableView("此设备不支持扫码", systemImage: "qrcode", description: Text("请手动输入 DSH Pocket 地址。")) }
        }
    }
}

struct PocketCodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item, let value = barcode.payloadStringValue else { continue }
                onCode(value)
                dataScanner.stopScanning()
                return
            }
        }
    }
}

struct ConnectedView: View {
    @Bindable var model: ConnectionModel
    @State private var didAutoOpen = false
    var body: some View {
        List {
            if let error = model.errorMessage {
                Section { Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red) }
            }
            if model.sessions.isEmpty && !model.isLoadingSessions {
                ContentUnavailableView("还没有会话", systemImage: "bubble.left.and.bubble.right", description: Text("创建会话后即可开始对话。"))
                    .listRowSeparator(.hidden)
            }
            ForEach(model.sessions) { session in
                NavigationLink {
                    ConversationView(model: model)
                        .onAppear { model.open(session) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: session.running ? "ellipsis.bubble.fill" : "bubble.left").foregroundStyle(session.running ? .green : .secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.displayTitle).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                            Text(session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? (session.running ? "正在运行" : "对话记录"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if session.running { Circle().fill(.green).frame(width: 7, height: 7) }
                    }.padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .overlay { if model.isLoadingSessions { ProgressView() } }
        .refreshable { await model.loadSessions() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { model.disconnect() } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }.accessibilityLabel("断开连接") }
            ToolbarItem(placement: .topBarTrailing) { Button { Task { await model.createSession() } } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("新建会话") }
        }
        .navigationTitle("会话")
        .navigationDestination(item: Binding(get: { model.selectedSession }, set: { if $0 == nil { model.selectedSession = nil } })) { _ in ConversationView(model: model) }
        .task {
            if model.sessions.isEmpty { await model.loadSessions() }
#if DEBUG
            if !didAutoOpen, let id = DebugLaunch.sessionId,
               let session = model.sessions.first(where: { $0.sessionId == id }) {
                didAutoOpen = true
                model.open(session)
            }
#endif
        }
    }
}

struct MarkdownBody: View {
    let text: String

    private enum Block {
        case paragraph(String)
        case heading(String)
        case bullet(String)
        case numbered(String, String)
        case code(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let value):
                    // `inlineOnlyPreservingWhitespace` 保留原始换行，避免多行回复被挤成一段。
                    Text(inline(value)).font(.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                case .heading(let value):
                    Text(inline(value)).font(.headline).fixedSize(horizontal: false, vertical: true)
                case .bullet(let value):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").font(.body)
                        Text(inline(value)).font(.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                case .numbered(let marker, let value):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker).font(.body).foregroundStyle(.secondary)
                        Text(inline(value)).font(.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                case .code(let value):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(value)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func inline(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(value)
    }

    /// 按空行/列表/代码块切段。段内保留逐行换行，这是"多行回复能正常换行"的关键。
    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var insideCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if insideCode {
                    result.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    insideCode = false
                } else {
                    flushParagraph()
                    insideCode = true
                }
                continue
            }
            if insideCode {
                codeLines.append(rawLine)
                continue
            }
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                result.append(.bullet(String(line.dropFirst(2))))
            } else if line.hasPrefix("#") {
                flushParagraph()
                result.append(.heading(line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))))
            } else if let match = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let marker = String(line[line.startIndex..<match.upperBound]).trimmingCharacters(in: .whitespaces)
                result.append(.numbered(marker, String(line[match.upperBound...])))
            } else {
                paragraph.append(line)
            }
        }
        if insideCode { result.append(.code(codeLines.joined(separator: "\n"))) }
        flushParagraph()
        return result
    }
}

struct ConversationView: View {
    @Bindable var model: ConnectionModel
    @State private var didAutoSend = false
    var body: some View {
        VStack(spacing: 0) {
            if let error = model.conversationError {
                Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 8).background(.red.opacity(0.06))
            }
            HStack(spacing: 6) {
                Circle().fill(model.liveConnectionState == "已连接" ? .green : .orange).frame(width: 7, height: 7)
                Text("实时连接：\(model.liveConnectionState)").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal).padding(.vertical, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if model.isLoadingConversation && model.messages.isEmpty { ProgressView().padding(.top, 36) }
                        if model.messages.isEmpty && !model.isLoadingConversation { ContentUnavailableView("开始对话", systemImage: "text.bubble", description: Text("发送第一条消息。")) }
                        ForEach(model.messages) { message in
                            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 5) {
                                HStack(spacing: 5) {
                                    if !message.isUser { Image(systemName: "sparkle").foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37)) }
                                    Text(message.isUser ? "你" : "DSH").foregroundStyle(.secondary)
                                }.font(.caption2.weight(.semibold))
                                HStack {
                                    if message.isUser { Spacer(minLength: 48) }
                                    MarkdownBody(text: message.text)
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 14).padding(.vertical, 11)
                                        .background(message.isUser ? Color(red: 0.08, green: 0.48, blue: 0.37) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                        .foregroundStyle(message.isUser ? .white : .primary)
                                    if !message.isUser { Spacer(minLength: 28) }
                                }
                            }.frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading).id(message.id)
                        }
                    }.padding()
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.count) { oldCount, newCount in
                    timingLog("ui_messages_changed old=\(oldCount) new=\(newCount)")
                    if newCount > oldCount, let latest = model.messages.last {
                        model.recordDiagnostic("界面消息列表更新：\(latest.isUser ? "用户" : "助手")消息，序号 \(latest.sequence)，当前共 \(newCount) 条；内容：\(latest.text)")
                    }
                    guard oldCount > 0, newCount > oldCount, let id = model.messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("发送消息", text: $model.draft, axis: .vertical).lineLimit(1...5).padding(.horizontal, 12).padding(.vertical, 9).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                Button { Task { await model.sendMessage() } } label: {
                    if model.isSending { ProgressView().frame(width: 44, height: 44) }
                    else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44).background(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : Color(red: 0.08, green: 0.48, blue: 0.37), in: Circle()) }
                }.disabled(model.isSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("发送消息")
            }.padding(.horizontal).padding(.vertical, 10).background(.background)
        }
        .navigationTitle(model.selectedSession?.title ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = model.diagnosticReport()
                } label: { Image(systemName: "doc.on.doc") }
                .accessibilityLabel("复制诊断记录")
            }
        }
        .task {
#if DEBUG
            if !didAutoSend, let text = DebugLaunch.sendText {
                didAutoSend = true
                try? await Task.sleep(for: .seconds(2))
                model.draft = text
                await model.sendMessage()
            }
#endif
        }
    }
}
