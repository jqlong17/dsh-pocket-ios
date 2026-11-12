import XCTest
@testable import DSHKit

final class ImageFetchPolicyTests: XCTestCase {
    func testRequestCarriesMaxPixel() {
        let args = ImageFetchPolicy.requestArgs(sessionId: "s1",
                                                attachment: ["attachmentId": "a"],
                                                maxPixel: 640)
        XCTAssertEqual(args["sessionId"] as? String, "s1")
        XCTAssertEqual(args["maxPixel"] as? Int, 640)
        XCTAssertNotNil(args["attachment"])
    }

    func testTiersAreSane() {
        // fullMaxPixel 已从常量改为「按屏幕算」的函数：固定 2048 在 Pro Max（2868）上会放大 1.4 倍，
        // 截图文字直接糊。这里只断言「缩略 < 全屏」这个不变式。
        XCTAssertEqual(ImageFetchPolicy.thumbnailMaxPixel, 640)
        XCTAssertGreaterThan(ImageFetchPolicy.fullMaxPixel(screenLongSide: 1200),
                             ImageFetchPolicy.thumbnailMaxPixel)
        XCTAssertEqual(ImageFetchPolicy.fullMaxPixel(screenLongSide: 1200), 2048)
    }

    func testOversizedFetchesFullLazily() {
        XCTAssertFalse(ImageFetchPolicy.shouldFetchFullLazily(bytes: 1_000_000))
        XCTAssertTrue(ImageFetchPolicy.shouldFetchFullLazily(bytes: 5_000_000))
    }
}
