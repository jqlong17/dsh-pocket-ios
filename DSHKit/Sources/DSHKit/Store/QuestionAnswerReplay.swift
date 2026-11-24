import Foundation

/// 问答卡「还会不会再弹出来」的判定（重进会话、重放历史时用）。
///
/// 基准是 DSH 官方 `userQuestions` 投影（`packages/interaction/user-questions/src/projection.ts`）：
///
/// - `tool/call` → 进入可回答集合；
/// - `tool/result` 为 `{"pending":true}`（或错误码 `TOOL_OUTCOME_UNKNOWN`）→ **仍然可回答**
///   （超时后问题留给用户慢慢答）；
/// - `tool/result` 带答案批次 → 已结算；
/// - `tool/result` 是其它成功结果（没有答案）→ 从可回答集合移除；
/// - `user/message` 且 `source.kind == "user-question-reply"` → 用 `source.callId` 结算。
///
/// App 以前只把「已回答」记在内存里，重放快照时把答过的问题又抬出来（2026-11-24 反馈）。
public enum QuestionAnswerReplay {
    /// `tool/result` 的正文是不是「还没答」的 pending 载荷。
    ///
    /// 命中时必须**保持**卡片（该问题仍可回答）；不命中才当成已结算。
    public static func isPendingResult(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["pending"] as? Bool == true
    }
}
