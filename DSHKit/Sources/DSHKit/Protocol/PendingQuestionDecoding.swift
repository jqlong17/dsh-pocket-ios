import Foundation

/// `ask_user_question` 的结构化载荷。
///
/// 定义在 DSHKit 而不是 App：解析属于纯逻辑，必须能脱离 UI 单测
/// （spec/12 的「判断可测、IO 隔离」）。App 侧的同名类型从这里构造。
public struct PendingQuestionPayload: Equatable, Sendable {
    public struct Option: Identifiable, Equatable, Sendable {
        public let label: String
        public let description: String?
        public var id: String { label }
        public init(label: String, description: String?) {
            self.label = label
            self.description = description
        }
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: String
        public let header: String?
        public let question: String
        public let detail: String?
        public let options: [Option]
        public let multiSelect: Bool
        public init(id: String, header: String?, question: String,
                    detail: String?, options: [Option], multiSelect: Bool) {
            self.id = id
            self.header = header
            self.question = question
            self.detail = detail
            self.options = options
            self.multiSelect = multiSelect
        }
    }

    public let callId: String
    public let questions: [Item]
    public init(callId: String, questions: [Item]) {
        self.callId = callId
        self.questions = questions
    }

    /// 解析工具调用的 arguments（JSON 字符串）。任何结构不符都返回 nil，不抛错。
    public static func decode(callId: String, arguments: String) -> PendingQuestionPayload? {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawQuestions = object["questions"] as? [[String: Any]] else { return nil }
        let items: [Item] = rawQuestions.compactMap { raw in
            guard let id = raw["id"] as? String,
                  let question = raw["question"] as? String else { return nil }
            let options: [Option] = (raw["options"] as? [[String: Any]] ?? []).compactMap { opt in
                guard let label = opt["label"] as? String else { return nil }
                return Option(label: label, description: opt["description"] as? String)
            }
            return Item(id: id,
                        header: raw["header"] as? String,
                        question: question,
                        detail: raw["detail"] as? String,
                        options: options,
                        multiSelect: raw["multiSelect"] as? Bool ?? false)
        }
        guard !items.isEmpty else { return nil }
        return PendingQuestionPayload(callId: callId, questions: items)
    }
}
