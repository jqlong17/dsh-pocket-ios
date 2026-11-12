import XCTest
@testable import DSHKit

/// 错误分类：把「怎么处理」和「怎么显示」分开。
///
/// 为什么要有 kind：App 层的 `ConnectionError` 分类（暂时性/认证/地址/未知）以前自己判断，
/// 收口后判断要落在 DSHKit（可测），App 只做映射。
final class DSHErrorKindTests: XCTestCase {
    func testTransportErrorsAreTransient() {
        XCTAssertEqual(DSHError.transport("timeout").kind, .transient)
        XCTAssertEqual(DSHError.transport("connection lost").kind, .transient)
    }

    func testAuthErrorsAreAuth() {
        XCTAssertEqual(DSHError.unauthorized.kind, .auth)
    }

    func testRateLimitIsTransient() {
        // 429 是「稍后再试」，和网络抖动同属可重试类。
        XCTAssertEqual(DSHError.rateLimited.kind, .transient)
    }

    func testServer5xxIsTransientBut4xxIsNot() {
        XCTAssertEqual(DSHError.server(status: 500, message: nil).kind, .transient)
        XCTAssertEqual(DSHError.server(status: 503, message: nil).kind, .transient)
        XCTAssertEqual(DSHError.server(status: 400, message: "bad").kind, .business)
        XCTAssertEqual(DSHError.server(status: 404, message: nil).kind, .business)
    }

    func testInvalidAddressIsInvalidAddress() {
        XCTAssertEqual(DSHError.invalidAddress.kind, .invalidAddress)
    }

    func testPayloadAndDecodingAreBusiness() {
        XCTAssertEqual(DSHError.invalidPayload.kind, .business)
        XCTAssertEqual(DSHError.decoding("x").kind, .business)
    }

    func testOnlyTransientAndRateLimitAreRetryable() {
        XCTAssertTrue(DSHError.transport("x").isRetryable)
        XCTAssertTrue(DSHError.rateLimited.isRetryable)
        XCTAssertTrue(DSHError.server(status: 502, message: nil).isRetryable)
        XCTAssertFalse(DSHError.unauthorized.isRetryable)
        XCTAssertFalse(DSHError.server(status: 400, message: nil).isRetryable)
        XCTAssertFalse(DSHError.invalidAddress.isRetryable)
    }
}
