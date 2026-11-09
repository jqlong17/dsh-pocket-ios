import Foundation

/// DSH JSON → 领域模型解码（用例 P20–P40）。
public enum DSHDecoding {
    // MARK: Session

    public static func session(fromJSON json: [String: Any]) -> DSHSession? {
        guard let sessionId = json["sessionId"] as? String else { return nil }
        let projections = (json["projections"] as? [String: Any])?["values"] as? [String: Any]
        let title = projections?["title"] as? String
        return DSHSession(
            sessionId: sessionId,
            updatedAt: (json["updatedAt"] as? NSNumber)?.doubleValue ?? 0,
            running: json["running"] as? Bool ?? false,
            blank: json["blank"] as? Bool ?? false,
            title: title,
            cwd: json["cwd"] as? String,
            origin: json["origin"] as? String,
            parentSessionId: json["parentSessionId"] as? String
        )
    }

    // MARK: Event → Message

    public static func message(fromEvent event: [String: Any]) -> DSHMessage? {
        guard let kind = event["type"] as? String,
              kind == "user/message" || kind == "assistant/message",
              let sequence = (event["seq"] as? NSNumber)?.intValue,
              let data = event["data"] as? [String: Any] else { return nil }

        let payload = (data["message"] as? [String: Any]) ?? data
        let source = (payload["source"] as? [String: Any]) ?? (data["source"] as? [String: Any])
        if kind == "user/message" {
            // 注入上下文（runtime-context/skill-catalog/time-context）不是用户消息。
            guard source?["kind"] as? String == "user" else { return nil }
        }
        let content = payload["content"] as? [[String: Any]] ?? []
        let text = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined()
        let images = content.compactMap(imageRef(from:))
        guard !text.isEmpty || !images.isEmpty else { return nil }
        return DSHMessage(
            id: "event-\(sequence)",
            sequence: sequence,
            kind: kind,
            text: text,
            isUser: kind == "user/message",
            rpcId: RPCId.normalized(source?["rpcId"] as? String),
            images: images
        )
    }

    // MARK: Event → Step / Turn

    public static func stepEvent(fromEvent event: [String: Any]) -> DSHStepEvent? {
        guard let type = event["type"] as? String,
              let sequence = (event["seq"] as? NSNumber)?.intValue,
              let data = event["data"] as? [String: Any] else { return nil }
        let turn = (data["turn"] as? NSNumber)?.intValue ?? 0
        switch type {
        case "tool/call":
            guard let callId = data["callId"] as? String,
                  let name = data["name"] as? String else { return nil }
            let arguments = (data["arguments"] as? String) ?? ""
            return .toolCall(seq: sequence, turn: turn, callId: callId, name: name,
                             detail: argumentDetail(name: name, arguments: arguments),
                             arguments: arguments)
        case "tool/result":
            let message = data["message"] as? [String: Any]
            let content = message?["content"] as? [[String: Any]] ?? []
            let text = content.compactMap { $0["text"] as? String }.joined()
            let isError = (data["isError"] as? Bool) ?? (message?["isError"] as? Bool) ?? false
            let images = content.compactMap { DSHDecoding.imageRef(from: $0) }
            let callId = (data["toolCallId"] as? String)
                ?? (message?["toolCallId"] as? String)
                ?? ((message?["source"] as? [String: Any])?["callId"] as? String)
                ?? ""
            return .toolResult(seq: sequence, turn: turn,
                               callId: callId, text: text,
                               isError: isError, images: images)
        case "turn/start":
            return .turnStart(seq: sequence, turn: turn)
        case "turn/end":
            return .turnEnd(seq: sequence, turn: turn)
        default:
            return nil
        }
    }

    /// 解析 `{type:"image", attachment:{attachmentId, mediaType, width, height, name}}`。
    static func imageRef(from block: [String: Any]) -> DSHImageRef? {
        guard block["type"] as? String == "image",
              let attachment = block["attachment"] as? [String: Any],
              let attachmentId = attachment["attachmentId"] as? String else { return nil }
        return DSHImageRef(
            attachmentId: attachmentId,
            mediaType: attachment["mediaType"] as? String,
            bytes: (attachment["bytes"] as? NSNumber)?.intValue,
            width: (attachment["width"] as? NSNumber)?.intValue,
            height: (attachment["height"] as? NSNumber)?.intValue,
            name: attachment["name"] as? String
        )
    }

    /// 工具调用的"一句话说明"：bash 取命令首行，其余取参数里的路径。
    static func argumentDetail(name: String, arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return arguments
        }
        if name == "bash" {
            let command = object["command"] as? String ?? object["cmd"] as? String ?? ""
            return command.split(separator: "\n").first.map(String.init) ?? command
        }
        let keys = ["path", "file_path", "filePath", "url", "queries", "query", "description"]
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
            if let array = object[key] as? [String], !array.isEmpty { return array.joined(separator: " / ") }
        }
        return name
    }

    // MARK: Page

    public static func page(fromValue value: [String: Any]) -> DSHSessionPage {
        let records = value["records"] as? [[String: Any]] ?? []
        let hasMore = value["hasMore"] as? Bool ?? false
        let decoded: [DSHRecord] = records.compactMap { record in
            if let event = record["event"] as? [String: Any] {
                if let message = message(fromEvent: event) { return .message(message) }
                if let step = stepEvent(fromEvent: event) { return .step(step) }
                if event["type"] as? String == "session/title",
                   let seq = (event["seq"] as? NSNumber)?.intValue,
                   let data = event["data"] as? [String: Any],
                   let title = data["title"] as? String {
                    return .title(seq: seq, title: title)
                }
            }
            return .unknown
        }
        return DSHSessionPage(records: decoded, hasMore: hasMore)
    }

    // MARK: assistant-stream

    public static func streamFrame(fromJSON json: [String: Any]) -> DSHStreamFrame? {
        guard json["type"] as? String == "assistant-stream",
              let frame = json["frame"] as? [String: Any] else { return nil }
        let attemptId = (frame["attemptId"] as? String) ?? ""
        switch frame["type"] as? String {
        case "start":
            return .start(attemptId: attemptId,
                          turn: (frame["turn"] as? NSNumber)?.intValue ?? 0,
                          step: (frame["step"] as? NSNumber)?.intValue ?? 0)
        case "chunk":
            let chunk = frame["chunk"] as? [String: Any] ?? [:]
            switch chunk["type"] as? String {
            case "text-delta":
                return .textDelta(attemptId: attemptId,
                                  index: (frame["index"] as? NSNumber)?.intValue ?? 0,
                                  text: chunk["text"] as? String ?? "")
            default:
                return .other
            }
        case "end":
            let outcome = (frame["outcome"] as? [String: Any])?["kind"] as? String
            return .end(attemptId: attemptId, outcome: outcome)
        default:
            return nil
        }
    }
}
