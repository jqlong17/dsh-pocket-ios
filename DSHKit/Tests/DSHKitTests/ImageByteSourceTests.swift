import XCTest
@testable import DSHKit

final class ImageByteSourceTests: XCTestCase {
    func testAttachmentAndRemoteKeysNeverCollide() {
        // 两条链路共用同一个内存缓存，键必须能区分来源——
        // 否则同名的附件与 URL 会互相覆盖，出现「点开是另一张图」。
        let att = ImageSourceKey.attachment("shot-1")
        let url = ImageSourceKey.remote(URL(string: "https://host/shot-1")!)
        XCTAssertNotEqual(att, url)
        XCTAssertTrue(att.hasPrefix(ImageSourceKey.attachmentPrefix))
        XCTAssertTrue(url.hasPrefix(ImageSourceKey.remotePrefix))
    }

    func testSameSourceProducesStableKey() {
        XCTAssertEqual(ImageSourceKey.attachment("a"), ImageSourceKey.attachment("a"))
        XCTAssertEqual(ImageSourceKey.remote(URL(string: "https://h/x")!),
                       ImageSourceKey.remote(URL(string: "https://h/x")!))
    }

    func testFullMaxPixelFollowsScreenButKeepsFloor() {
        // 屏幕比 2048 大就按屏幕（iPhone Pro Max 2868 → 1:1 不放大）；
        // 屏幕更小时至少给 2048，避免小屏设备拿到过低分辨率、外接显示器时糊。
        XCTAssertEqual(ImageFetchPolicy.fullMaxPixel(screenLongSide: 2868), 2868)
        XCTAssertEqual(ImageFetchPolicy.fullMaxPixel(screenLongSide: 1200), 2048)
        XCTAssertEqual(ImageFetchPolicy.fullMaxPixel(screenLongSide: 0), 2048)
    }
}
