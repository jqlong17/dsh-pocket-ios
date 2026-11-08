import XCTest
@testable import DSHKit

final class URLBuildingTests: XCTestCase {
    // P01
    func testWebSocketURLAddsLeadingSlash() throws {
        let base = try XCTUnwrap(DSHURL.normalizedBase("http://192.168.1.10:3081"))
        let url = try XCTUnwrap(DSHURL.webSocketURL(from: base, path: "api/remote.mux"))
        XCTAssertEqual(url.absoluteString, "ws://192.168.1.10:3081/api/remote.mux")
    }

    // P01 变体：https → wss
    func testWebSocketURLUsesWSSForHTTPS() throws {
        let base = try XCTUnwrap(DSHURL.normalizedBase("https://example.trycloudflare.com"))
        let url = try XCTUnwrap(DSHURL.webSocketURL(from: base, path: "api/remote.mux"))
        XCTAssertEqual(url.absoluteString, "wss://example.trycloudflare.com/api/remote.mux")
    }

    // P02
    func testNormalizeBaseAddsScheme() throws {
        let url = try XCTUnwrap(DSHURL.normalizedBase("192.168.1.10:3081"))
        XCTAssertEqual(url.absoluteString, "http://192.168.1.10:3081")
    }

    // P02 变体：零宽字符/空白
    func testNormalizeBaseStripsZeroWidthAndWhitespace() throws {
        let raw = "  \u{200B}192.168.1.10:3081\u{200D}  "
        let url = try XCTUnwrap(DSHURL.normalizedBase(raw))
        XCTAssertEqual(url.absoluteString, "http://192.168.1.10:3081")
    }

    func testNormalizeBaseRejectsEmptyAndInvalid() {
        XCTAssertNil(DSHURL.normalizedBase("   "))
        XCTAssertNil(DSHURL.normalizedBase("http://"))
    }
}
