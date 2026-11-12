import Foundation

/// 构造 `session/prompt` 的请求体。
///
/// 为什么抽出来：这段结构原先在 performSend 里手拼，其中两条容易写错：
/// - 文本为空时**不能**塞一个空 text block（服务端会当成空消息）；
/// - 图片是 base64 内联在 content 里，字段名 mediaType/data/name 一个都不能差。
/// 放在 DSHKit 之后可以直接断言结构，不必等发到服务端才发现。
public enum PromptPayload {
    public struct Image: Equatable, Sendable {
        public let mediaType: String
        public let base64: String
        public let name: String
        public init(mediaType: String, base64: String, name: String) {
            self.mediaType = mediaType
            self.base64 = base64
            self.name = name
        }
    }

    /// 消息内容块：文本在前、图片按顺序在后，空内容不产生块。
    public static func content(text: String, images: [Image]) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        if !text.isEmpty {
            blocks.append(["type": "text", "text": text])
        }
        for image in images {
            blocks.append([
                "type": "image",
                "mediaType": image.mediaType,
                "data": image.base64,
                "name": image.name
            ])
        }
        return blocks
    }

    /// 完整请求体。
    public static func request(requestId: String,
                               sessionId: String,
                               mode: PromptMode,
                               text: String,
                               images: [Image],
                               timeZone: String) -> [String: Any] {
        [
            "requestId": requestId,
            "sessionId": sessionId,
            "mode": mode.rawValue,
            "content": content(text: text, images: images),
            "clientTimeZone": timeZone
        ]
    }
}
