// QuestionInbox

import Foundation
import Observation
import DSHKit

/// `ask_user_question` 卡片的状态机：什么时候该弹出、什么时候收起、怎么提交回答。
///
/// 边界（spec/12）：
/// - 只读写「当前会话的 pendingQuestion」，不持有会话本身；
/// - 不发别的请求，只发 `userQuestions/answer`；
/// - 会话与诊断通过闭包注入，避免反向依赖 ConnectionModel。
@Observable
final class QuestionInbox {
    struct Providers {
        /// 当前打开的会话（用于提交回答时的 sessionId）。
        var sessionId: () -> String?
        /// 当前会话状态（读写 pendingQuestion / answeredQuestionCallIds）。
        var conversation: () -> ConversationState?
        /// 发请求用的客户端。
        var client: () throws -> DSHClient
        /// 写诊断。
        var record: (String) -> Void
        /// 回答失败时把错误展示给用户。
        var reportError: (String) -> Void
    }

    var providers: Providers?

    /// 历史重放不能把答过的问题再抬出来：只有「还没结果且这一轮没结束」才占输入区。
    @MainActor
    func noteAsked(callId: String, turn: Int, arguments: String) {
        guard let conversation = providers?.conversation() else { return }
        let answered = conversation.answeredQuestionCallIds.contains(callId)
        let turnEnded = conversation.endedTurnNumbers.contains(turn)
        guard PendingQuestionPolicy.shouldShow(hasResult: answered, turnEnded: turnEnded),
              let payload = PendingQuestionPayload.decode(callId: callId, arguments: arguments) else { return }
        conversation.pendingQuestion = PendingUserQuestion(payload: payload)
        conversation.pendingQuestionTurn = turn
    }

    /// 电脑端已经给出结果，或本机刚提交了回答。
    @MainActor
    func noteSettled(callId: String) {
        guard !callId.isEmpty, let conversation = providers?.conversation() else { return }
        conversation.answeredQuestionCallIds.insert(callId)
        if conversation.pendingQuestion?.callId == callId {
            clear()
        }
    }

    @MainActor
    func clear() {
        providers?.conversation()?.pendingQuestion = nil
        providers?.conversation()?.pendingQuestionTurn = nil
    }

    /// 提交回答：选中项与自定义文本一起发回。
    @MainActor
    func answer(_ request: PendingUserQuestion,
                selected: [String: Set<String>],
                custom: [String: String]) {
        guard let providers, let sessionId = providers.sessionId() else { return }
        let answers: [[String: Any]] = request.questions.map { item in
            var answer: [String: Any] = [
                "id": item.id,
                "selected": Array(selected[item.id] ?? [])
            ]
            let text = (custom[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { answer["custom"] = text }
            return answer
        }
        let args: [String: Any] = [
            "agentId": sessionId,
            "callId": request.callId,
            "answer": ["answers": answers]
        ]
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await providers.client().rpcAdapted("userQuestions/answer", args: args)
                self.noteSettled(callId: request.callId)
                providers.record("已回答用户问题：\(request.callId)")
            } catch {
                providers.reportError("回答问题失败：\(error.localizedDescription)")
            }
        }
    }
}
