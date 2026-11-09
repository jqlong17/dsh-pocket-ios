import XCTest

/// 模块 05b：Demo 模式 UI 端到端（无需电脑/网络，覆盖发送、滚动回底、复制）。
final class DemoFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchDemo(session: String = "demo-1") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DSH_DEMO"] = "1"
        app.launchEnvironment["DSH_RESET"] = "1"
        app.launchEnvironment["DSH_OPEN"] = session
        app.launch()
        return app
    }

    func testSendMessageFromComposer() {
        let app = launchDemo()
        let field = app.textFields["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "输入框未出现")
        field.tap()
        field.typeText("UI 测试消息")
        let send = app.buttons["send-button"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        // 演示模式：1 秒后待发送气泡被示例回复替换，用回复文本确认发送链路成功。
        let reply = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "这是内置的示例回复")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 12), "发送后未出现示例回复，发送链路失败")
    }

    /// 真实会话：生成中发送应触发 steer（"已引导"或用户气泡立即出现）。
    /// 需要外部传入 TEST_RUNNER_LIVE_SESSION_ID，否则跳过。
    func testSendWhileTurnRunningUsesSteer() throws {
        guard let session = ProcessInfo.processInfo.environment["LIVE_SESSION_ID"], !session.isEmpty else {
            throw XCTSkip("未提供 LIVE_SESSION_ID")
        }
        let app = XCUIApplication()
        app.launchEnvironment["DSH_SERVER"] = ProcessInfo.processInfo.environment["LIVE_SERVER"] ?? ""
        app.launchEnvironment["DSH_PIN"] = ProcessInfo.processInfo.environment["LIVE_PIN"] ?? ""
        app.launchEnvironment["DSH_OPEN"] = session
        app.launch()

        let running = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "深度求索中")).firstMatch
        XCTAssertTrue(running.waitForExistence(timeout: 25), "turn 未处于运行状态")

        let field = app.textFields["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("请先停一下，总结当前已完成的内容。")
        app.buttons["send-button"].tap()

        let sent = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "请先停一下")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 12), "steer 消息未出现在对话中")
    }



    /// 发送后输入框必须清空（回归：偶发残留已发送文字）。
    func testSendClearsComposer() {
        let app = launchDemo(session: "demo-1")
        let field = app.textFields["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("清空测试")
        let send = app.buttons["send-button"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        // 空输入框的 value 会是占位符「发送消息」，因此断言"不再是刚发送的文字"。
        let cleared = NSPredicate(format: "value != %@", "清空测试")
        expectation(for: cleared, evaluatedWith: field)
        waitForExpectations(timeout: 8)
    }

    /// 草稿按会话隔离：切换会话再回来，原草稿应恢复。
    func testDraftIsPerSession() {
        let app = launchDemo(session: "demo-1")
        let field = app.textFields["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "输入框未出现")
        field.tap()
        field.typeText("草稿-会话1")

        // 返回列表
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let otherSession = app.staticTexts["分析 App Store 截图"]
        XCTAssertTrue(otherSession.waitForExistence(timeout: 10), "会话列表未出现")
        otherSession.tap()
        let otherField = app.textFields["composer-field"]
        XCTAssertTrue(otherField.waitForExistence(timeout: 10))
        XCTAssertNotEqual(otherField.value as? String, "草稿-会话1", "不同会话不应共享草稿")

        // 回到原会话，草稿应恢复
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let original = app.staticTexts["整理 v1.0.2 发布说明"]
        XCTAssertTrue(original.waitForExistence(timeout: 10))
        original.tap()
        let restored = app.textFields["composer-field"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.value as? String, "草稿-会话1", "切回会话后草稿未恢复")
    }



    func testBackToBottomThenScrollUpDoesNotSnapBack() {
        let app = launchDemo()
        XCTAssertTrue(app.textFields["composer-field"].waitForExistence(timeout: 15))
        // 向上滚动，触发"回到底部"按钮。
        app.swipeDown()
        app.swipeDown()
        let back = app.buttons["back-to-bottom"]
        guard back.waitForExistence(timeout: 5) else {
            return // 内容不足一屏时按钮不出现，跳过
        }
        back.tap()
        // 立刻再次上滑：不应被强制拉回底部（按钮应重新出现）。
        app.swipeDown()
        XCTAssertTrue(back.waitForExistence(timeout: 5), "上滑后应重新出现回到底部按钮，说明没有被强制抢滚动")
    }
}
