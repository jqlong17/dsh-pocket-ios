import XCTest
@testable import DSHKit

final class ComposerAndPresentationTests: XCTestCase {
    // U10：有文本可发送
    func testCanSendWithText() {
        let policy = ComposerPolicy(text: "你好")
        XCTAssertTrue(policy.canSend)
        XCTAssertEqual(policy.button, .send)
    }

    // U11：发送中按钮变为取消；取消后可恢复
    func testSendingShowsCancelButton() {
        var policy = ComposerPolicy(text: "hi", isSending: true)
        XCTAssertEqual(policy.button, .cancel)
        XCTAssertFalse(policy.canSend)
        policy.isSending = false
        XCTAssertEqual(policy.button, .send)
        XCTAssertTrue(policy.canSend)
    }

    // U14：空文本且无图片不可发送；空白文本 trim
    func testEmptyCannotSend() {
        XCTAssertFalse(ComposerPolicy(text: "   ").canSend)
        XCTAssertFalse(ComposerPolicy().canSend)
        XCTAssertTrue(ComposerPolicy(imageCount: 1).canSend)
    }

    // U15：生成中也允许继续输入
    func testTypingAllowedWhileSending() {
        let policy = ComposerPolicy(text: "继续", isSending: true)
        XCTAssertTrue(policy.allowsTyping)
    }

    // U12：steer 状态文案
    func testSteerPresentation() {
        XCTAssertEqual(PendingPresentationBuilder.make(state: .accepted(.steer)).label, "已引导，正在继续")
        XCTAssertEqual(PendingPresentationBuilder.make(state: .accepted(.queue)).label, "已发出，等待处理")
        XCTAssertEqual(PendingPresentationBuilder.make(state: .sending).label, "发送中…")
    }

    // U13：失败可重发
    func testFailedPresentation() {
        let failed = PendingPresentationBuilder.make(state: .failed)
        XCTAssertTrue(failed.isFailed)
        XCTAssertTrue(failed.isRetryable)
        XCTAssertEqual(failed.label, "发送失败")
    }

    // U20：整条复制
    func testCopyWholeMessage() {
        XCTAssertEqual(CopyTextBuilder.wholeMessage("# 标题\n正文"), "# 标题\n正文")
        XCTAssertEqual(CopyTextBuilder.wholeMessage("\n正文\n"), "正文")
    }

    // U30：连接状态展示
    func testConnectionStatusPresentation() {
        XCTAssertEqual(ConnectionStatusBuilder.make(state: .connected).label, "已连接")
        XCTAssertEqual(ConnectionStatusBuilder.make(state: .connecting).kind, .connecting)
        XCTAssertEqual(ConnectionStatusBuilder.make(state: .reconnecting(attempt: 3)).label, "重连中（第 3 次）")
        XCTAssertTrue(ConnectionStatusBuilder.make(state: .disconnected(reason: nil)).showsRetry)
        XCTAssertEqual(ConnectionStatusBuilder.make(state: .idle).kind, .idle)
    }
}
