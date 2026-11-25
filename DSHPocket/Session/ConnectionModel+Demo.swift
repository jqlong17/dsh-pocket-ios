// 演示数据和商店截图

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

extension ConnectionModel {

    @MainActor
    func startDemoMode() {
        isDemoMode = true
#if DEBUG
        if DebugLaunch.demoHosts {
            // 两台机器：A 有三条地址（局域网/CF/Tailscale），B 只有一条。
            // UI 测试据此断言「删一条不影响他人」。
            let now = Date().timeIntervalSince1970
            let a = DSHHost(id: "demo-host-a", name: "DSH 1 Mac", endpoints: [
                SavedEndpoint(address: "http://192.168.1.10:3093", kind: .lan, lastUsedAt: now),
                SavedEndpoint(address: "https://demo-a.trycloudflare.com", kind: .publicNetwork, lastUsedAt: now - 1),
                SavedEndpoint(address: "https://demo-a.ts.net", kind: .publicNetwork, lastUsedAt: now - 2),
            ], lastUsedAt: now, machine: "demo-mac")
            let b = DSHHost(id: "demo-host-b", name: "DSH 2 阿里云", endpoints: [
                SavedEndpoint(address: "https://demo-b.ts.net:8443", kind: .publicNetwork, lastUsedAt: now),
            ], lastUsedAt: now - 5, machine: "demo-aliyun")
            hosts = [a, b]
            currentHostId = a.id
            connection.serverAddress = "http://192.168.1.10:3093"
        }
#endif
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
#if DEBUG
        // UI 测试/排查用：在演示会话里挂一条失败消息，验证删除与重发入口。
        if DebugLaunch.demoFailedMessage {
            let rpcId = "demo-failed-message"
            messages.append(PocketMessage(pendingText: "这是一条发送失败的消息。",
                                          rpcId: rpcId,
                                          sortSequence: messages.map(\.sequence).max()))
            conversation.failedRpcIds.insert(rpcId)
        }
#endif
        // 会话内上限：允许翻历史，但不让压测数据把内存吃爆（退出时另按 24 裁）。
        trimToInSessionLimit()
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
        if !DebugLaunch.stressScenarios.isEmpty { return stressMessages(scenarios: DebugLaunch.stressScenarios) }
#endif
        if LanguageStore.shared.isEnglish { return demoMessagesEN(for: sessionId) }
        switch sessionId {
        case "demo-1":
            return [
                // 用户气泡是固定的深绿色（不随深浅模式），行内代码在这上面最容易糊成白块。
                PocketMessage(demoText: "帮我做一个 iOS 版的 DSH：要能连我电脑上的 `会话`，原生客户端，不要网页套壳。",
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

                - 原生 SwiftUI 客户端：`会话`、`实时流`、`图片`、`Markdown`
                - 扫码即连，局域网 / Tailscale / 公网三种通道
                - 模拟器已跑通，会话历史和电脑端实时同步

                想再加什么能力，直接去插件市场里装一个就行。

                > 行内代码（上面打反引号的词）不该有底色：气泡本身有颜色，
                > 加浅色底会把文字糊成白块。
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
        // 压测：steps:N 生成 N 个步骤（对应 steps 场景的消息轮数）。
        if let scaled = DebugLaunch.stressScenarios.first(where: {
            if case .steps = $0 { return true }
            return false
        }), case .steps(let count) = scaled {
            return (0..<count).map { index in
                PocketStep(id: "stress-step-\(index)", sequence: index * 2 + 3, turn: 1, number: index + 1,
                           name: index % 3 == 0 ? "bash" : (index % 3 == 1 ? "read" : "write"),
                           detail: "压测步骤 \(index + 1) · 执行中",
                           resultText: "步骤 \(index + 1) 的输出结果：done",
                           finished: true)
            }
        }
#endif
        guard sessionId == "demo-1" else { return [] }
        let en = LanguageStore.shared.isEnglish
        return [
            PocketStep(id: "demo-step-1", sequence: 3, turn: 1, number: 1,
                       name: "search",
                       detail: en ? "plugin market · ios" : "插件市场 · ios",
                       resultText: en
                           ? "dsh-pocket-ios (connector) · dsh-usage (billing) · huashu-design (design)"
                           : "dsh-pocket-ios（连接） · dsh-usage（用量） · huashu-design（设计）",
                       finished: true),
            PocketStep(id: "demo-step-2", sequence: 4, turn: 1, number: 2,
                       name: "bash", detail: "dsh plugin add dsh-pocket-ios",
                       resultText: "installed dsh-pocket-ios@0.2.1", finished: true),
            PocketStep(id: "demo-step-3", sequence: 5, turn: 1, number: 3,
                       name: "write",
                       detail: en ? "Generated SwiftUI app + DSHKit" : "生成 SwiftUI 工程 + DSHKit",
                       resultText: en ? "App target / DSHKit generated" : "App target / DSHKit 已生成",
                       finished: true),
            PocketStep(id: "demo-step-4", sequence: 6, turn: 1, number: 4,
                       name: "bash", detail: "xcodebuild → BUILD SUCCEEDED",
                       resultText: en ? "Verified on simulator · session synced" : "模拟器验证通过，会话已同步",
                       finished: true)
        ]
    }

    /// 英文演示消息。与中文版逐条对应，只换文案不换结构——
    /// 英文 App Store 截图里不能出现中文，但数据形状必须一致。
    static func demoMessagesEN(for sessionId: String) -> [PocketMessage] {
        switch sessionId {
        case "demo-1":
            return [
                PocketMessage(demoText: "Build an iOS client for DSH — it has to reach the sessions on my Mac, native, not a web wrapper.",
                              isUser: true, sequence: 1),
                PocketMessage(demoText: "Sure. DSH is plugins all the way down — let me find a ready-made connector first, then assemble the app around it.",
                              isUser: false, sequence: 2),
                PocketMessage(demoText: """
                Done. Here is how the client is assembled:

                | Plugin | What it does |
                | --- | --- |
                | dsh-pocket-ios | Phone → Mac |
                | dsh-usage | Balance, tokens |
                | parse-convert | Audio → text |

                ### What shipped

                - Native SwiftUI client: sessions, live stream, images, Markdown
                - Pair by QR: LAN, Tailscale, or public tunnel
                - Verified on simulator; history stays in sync with the Mac

                Want more capability? Install another plugin from the market.
                """, isUser: false, sequence: 7)
            ]
        case "demo-2":
            return [
                PocketMessage(demoText: "What is there to play with in the DSH plugin market?",
                              isUser: true, sequence: 1),
                PocketMessage(demoText: """
                The whole idea of DSH is that everything is a plugin — connectors, tools, UI, skills all load and unload independently.

                | Plugin | What it does |
                | --- | --- |
                | dsh-pocket-ios | Phone → Mac DSH |
                | dsh-usage | Balance, tokens |
                | parse-convert | Audio → text |
                | huashu-design | Prototypes, slides |

                Installing one needs no launcher change — restart and the new capability shows up in settings.
                """, isUser: false, sequence: 2)
            ]
        case "demo-3":
            return [
                PocketMessage(demoText: "Plan a 5-day Tokyo trip. Staying in Shinjuku, into coffee and architecture, not too rushed.",
                              isUser: true, sequence: 1),
                PocketMessage(demoText: """
                One focus per half-day, leaving room for coffee and walking:

                | Day | Morning | Evening |
                | --- | --- | --- |
                | D1 | Shinjuku | Omoide Yokocho |
                | D2 | Senso-ji | Jimbocho books |
                | D3 | Omotesando | Roppongi view |
                | D4 | Daikanyama | Meguro river |
                | D5 | Tsukiji | Departure |

                **Tip**: get a Suica, and cluster coffee stops by area so you don't zig-zag across the city.
                """, isUser: false, sequence: 2)
            ]
        case "demo-4":
            return [
                PocketMessage(demoText: "Can you look at this health report and explain a few of the numbers?",
                              isUser: true, sequence: 1, localImages: [demoPicture]),
                PocketMessage(demoText: """
                Nothing alarming overall — three items worth watching:

                | Marker | Result | Reading |
                | --- | --- | --- |
                | Cholesterol | Slightly high | Diet, retest 3 mo |
                | Uric acid | High | Less sugar, more water |
                | Vitamin D | Low | More daylight |

                Everything else is in range. Take the report to a clinic so a doctor can weigh it against your symptoms.
                """, isUser: false, sequence: 2)
            ]
        default:
            return [
                PocketMessage(demoText: "Turn today's meeting notes into action items with owners.",
                              isUser: true, sequence: 1),
                PocketMessage(demoText: """
                Done:

                1. **By Wednesday** — Q2 metric definitions doc — @Wang
                2. **Thursday** — confirm new home screen with design — @Li
                3. **Next Monday** — send demo environment to client — @me
                4. TBD: whether to add third-party sign-in

                Two items had no owner in the notes, so I marked them TBD — tell me and I'll fill them in.
                """, isUser: false, sequence: 2)
            ]
        }
    }

#if DEBUG
    /// 压测数据：按场景列表生成对话。
    ///
    /// 场景可叠加（`messages:400,images:120`），各自贡献一组消息。
    /// 目的是在模拟器上复现长会话 / 图片 / 步骤 / 极端 Markdown 的压力，
    /// 不需要真机，也不需要连电脑。
    static func stressMessages(scenarios: [StressScenario]) -> [PocketMessage] {
        var result: [PocketMessage] = []
        var sequence = 0

        func append(user: String, assistant: String, image: Bool) {
            sequence += 1
            result.append(PocketMessage(demoText: user, isUser: true, sequence: sequence))
            sequence += 1
            result.append(PocketMessage(demoText: assistant, isUser: false, sequence: sequence,
                                        localImages: image ? [demoPicture] : []))
        }

        for scenario in scenarios {
            switch scenario {
            case .messages(let rounds):
                for index in 0..<rounds {
                    append(user: Self.stressUserText(index),
                           assistant: Self.stressAssistantText(index), image: false)
                }
            case .images(let count):
                for index in 0..<count {
                    append(user: "第 \(index + 1) 张图：帮我看下这张截图里的问题。",
                           assistant: "收到，这是第 \(index + 1) 张。图里主要问题在右侧边距，其余正常。",
                           image: true)
                }
            case .steps(let count):
                for index in 0..<count {
                    append(user: "第 \(index + 1) 步任务：跑一下构建看看。",
                           assistant: "这一步有 \(count) 个子步骤，过程已折叠，展开可以看明细。",
                           image: false)
                }
            case .markdownExtreme:
                append(user: "给我一张大表和一段长代码。",
                       assistant: Self.extremeMarkdown(), image: false)
            case .markdownTable(let rows):
                append(user: "给我一张 \(rows) 行的表。",
                       assistant: Self.tableMarkdown(rows: rows), image: false)
            case .markdownCodePlain(let lines):
                append(user: "给我一段 \(lines) 行的代码，不要语言标识。",
                       assistant: Self.codePlainMarkdown(lines: lines), image: false)
            case .markdownCode(let lines):
                append(user: "给我一段 \(lines) 行的代码。",
                       assistant: Self.codeMarkdown(lines: lines), image: false)
            case .markdownText(let paragraphs):
                append(user: "写 \(paragraphs) 段长文字。",
                       assistant: Self.textMarkdown(paragraphs: paragraphs), image: false)
            case .markdownSingleLine(let lines):
                append(user: "写 \(lines) 行、中间不空行的长文本。",
                       assistant: Self.singleLineMarkdown(lines: lines), image: false)
            case .sessions:
                // 会话规模在列表层生成，不产出消息。
                break
            }
        }
        return result
    }

    private static func stressUserText(_ index: Int) -> String {
        "第 \(index + 1) 轮提问：帮我看一下这组数据的趋势，重点说异常项。"
    }

    private static func stressAssistantText(_ index: Int) -> String {
        """
        ### 第 \(index + 1) 轮分析

        下面按指标拆开说。整体结论是**没有严重异常**，两项需要留意。

        | 指标 | 当前值 | 参考区间 | 判断 |
        | --- | --- | --- | --- |
        | 指标 A | \(index * 3 % 97) | 40–80 | 正常 |
        | 指标 B | \(index * 7 % 53) | 10–45 | 略高 |
        | 指标 C | \(index * 11 % 31) | 5–25 | 正常 |

        ```swift
        let sample = \(index)
        let ratio = Double(sample) / 100.0
        print(ratio)
        ```

        **需要留意的两点**

        1. `指标 B` 连续三轮略高（阈值 `> 45`），建议下周复测
        2. `指标 C` 波动较大，但仍在区间 `5–25` 内

        > 行内代码在这里不该有底色：气泡本身是深色的，白底会把文字糊掉。

        如果要把这组数据导成表格，告诉我，我可以直接生成 CSV。
        """
    }

    /// 只有表格：N 行 × 8 列。
    private static func tableMarkdown(rows: Int) -> String {
        var table = "| 列一 | 列二 | 列三 | 列四 | 列五 | 列六 | 列七 | 列八 |\n"
        table += "| --- | --- | --- | --- | --- | --- | --- | --- |\n"
        for row in 0..<rows {
            table += "| 值 \(row) | 说明 \(row) | 12345 | 中文内容 \(row) | abc | δ | 0.5 | 完成 |\n"
        }
        return "### 表格压测 \(rows) 行\n\n" + table
    }

    /// 单段落超长文本：N 行，**中间没有空行**，整块就是一个段落。
    /// 用来验证「单个 Text 的长度」是不是崩溃主因。
    private static func singleLineMarkdown(lines: Int) -> String {
        var text = "### 单段落压测 \(lines) 行\n\n"
        for index in 0..<lines {
            text += "第 \(index + 1) 行内容，继续补充一些中文让每行有实际宽度。\n"
        }
        return text
    }

    /// 无语言代码块：N 行，``` 不带语言标识（不走语法高亮）。
    private static func codePlainMarkdown(lines: Int) -> String {
        var code = "```\n"
        for line in 0..<lines {
            code += "let value\(line) = compute(\(line))\n"
        }
        code += "```\n"
        return "### 无高亮代码压测 \(lines) 行\n\n" + code
    }

    /// 只有代码块：N 行。
    private static func codeMarkdown(lines: Int) -> String {
        var code = "```swift\n"
        for line in 0..<lines {
            code += "let value\(line) = compute(\(line))\n"
        }
        code += "```\n"
        return "### 代码压测 \(lines) 行\n\n" + code
    }

    /// 只有纯文本：N 个段落，每段约 120 字。
    private static func textMarkdown(paragraphs: Int) -> String {
        let sentence = "整体结论是没有严重异常，两项需要留意。指标 B 连续三轮略高，建议下周复测；指标 C 波动较大但仍在区间内。"
        var text = "### 文本压测 \(paragraphs) 段\n\n"
        for index in 0..<paragraphs {
            text += "第 \(index + 1) 段：" + sentence + "\n\n"
        }
        return text
    }

    /// 极端 Markdown：超宽表格 + 超长代码块，用来压 Textual 的解析与布局。
    private static func extremeMarkdown() -> String {
        var table = "| 列一 | 列二 | 列三 | 列四 | 列五 | 列六 | 列七 | 列八 |\n"
        table += "| --- | --- | --- | --- | --- | --- | --- | --- |\n"
        for row in 0..<100 {
            table += "| 值 \(row) | 说明 \(row) | 12345 | 中文内容 \(row) | abc | δ | 0.5 | 完成 |\n"
        }
        var code = "```swift\n"
        for line in 0..<500 {
            code += "let value\(line) = compute(\(line))\n"
        }
        code += "```\n"
        return """
        ### 极端 Markdown 压测

        \(table)

        \(code)

        以上是 100 行 8 列表格与 500 行代码块。
        """
    }
#endif
}
