import XCTest
@testable import DSHKit

final class BubbleWidthPolicyTests: XCTestCase {
    func testIPhoneWidthReservesPaddingAndLeadingGap() {
        // 393 - 32 - 44 = 317：5 张 88pt 缩略图（+间距）铺不满一行，必须换行。
        XCTAssertEqual(BubbleWidthPolicy.maxBubbleWidth(containerWidth: 393), 317)
    }

    func testUnmeasuredContainerFallsBackToPhoneWidth() {
        XCTAssertEqual(BubbleWidthPolicy.maxBubbleWidth(containerWidth: 0), 317)
        XCTAssertEqual(BubbleWidthPolicy.maxBubbleWidth(containerWidth: .nan), 317)
        XCTAssertEqual(BubbleWidthPolicy.maxBubbleWidth(containerWidth: .infinity), 317)
    }

    func testIPadUseCaseCapsColumnAtSevenTwenty() {
        XCTAssertEqual(BubbleWidthPolicy.maxBubbleWidth(containerWidth: 1_366),
                       720 - 32 - 44)
    }

    func testVeryNarrowSplitViewNeverGoesNegative() {
        XCTAssertEqual(BubbleWidthPolicy.maxBubbleWidth(containerWidth: 120),
                       BubbleWidthPolicy.minimumBubbleWidth)
    }

    func testFallbackIsConfigurable() {
        XCTAssertEqual(BubbleWidthPolicy.maxBubbleWidth(containerWidth: 0, fallbackContainerWidth: 430), 354)
    }
}
