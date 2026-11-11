import XCTest
@testable import DSHKit

final class URLRedactionTests: XCTestCase {
    func testRedactedDropsQueryToken() {
        let url = URL(string: "https://example.com/?token=SECRET123&x=1")!
        let text = DSHURL.redacted(url)
        XCTAssertFalse(text.contains("SECRET123"))
        XCTAssertFalse(text.contains("token="))
        XCTAssertTrue(text.hasPrefix("https://example.com"))
    }

    func testRedactedKeepsPlainAddressIntact() {
        let url = URL(string: "http://192.168.1.9:3081")!
        XCTAssertEqual(DSHURL.redacted(url), "http://192.168.1.9:3081")
    }

    func testBaseAddressStripsQuery() {
        let url = URL(string: "https://host.example/path/?pair=SECRET")!
        XCTAssertEqual(DSHURL.baseAddress(url), "https://host.example/path/")
    }

    func testRedactedAddressOnRawString() {
        let text = DSHURL.redactedAddress("https://h.example/?pair=SECRET")
        XCTAssertFalse(text.contains("SECRET"))
    }

    func testRedactedAddressHandlesGarbage() {
        XCTAssertEqual(DSHURL.redactedAddress(":::"), "（地址无法解析）")
    }
}
