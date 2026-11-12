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
        XCTAssertLessThan(ImageFetchPolicy.thumbnailMaxPixel, ImageFetchPolicy.fullMaxPixel)
        XCTAssertEqual(ImageFetchPolicy.thumbnailMaxPixel, 640)
        XCTAssertEqual(ImageFetchPolicy.fullMaxPixel, 2048)
    }

    func testOversizedFetchesFullLazily() {
        XCTAssertFalse(ImageFetchPolicy.shouldFetchFullLazily(bytes: 1_000_000))
        XCTAssertTrue(ImageFetchPolicy.shouldFetchFullLazily(bytes: 5_000_000))
    }
}
