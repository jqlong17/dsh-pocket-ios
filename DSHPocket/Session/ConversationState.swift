// 单个会话的界面状态

import SwiftUI
import Security
import DSHKit
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import Photos
import os
import AudioToolbox
import ImageIO
import UserNotifications


/// 单个会话独立的展示/发送状态。
/// 切换会话时切换 activeConversation 实例，旧会话数据自然不会出现在新会话里（从结构上隔离）。
@Observable
final class ConversationState {
    let sessionId: String
    /// 该会话自己的输入框草稿（切换会话/退出后恢复）。
    var draft: String = ""
    var draftImages: [PocketDraftImage] = []
    var messages: [PocketMessage] = []
    var steps: [PocketStep] = []
    var isLoadingConversation = false
    var conversationError: String?
    var isTurnRunning = false
    var turnStartedAt: Date?
    var scrollToBottomTick = 0
    /// 最近一次收到实时帧的时间。**故意不参与观察**：
    /// 它每帧都会更新，若参与 @Observable 会让整个 ConversationView 每帧重绘
    /// （进而重算 entries、重解析每条消息的 Markdown），是长会话卡顿的主因。
    /// 唯一用途是「15 秒没帧判定卡住」，不需要触发 UI。
    @ObservationIgnored var lastLiveFrameAt = Date()
    /// 最近实时帧的到达时间（环形缓冲，最多 120 个）。
    /// 用来在诊断报告里给出「帧频率 / 帧间隔」——卡顿时能看出是「没收到帧」还是「收到帧但渲染慢」。
    /// 同样不参与观察：它每帧都变。
    @ObservationIgnored var recentFrameTimes: [Date] = []
    var liveTask: Task<Void, Never>?
    var fallbackTask: Task<Void, Never>?
    /// 后台任务名单（`job/list` 流）。整份替换，不是增量。
    var jobs: [PocketJob] = []
    /// 实时流是否在运行：避免"返回会话时 liveTask 已结束但仍非 nil"导致不再重连。
    var isFollowing = false
    var coordinator: SessionSyncCoordinator?
    var coordinatorTask: Task<Void, Never>?
    var coordinatorStarted = false
    /// 最近一次打开时间。用来决定淘汰哪些会话的内存副本。
    var lastOpenedAt = Date()
    /// 历史分页：是否还有更早消息、是否正在加载、加载前的滚动锚点。
    var hasMoreOlder = false
    /// 分页诊断：上滑触发了几次、成功了几次、最后一次拿到多少条。
    /// 用来区分「上滑没触发」「触发了但服务端没回」「回了但没合并」三种情况。
    var olderLoadAttempts = 0
    var olderLoadSuccesses = 0
    var olderLoadLastAdded = 0
    var olderLoadLastAt: Date?
    var olderLoadLastResult: String?
    var isLoadingOlder = false
    /// 打开会话后是否收到过实时 turn/start、turn/end（用于区分历史快照与实时状态）。
    var liveTurnEventsSeen = false
    /// 正在等待回答的问题（ask_user_question）。电脑上已答过、或那一轮已结束，必须是 nil。
    var pendingQuestion: PendingUserQuestion?
    /// 这张卡片属于哪一轮。那一轮结束就不能再显示。
    var pendingQuestionTurn: Int?
    /// 已经有工具结果的 callId。历史重放时不能把答过的问题再当成待答。
    var answeredQuestionCallIds: Set<String> = []
    /// 已经结束的轮次号。
    var endedTurnNumbers: Set<Int> = []
    var olderAnchorID: String?
    var olderLoadTick = 0
    var conversationToken = UUID()
    var turnStarts: [Int] = []
    var turnEnds: [Int] = []
    /// 这次打开会话的计时。快照到达后写入 lastLoadMs，供右上角诊断。
    var loadStartedAt: Date?
    var loadTimingPending = false
    var lastLoadMs: Int?
    var lastLoadSource: String?
    /// 已结束且失败的轮次，按 seq 展示在时间线里。
    var turnFailures: [TurnFailureNotice] = []
    var ackedRpcIds: Set<String> = []
    /// 已 ACK、但消息体尚未进入历史的 rpcId；保留本地 pending，避免消息"闪一下消失"。
    var acknowledgedRpcIds: Set<String> = []
    var failedRpcIds: Set<String> = []
    /// 断网时暂存的消息：不发失败，等网络回来自动发出。
    var queuedRpcIds: Set<String> = []
    var steeredRpcIds: Set<String> = []

    init(sessionId: String) {
        self.sessionId = sessionId
        self.draft = DraftStore.draft(for: sessionId)
    }

    /// 裁剪到最近 N 条消息（含步骤与失败记录）。
    ///
    /// 调用时机由外部策略决定：
    /// - 会话**仍在看时**用 `inSessionMessageLimit`（允许上滑翻历史，但不无限涨）
    /// - 会话**被切走/退出时**用 `retainedMessageLimit`（卸载旧历史，省内存）
    @MainActor
    func trimMessages(to limit: Int) {
        guard messages.count > limit else { return }
        var remaining = messages
        var removed = 0
        var index = 0
        let target = messages.count - limit
        while removed < target, index < remaining.count {
            if remaining[index].isPending {
                index += 1
            } else {
                remaining.remove(at: index)
                removed += 1
            }
        }
        guard removed > 0 else { return }
        messages = remaining
        let oldestKept = remaining.first?.sequence ?? Int.max
        steps = steps.filter { $0.sequence >= oldestKept }
        turnFailures = turnFailures.filter { $0.sequence >= oldestKept }
    }

}
