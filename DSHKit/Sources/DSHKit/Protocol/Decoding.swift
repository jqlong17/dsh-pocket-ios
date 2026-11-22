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

    /// 宽松地把 JSON 里的数字转成 Int（NSNumber / Int / Double / String 都接受）。
    ///
    /// 只写 `as? NSNumber` 会在某些桥接路径下拿不到值（实测 turn 恒为 nil），
    /// 所以这里把常见类型都试一遍。
    public static func intValue(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int: return value
        case let value as NSNumber: return value.intValue
        case let value as Double: return Int(value)
        case let value as String: return Int(value)
        default: return nil
        }
    }

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
            images: images,
            turn: DSHDecoding.intValue(data["turn"])
        )
    }

    // MARK: Event → Step / Turn

    public static func stepEvent(fromEvent event: [String: Any]) -> DSHStepEvent? {
        guard let type = event["type"] as? String,
              let sequence = (event["seq"] as? NSNumber)?.intValue else { return nil }
        // `data` 缺失按空对象处理：turn/start、turn/end 的 data 可以为空。
        let data = event["data"] as? [String: Any] ?? [:]
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
            // callId 的位置随服务端版本变化：data.toolCallId / message.toolCallId /
            // data.callId（App 旧解析读这里）/ message.source.callId，依次兜底。
            let callId = (data["toolCallId"] as? String)
                ?? (message?["toolCallId"] as? String)
                ?? (data["callId"] as? String)
                ?? ((message?["source"] as? [String: Any])?["callId"] as? String)
                ?? ""
            return .toolResult(seq: sequence, turn: turn,
                               callId: callId, text: text,
                               isError: isError, images: images)
        case "turn/start":
            return .turnStart(seq: sequence, turn: turn)
        case "turn/end":
            return .turnEnd(seq: sequence, turn: turn, failure: turnFailure(from: data))
        default:
            return nil
        }
    }

    /// 解析 `{type:"image", attachment:{...}}`。attachment 字段被拍平时也认。
    static func imageRef(from block: [String: Any]) -> DSHImageRef? {
        guard block["type"] as? String == "image" else { return nil }
        if let attachment = block["attachment"] as? [String: Any] {
            return imageRef(fromAttachment: attachment)
        }
        return block["attachmentId"] != nil ? imageRef(fromAttachment: block) : nil
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

    /// `turn/end` 的 `reason.kind == error`。成功结束或没有 reason 时返回 nil。
    public static func turnFailure(from data: [String: Any]) -> DSHTurnFailure? {
        guard let reason = data["reason"] as? [String: Any],
              (reason["kind"] as? String) == "error",
              let error = reason["error"] as? [String: Any] else { return nil }
        let message = (error["message"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let code = (error["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = (code?.isEmpty == false) ? code : nil
        guard !message.isEmpty || normalizedCode != nil else { return nil }
        return DSHTurnFailure(message: message, code: normalizedCode)
    }

    // MARK: Page

    /// - Parameter requestedMax: 本次请求的 maxMessages。传了才做「满页推断」；
    ///   不传就只看服务端字段（保持旧行为）。
    public static func page(fromValue value: [String: Any], requestedMax: Int? = nil) -> DSHSessionPage {
        let records = value["records"] as? [[String: Any]] ?? []
        // 服务端字段优先；**取不到时**用「满页」推断是否还有更早。
        //
        // 为什么需要推断：实测一个 10357 条消息的会话，客户端只拿到 13 条，
        // 但这里的 hasMore 读出来是 false（服务端字段缺失或字段名不同），
        // 直接导致上滑永远不触发（2026-11-22）。而「返回条数 == 请求上限」
        // 在物理上就意味着「可能还截断过」，宁可多请求一次也不能把历史藏起来。
        // 只认「这一页有没有内容」。
        //
        // 不信任服务端 hasMore：实测 10357 条消息的会话拿到 13 条、hasMore 却是 false，
        // 而客户端拿不到这个字段的原因始终没定位到（WS snapshot 与 HTTP page 两条路都可能丢）。
        // 判据改成「本页非空 ⇒ 可能还有」，下一页真取空时自然停——
        // 最多多一次空请求，代价远低于「历史永远看不到」。
        // 判据：本页装满了请求上限 ⇒ 很可能还有更早的；没装满 ⇒ 已经到底。
        // （用「非空」会在「最早那批恰好一页」时反复请求同一页，所以必须看是否满页。
        //  服务端字段若存在则以它为准——只是实测它常缺失。）
        let fullPage = requestedMax.map { records.count >= $0 } ?? !records.isEmpty
        let hasMore = value["hasMore"] as? Bool ?? fullPage
        // 与实时流共用同一份 record 分发（message/step/title/unknown），避免两处漂移。
        let decoded: [DSHRecord] = DSHDecoding.records(fromRecords: records)
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
