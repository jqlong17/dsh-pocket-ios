// 演示数据和商店截图

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

extension ConnectionModel {

    @MainActor
    func startDemoMode() {
        isDemoMode = true
        connection.isConnected = true
        connection.isConnecting = false
        connection.errorMessage = nil
#if DEBUG
        sessionStore.sessions = DebugLaunch.storeShots ? Self.storeShotSessions : Self.demoSessionList
#else
        sessionStore.sessions = Self.demoSessionList
#endif
        sessionStore.archivedSessionIds = []
        sessionStore.selected = nil
        sessionStore.navigationPath = []
        messages = []
        steps = []
        liveConnection = .demo
#if DEBUG
        let shotList = DebugLaunch.storeShots ? Self.storeShotSessions : Self.demoSessionList
        if let id = DebugLaunch.sessionId, let session = shotList.first(where: { $0.sessionId == id }) {
            sessionStore.navigationPath = [session]
        }
#endif
    }

    @MainActor
    func exitDemoMode() {
        isDemoMode = false
        connection.isConnected = false
        sessionStore.selected = nil
        sessionStore.navigationPath = []
        sessionStore.conversations.removeAll()
        activeConversation = nil
        sessionStore.sessions = []
        draftImages = []
        liveConnection = .idle
    }

    @MainActor
    func openDemo(_ session: PocketSession) {
        liveTask?.cancel()
        let conversation = ConversationState(sessionId: session.sessionId)
        sessionStore.conversations[session.sessionId] = conversation
        activeConversation = conversation
        sessionStore.selected = session
        messages = Self.demoMessages(for: session.sessionId)
        steps = Self.demoSteps(for: session.sessionId)
        isTurnRunning = session.running
        turnStartedAt = session.running ? Date().addingTimeInterval(-37) : nil
        isLoadingConversation = false
        conversationError = nil
        hasMoreOlder = false
        draftImages = []
        liveConnection = .demo
    }

