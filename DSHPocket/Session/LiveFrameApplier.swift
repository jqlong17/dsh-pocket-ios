// 实时帧处理

import Foundation
import DSHKit

/// 处理一帧实时数据：快照 / 消息 / steer 收件箱 / 过程事件。
///
/// 边界（spec/12）：
/// - 只做「把帧写进当前会话」这件事，不负责建连、重连、心跳（那些在 follow 循环里）；
/// - 全部依赖闭包注入：它要改消息列表、发件箱标记、过程步骤，但模型不该反过来知道帧的形态。
/// - 帧**分类**不在这里，而在 `LiveFrameRouter`（DSHKit，可测）。
extension ConnectionModel {
    @MainActor
    func acceptLive(_ value: [String: Any], sessionId: String) {
        guard activeConversation?.sessionId == sessionId,
              sessionStore.selected?.sessionId == sessionId else { return }
        lastLiveFrameAt = Date()
        // 帧类型判定在 DSHKit（可测）：快照 / 消息 / steer 收件箱 / 过程事件 / 认不出。
        switch LiveFrameRouter.kind(of: value) {
        case .snapshot:
            let records = value["records"] as? [[String: Any]] ?? []
            let history = records.compactMap(PocketMessage.init(record:))
            mergeMessages(history)
            mergeSteps(from: records)
            confirmInboxOutbox(in: records)
            recordDiagnostic("收到历史快照：\(history.count) 条消息")
            isLoadingConversation = false
            if let conversation = activeConversation { noteLoadFinished(source: "follow", conversation: conversation) }
            if messages.isEmpty { requestScrollToBottom() }

        case .message:
            guard let event = value["event"] as? [String: Any],
                  let message = PocketMessage(event: event) else { return }
            pocketLogger.info("follow message kind=\(message.kind) seq=\(message.sequence) chars=\(message.text.count)")
            var list = messages
            // 服务端回显的用户消息要把本地待确认气泡顶掉，否则会重复两条。
            if let pendingIndex = list.firstIndex(where: { pending in
                pending.isPending && pending.isUser && (pending.text == message.text
                    || (pending.rpcId != nil && pending.rpcId == message.rpcId))
            }) {
                list.remove(at: pendingIndex)
            }
            if message.isUser, let rpcId = message.rpcId {
                confirmOutbox(rpcIds: [rpcId])
            }
            if !list.contains(where: { !$0.isPending && $0.sequence == message.sequence }) {
                list.append(message)
                list.sort { $0.sequence < $1.sequence }
            }
            messages = list
            timingLog("reply_available source=follow kind=\(message.kind) seq=\(message.sequence) chars=\(message.text.count) total_messages=\(list.count)")
            recordDiagnostic("实时收到\(message.isUser ? "用户" : "助手")消息，序号 \(message.sequence)，\(message.text.count) 字")

        case .steerInbox:
            guard let event = value["event"] as? [String: Any] else { return }
            // steer 消息先进 agent inbox（spliced），这里也视为已送达，避免误报失败。
            let ids = LiveFrameRouter.steerInboxRpcIds(from: event)
            if !ids.isEmpty {
                confirmOutbox(rpcIds: ids)
                ackedSendRpcIds.subtract(ids)
                failedSendRpcIds.subtract(ids)
                conversationError = nil
                recordDiagnostic("steer 已进入收件箱（\(ids.count) 条），等待注入")
            }
            applyStepEvent(event)

        case .event:
            guard let event = value["event"] as? [String: Any] else { return }
            applyStepEvent(event)
            let described = LiveFrameRouter.describe(value)
            if described.type == "assistant/message"
                || (described.type == "user/message" && described.sourceKind == "user") {
                recordDiagnostic("消息事件未解析：\(described.type)，source=\(described.sourceKind ?? "-")")
            }

        case .unknown:
            recordDiagnostic("未识别 follow 数据：\(value.keys.sorted().joined(separator: ","))")
        }
    }
}
