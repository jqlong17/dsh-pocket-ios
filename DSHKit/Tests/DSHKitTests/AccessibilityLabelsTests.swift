import XCTest
@testable import DSHKit

final class AccessibilityLabelsTests: XCTestCase {
    func testProcessGroupListsDistinctLabels() {
        let text = AccessibilityLabels.processGroup(
            stepLabels: ["执行了命令", "执行了命令", "写入了文件"],
            runningLabel: nil
        )
        XCTAssertEqual(text, "过程，3 步：执行了命令、写入了文件")
    }

    func testProcessGroupMarksMoreThanThree() {
        let text = AccessibilityLabels.processGroup(
            stepLabels: ["执行了命令", "写入了文件", "读取了文件", "搜索了网页"],
            runningLabel: nil
        )
        XCTAssertTrue(text.contains("等"))
        XCTAssertTrue(text.hasPrefix("过程，4 步"))
    }

    func testProcessGroupRunningSaysWhat() {
        let text = AccessibilityLabels.processGroup(stepLabels: ["执行了命令"],
                                                    runningLabel: "正在运行命令…")
        XCTAssertEqual(text, "正在运行命令…，共 1 步")
    }

    func testProcessGroupEmpty() {
        XCTAssertEqual(AccessibilityLabels.processGroup(stepLabels: [], runningLabel: nil),
                       "过程，没有步骤")
    }

    func testJobSentence() {
        XCTAssertEqual(
            AccessibilityLabels.job(name: "跑测试", statusLabel: "正在运行", elapsed: "12 秒"),
            "跑测试，正在运行，已跑 12 秒"
        )
        XCTAssertEqual(
            AccessibilityLabels.job(name: "跑测试", statusLabel: "已完成", elapsed: nil),
            "跑测试，已完成"
        )
    }

    func testBackToBottomWithUnread() {
        XCTAssertEqual(AccessibilityLabels.backToBottom(unreadReplies: 0), "回到底部")
        XCTAssertEqual(AccessibilityLabels.backToBottom(unreadReplies: 5), "回到底部，5 条新回复")
        XCTAssertEqual(AccessibilityLabels.backToBottom(unreadReplies: 120), "回到底部，99+ 条新回复")
    }

    func testAttachmentSentence() {
        XCTAssertEqual(AccessibilityLabels.attachment(index: 2, total: 3), "图片 2，共 3 张，双击查看大图")
        XCTAssertEqual(AccessibilityLabels.attachment(index: 1, total: 1), "图片，双击查看大图")
        XCTAssertEqual(AccessibilityLabels.attachment(index: nil, total: nil), "图片，双击查看大图")
    }

    func testMessageSender() {
        XCTAssertEqual(AccessibilityLabels.messageSender(isUser: true), "你")
        XCTAssertEqual(AccessibilityLabels.messageSender(isUser: false), "DSH")
    }

    func testSessionRow() {
        XCTAssertEqual(AccessibilityLabels.sessionRow(title: "做一个 iOS 版 DSH", status: "正在运行", isPinned: false),
                       "做一个 iOS 版 DSH，正在运行")
        XCTAssertEqual(AccessibilityLabels.sessionRow(title: "做一个 iOS 版 DSH", status: "已完成，等待你的回复", isPinned: true),
                       "做一个 iOS 版 DSH，已完成，等待你的回复，已置顶")
    }

    func testNewReplyAnnouncement() {
        XCTAssertEqual(AccessibilityLabels.newReplyAnnouncement(unreadReplies: 0), "DSH 回复了")
        XCTAssertEqual(AccessibilityLabels.newReplyAnnouncement(unreadReplies: 3), "DSH 回复了，3 条未读")
    }
}
