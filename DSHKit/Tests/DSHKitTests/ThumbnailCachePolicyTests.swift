import XCTest
@testable import DSHKit

final class ThumbnailCachePolicyTests: XCTestCase {
    func testTotalLimitIsFiveMegabytes() {
        XCTAssertEqual(ThumbnailCachePolicy.maxTotalBytes, 5 * 1024 * 1024)
    }

    func testFileNameIncludesSize() {
        XCTAssertEqual(ThumbnailCachePolicy.fileName(attachmentId: "abc", maxPixel: 640), "abc-640.jpg")
        XCTAssertEqual(ThumbnailCachePolicy.fileName(attachmentId: "a/b", maxPixel: 2048), "a_b-2048.jpg")
    }

    func testUnderLimitEvictsNothing() {
        let now = Date()
        let entries = [("a", 1_000_000, now)]
        XCTAssertEqual(ThumbnailCachePolicy.evictions(entries: entries), [])
    }

    func testOverLimitEvictsOldestFirst() {
        let now = Date()
        let entries = [
            ("old", 3_000_000, now.addingTimeInterval(-300)),
            ("new", 3_000_000, now),
        ]
        XCTAssertEqual(ThumbnailCachePolicy.evictions(entries: entries), ["old"])
    }

    func testEvictsUntilUnderLimit() {
        let now = Date()
        let entries = [
            ("a", 3_000_000, now.addingTimeInterval(-300)),
            ("b", 3_000_000, now.addingTimeInterval(-200)),
            ("c", 3_000_000, now),
        ]
        XCTAssertEqual(ThumbnailCachePolicy.evictions(entries: entries), ["a", "b"])
    }
}