    @MainActor
    func sendDemoMessage() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = draftImages
        guard (!text.isEmpty || !images.isEmpty), sessionStore.selected != nil, !isSending else { return }
        let pending = PocketMessage(pendingText: text, localImages: images.map(\.uiImage))
        messages.append(pending)
        pendingSendID = pending.id
        cancelledDraft = text
        cancelledImages = images
        draft = ""
        draftImages = []
        isSending = true
        defer {
            isSending = false
            pendingSendID = nil
            cancelledDraft = ""
            cancelledImages = []
        }
        recordDiagnostic("演示模式：本地模拟发送")
        try? await Task.sleep(for: .seconds(1))
        if Task.isCancelled { return }
        messages.removeAll { $0.isPending }
        // 演示模式也要保留用户消息（与真实发送一致），否则气泡会消失。
        var nextSequence = (messages.map(\.sequence).max() ?? 0) + 1
        messages.append(PocketMessage(demoText: text, isUser: true, sequence: nextSequence))
        nextSequence += 1
        messages.append(PocketMessage(
            demoText: "（演示模式）这是内置的示例回复，不会真正调用模型。\n\n连接电脑后，消息会发给本机的 DSH，助手回复与工具过程会实时出现在这里。",
            isUser: false, sequence: nextSequence))
        messages.sort { $0.sequence < $1.sequence }
    }

    static func storeShotMessages(for sessionId: String) -> [PocketMessage] {
        let en = LanguageStore.shared.isEnglish
        if sessionId == "shot-media" {
            if en {
                return [
                    PocketMessage(demoText: "The Phone access card in Settings is too cramped. Show me a tighter version.", isUser: true, sequence: 1),
                    PocketMessage(demoText: "One card: the fixed address on top, and a note that the pairing code rotates every 60 seconds and works once. The only button is Copy address.", isUser: false, sequence: 2, localImages: [storeShotPicture])
                ]
            }
            return [
                PocketMessage(demoText: "设置页的「手机访问」卡片太挤了，配一张收紧后的样子。", isUser: true, sequence: 1),
                PocketMessage(demoText: "收成一张卡片：上面是固定地址，下面写配对码 60 秒轮换、用一次即失效。按钮只留「复制地址」。", isUser: false, sequence: 2, localImages: [storeShotPicture])
            ]
        }
        if en {
            return [
                PocketMessage(demoText: "Build an iOS client for DSH. It should reach the sessionStore.sessions on my Mac, and it has to be native — not a web wrapper.", isUser: true, sequence: 1),
                PocketMessage(demoText: "DSH is plugins all the way down. I'll look for a connector in the plugin market, then keep the interface in the app.", isUser: false, sequence: 2),
                PocketMessage(demoText: "Split them. The connector is a plugin. The app only renders sessionStore.sessions, live messages, and images.", isUser: true, sequence: 3),
                PocketMessage(demoText: "That's the split. dsh-pocket-ios handles pairing and forwarding. The app renders the session list, the live stream, and images.", isUser: false, sequence: 4),
                PocketMessage(demoText: "Don't make people type a password after they scan.", isUser: true, sequence: 5),
                PocketMessage(demoText: "The pairing code rotates every 60 seconds and works once. Scan to log in. The address stays on Tailscale.", isUser: false, sequence: 6)
            ]
        }
        return [
            PocketMessage(demoText: "帮我做一个 iOS 版的 DSH，要能连电脑上的会话，原生客户端，不要网页套壳。", isUser: true, sequence: 1),
            PocketMessage(demoText: "可以。DSH 讲究万物皆插件。我先去插件市场找现成的连接能力，界面留在 App 里。", isUser: false, sequence: 2),
            PocketMessage(demoText: "连接和界面拆开。连接做成插件，App 只负责会话、实时消息和图片。", isUser: true, sequence: 3),
            PocketMessage(demoText: "就这么拆。dsh-pocket-ios 负责配对和转发，App 渲染会话列表、实时流和图片。", isUser: false, sequence: 4),
            PocketMessage(demoText: "扫码那一步别让用户再填密码。", isUser: true, sequence: 5),
            PocketMessage(demoText: "配对码 60 秒轮换，用一次就失效。扫完直接登录。地址走 Tailscale，换网络也不用重扫。", isUser: false, sequence: 6)
        ]
    }

    static func demoMessages(for sessionId: String) -> [PocketMessage] {
#if DEBUG
        if DebugLaunch.storeShots { return storeShotMessages(for: sessionId) }
#endif
        switch sessionId {
        case "demo-1":
            return [
                PocketMessage(demoText: "帮我做一个 iOS 版的 DSH：要能连我电脑上的会话，原生客户端，不要网页套壳。",
                              isUser: true, sequence: 1),
                PocketMessage(demoText: "可以。DSH 讲究「万物皆插件」，我先去插件市场找现成能力，再组装起来。",
                              isUser: false, sequence: 2),
                PocketMessage(demoText: """
                搞定了，整个客户端是这样拼出来的：

                | 层 | 插件 | 作用 |
                | --- | --- | --- |
                | 连接 | dsh-pocket-ios | 把手机接到电脑上的 DSH |
                | 用量 | dsh-usage | 余额与 Token 统计 |
                | 转写 | parse-convert | 语音/链接转文字 |

                ### 已经完成

                - 原生 SwiftUI 客户端：会话、实时流、图片、Markdown
                - 扫码即连，局域网 / Tailscale / 公网三种通道
                - 模拟器已跑通，会话历史和电脑端实时同步

                想再加什么能力，直接去插件市场里装一个就行。
                """, isUser: false, sequence: 7)
            ]
        case "demo-2":
            return [
                PocketMessage(demoText: "DSH 的插件市场里都有什么好玩的？", isUser: true, sequence: 1),
                PocketMessage(demoText: """
                DSH 的理念就是「万物皆插件」：连接、工具、界面、技能都能单独装卸。

                | 类别 | 插件举例 | 能做什么 |
                | --- | --- | --- |
                | 连接 | dsh-pocket-ios | 手机远程用电脑上的 DSH |
                | 用量 | dsh-usage | 余额、Token、花费趋势 |
                | 转写 | parse-convert | 视频/音频转文字、提取字幕 |
                | 设计 | huashu-design | 高保真原型、幻灯片、动画 |

                装插件不用改启动器，重启后设置页里就出现新能力。
                """, isUser: false, sequence: 2)
            ]
        case "demo-3":
            return [
                PocketMessage(demoText: "帮我规划东京 5 天行程，住新宿，喜欢咖啡和建筑，不要太赶。",
                              isUser: true, sequence: 1),
                PocketMessage(demoText: """
                按「半天一个重点」排，留出咖啡和散步时间：

                | 天 | 上午 | 下午 | 晚上 |
                | --- | --- | --- | --- |
                | D1 | 抵达 / 新宿 | 都厅展望台 | 思い出横丁 |
                | D2 | 浅草寺 | 隅田川散步 | 神保町旧书店 |
                | D3 | 表参道建筑 | 青山咖啡 | 六本木夜景 |
                | D4 | 代官山 | 中目黑 | 目黑川 |
                | D5 | 筑地 | 银座 | 返程 |

                **小建议**：买一张 Suica，咖啡店按区域就近排，别跨区折返。
                """, isUser: false, sequence: 2)
            ]
        case "demo-4":
            return [
                PocketMessage(demoText: "帮我看下这份体检报告，几个指标是什么意思？",
                              isUser: true, sequence: 1, localImages: [demoPicture]),
                PocketMessage(demoText: """
                整体问题不大，重点关注这三项：

                | 指标 | 结果 | 解读 |
                | --- | --- | --- |
                | 总胆固醇 | 略高 | 先调整饮食，3 个月复查 |
                | 尿酸 | 偏高 | 少喝含糖饮料，多喝水 |
                | 维D | 偏低 | 多晒太阳，必要时补充 |

                其余指标在正常范围。建议把报告带去门诊让医生结合症状判断。
                """, isUser: false, sequence: 2)
            ]
        default:
            return [
                PocketMessage(demoText: "把今天的会议记录整理成行动项，标上负责人。", isUser: true, sequence: 1),
                PocketMessage(demoText: """
                整理好了：

                1. **周三前** 出 Q2 数据口径文档 — @小王
                2. **周四** 和设计确认新版首页 — @小李
                3. **下周一** 给客户发演示环境 — @我
                4. 待定：是否接入第三方登录

                原始记录里没写负责人的两条，我标成「待定」了，确认后我再补。
                """, isUser: false, sequence: 2)
            ]
        }
    }

    static func demoSteps(for sessionId: String) -> [PocketStep] {
#if DEBUG
        if DebugLaunch.storeShots { return [] }
#endif
        guard sessionId == "demo-1" else { return [] }
        return [
            PocketStep(id: "demo-step-1", sequence: 3, turn: 1, number: 1,
                       name: "search", detail: "插件市场 · ios",
                       resultText: "dsh-pocket-ios（连接） · dsh-usage（用量） · huashu-design（设计）",
                       finished: true),
            PocketStep(id: "demo-step-2", sequence: 4, turn: 1, number: 2,
                       name: "bash", detail: "dsh plugin add dsh-pocket-ios",
                       resultText: "installed dsh-pocket-ios@0.2.1", finished: true),
            PocketStep(id: "demo-step-3", sequence: 5, turn: 1, number: 3,
                       name: "write", detail: "生成 SwiftUI 工程 + DSHKit",
                       resultText: "App target / DSHKit 已生成", finished: true),
            PocketStep(id: "demo-step-4", sequence: 6, turn: 1, number: 4,
                       name: "bash", detail: "xcodebuild → BUILD SUCCEEDED",
                       resultText: "模拟器验证通过，会话已同步", finished: true)
        ]
    }
}
