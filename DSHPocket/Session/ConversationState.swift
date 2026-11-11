// 单个会话的界面状态

import SwiftUI
import Security
import Textual
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
    var lastLiveFrameAt = Date()
    var liveTask: Task<Void, Never>?
    var fallbackTask: Task<Void, Never>?
    /// 后台任务名单（`job/list` 流）。整份替换，不是增量。
    var jobs: [PocketJob] = []
    var jobsTask: Task<Void, Never>?
    var jobsStarted = false
    /// 实时流是否在运行：避免"返回会话时 liveTask 已结束但仍非 nil"导致不再重连。
    var isFollowing = false
    var coordinator: SessionSyncCoordinator?
    var coordinatorTask: Task<Void, Never>?
    var coordinatorStarted = false
    /// 历史分页：是否还有更早消息、是否正在加载、加载前的滚动锚点。
    var hasMoreOlder = false
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
}
