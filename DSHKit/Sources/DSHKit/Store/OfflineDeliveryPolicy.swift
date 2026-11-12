import Foundation

/// 断网积压消息的补发规则。
///
/// 接收侧（AI/服务端）看到的是「一次性涌入的一段话」，
/// 所以要避免两件事：把积压当成打断指令、把延迟消息当成刚说的。
public enum OfflineDeliveryPolicy {
    /// 补发一律排队，不打断当前轮。
    /// 积压的天性是「排着说」，不是「打断」；打断只适用于用户此刻在前台输入。
    public static let deliveryMode = "queue"

    /// 延迟超过这个时长才在正文里标注发送时间，短延迟不打扰阅读。
    public static let annotationThreshold: TimeInterval = 300

    /// 批量补发之间留出的间隔，避开服务端限流。
    public static let interMessageDelay: Duration = .milliseconds(250)

    /// 这条积压要不要在正文里注明原发送时间。
    public static func shouldAnnotate(createdAt: Date, now: Date,
                                      threshold: TimeInterval = annotationThreshold) -> Bool {
        now.timeIntervalSince(createdAt) >= threshold
    }

    /// 给延迟送达的正文加一行来源说明；不需要标注时原样返回。
    public static func annotatedText(_ text: String, createdAt: Date, now: Date,
                                     calendar: Calendar = .current,
                                     threshold: TimeInterval = annotationThreshold) -> String {
        guard shouldAnnotate(createdAt: createdAt, now: now, threshold: threshold) else { return text }
        let comps = calendar.dateComponents([.hour, .minute], from: createdAt)
        let stamp = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        return "（离线期间 \(stamp) 发出）\n\(text)"
    }
}
