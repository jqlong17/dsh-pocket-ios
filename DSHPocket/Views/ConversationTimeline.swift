import DSHKit
import SwiftUI

/// `ConversationView` 的「派生数据」层：把 model 的消息/过程/失败记录组装成可渲染条目，
/// 并提供间距、紧凑判定、可发送判断。
///
/// 独立成文件的理由：主 View 已经超过 app 层 600 行阈值，而这一整块是**纯派生**——
/// 不装配视图、不持有滚动状态，只做「数据 → 条目」的换算。放在一起会让
/// 「界面怎么摆」和「条目怎么算」混在同一个文件里，改任何一边都要翻过另一边。
extension ConversationView {
    struct TimelineEntry: Identifiable {
        let id: String
        let sortKey: Int      // 展示排序键（排队消息会被推迟到 turn 结束之后）
        let sequence: Int     // 原始 seq，二级排序保证同一 turn 内排队消息的先后顺序
        let message: PocketMessage?
        let group: PocketStepGroup?
        let failure: TurnFailureNotice?
    }

    /// 是否已经切到本页要显示的会话。切换完成前不渲染，避免首帧闪出上一条的内容。
    var isSwitchedToSession: Bool {
        model.activeSessionId == session.sessionId
    }

    /// 最近几条消息保持完整渲染，其余只做纯文本摘要。
    ///
    /// 这是**正式行为**（2026-11-21 用户拍板，不再作为实验）。
    ///
    /// 2026-11-22 从 3 提到 10：3 条导致往上翻两屏就全是摘要，
    /// 用户反馈「消息看着不完整」。10 条≈两屏完整 Markdown，
    /// 按之前实测（24 条 = 21-25ms/帧，3 条 ≈16.7ms）推算 10 条约 17-19ms，仍可接受。
    static let fullRenderRecentCount = 10

    /// 这条消息是否属于「更早的历史」（走精简渲染）。
    ///
    /// 按**消息**而不是按时间/顺序：工具步骤不占「条数」，避免把最新 3 条
    /// 全算成 step group 而导致最新回复也被降级。
    func isCompactMessage(_ entry: TimelineEntry) -> Bool {
        // 完整模式：不做 Markdown 精简，全部完整渲染。
        guard !model.showToolProcess else { return false }
        guard let messageId = entry.message?.id else { return false }
        let recentIds = messagesRecentFirst.prefix(Self.fullRenderRecentCount).map(\.id)
        return !recentIds.contains(messageId)
    }

    /// 消息按「新的在前」排列的 ID（只算消息，不含 process 行）。
    var messagesRecentFirst: [PocketMessage] {
        model.messages.sorted { left, right in
            let l = model.displaySortKey(for: left)
            let r = model.displaySortKey(for: right)
            if l != r { return l > r }
            return (left.sequence ?? 0) > (right.sequence ?? 0)
        }
    }

    var entries: [TimelineEntry] {
        guard isSwitchedToSession else { return [] }
        // 计时：把「一次重排要多久」量化出来，否则「卡不卡」只能凭感觉。
        let renderStarted = CFAbsoluteTimeGetCurrent()
        defer {
            model.lastRenderMs = (CFAbsoluteTimeGetCurrent() - renderStarted) * 1000
            model.lastRenderMessageCount = model.messages.count
            model.lastRenderStepGroupCount = model.stepGroups.count
        }
        // 排序规则在 DSHKit（可测）；这里只负责把元素映射成排序键、再映射回来。
        var byID: [String: TimelineEntry] = [:]
        var keys: [TimelineSortKey] = []
        // 同一个 turn 的连续助手消息合并成一条（2026-11-22 用户要求，与桌面端一致）。
        // 做法是「合成一条 PocketMessage」：text 用空行拼接，id/sequence 取第一条，
        // 这样 MessageRow 完全不用改，风险最小。
        // 精简模式（默认）：不显示过程、按 turn 合并成一个回复块。
        // 完整模式：显示过程、逐条展示（合并会把过程打乱，所以模式二不合并）。
        let compact = !model.showToolProcess
        let mergedMessages = compact ? ConnectionModel.mergeByTurn(model.messages) : model.messages
        model.lastRawMessageCount = model.messages.count
        model.lastMergedMessageCount = mergedMessages.count
        model.lastTurnParsedCount = model.messages.filter { $0.turn != nil }.count
        for message in mergedMessages {
            let entry = TimelineEntry(id: message.id,
                                      sortKey: model.displaySortKey(for: message),
                                      sequence: message.sequence,
                                      message: message, group: nil, failure: nil)
            byID[entry.id] = entry
            keys.append(TimelineSortKey(id: entry.id, sortKey: entry.sortKey, sequence: entry.sequence,
                                        isMessage: true, isPending: message.isPending,
                                        localOrder: message.localOrder))
        }
        // 过程（工具调用折叠行）只在完整模式显示；精简模式下用户明确「不关心过程」。
        if !compact {
            for group in model.stepGroups {
                let entry = TimelineEntry(id: group.id, sortKey: group.sequence, sequence: group.sequence,
                                          message: nil, group: group, failure: nil)
                byID[entry.id] = entry
                keys.append(TimelineSortKey(id: entry.id, sortKey: entry.sortKey,
                                            sequence: entry.sequence, isMessage: false))
            }
        }
        for failure in model.turnFailures {
            let entry = TimelineEntry(id: failure.id, sortKey: failure.sequence, sequence: failure.sequence,
                                      message: nil, group: nil, failure: failure)
            byID[entry.id] = entry
            keys.append(TimelineSortKey(id: entry.id, sortKey: entry.sortKey,
                                        sequence: entry.sequence, isMessage: false))
        }
        return TimelineAssembly.ordered(keys).compactMap { byID[$0.id] }
    }



    /// 离开底部之后到达的助手回复条数（用户自己的消息不算）。

    static func messageSpacing(previous: TimelineEntry, current: TimelineEntry) -> CGFloat {
        // 节奏规则在 DSHKit（可测）：同人 8、换角色 18、过程行/失败卡 10。
        CGFloat(TimelineSpacing.between(
            previousIsGroup: previous.group != nil || previous.failure != nil,
            currentIsGroup: current.group != nil || current.failure != nil,
            previousIsUser: previous.message?.isUser,
            currentIsUser: current.message?.isUser
        ))
    }

    var canSend: Bool {
        // 发送中必须禁止再点：`sendMessage` 在上一条未完成时是**直接丢弃**新消息的
        // （压测实测连发 8 条只成功 1 条）。置灰让用户明确知道要等，
        // 而不是以为发了其实没发。
        guard !model.isSending else { return false }
        return !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !model.draftImages.isEmpty
    }

    /// 复制成功：一次轻震动 + 一条「已复制」。
}
