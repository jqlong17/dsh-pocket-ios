import Foundation

/// App 侧遥测上报：把「只有手机才知道」的状态送到 Mac，落成 JSONL。
///
/// 为什么需要：`liveState`、`Outbox` 计数、`sinceFrameMs` 这些只在 App 里，
/// Mac 侧只能看到「消息到没到」。两边时间对齐后才能分清
/// - 是网络慢（Mac 侧 ping 也尖）
/// - 还是 App 状态机卡住（Mac 侧一切正常，但 liveState 一直 reconnecting）
///
/// 三条设计约束：
/// 1. **绝不影响主流程**：失败静默、不重试、不弹提示。
/// 2. **不阻塞**：`dataTask` 独立发出即返回，采样回调不等它。
/// 3. **不带敏感内容**：只报状态与计数，不报消息正文、不报 token。
enum TelemetryReporter {
    /// 上报一次。`baseURL` 是当前连接的服务器地址（含 scheme，不含尾斜杠）。
    static func report(_ payload: [String: Any], to baseURL: URL?) {
        guard let baseURL else { return }
        // 只在有会话连接时上报：没连上就没有诊断价值，还会白打请求。
        guard let url = URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/dsh-pocket-ios/telemetry") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 短超时：它是背景流量，不能占着连接不放。
        request.timeoutInterval = 5
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body
        // URLSession.shared 会带上 dsh-auth cookie，服务端据此认身份。
        URLSession.shared.dataTask(with: request) { _, _, _ in
            // 故意忽略结果：上报失败不该影响任何用户可见行为。
        }.resume()
    }
}
