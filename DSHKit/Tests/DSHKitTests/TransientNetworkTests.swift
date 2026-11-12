import XCTest
@testable import DSHKit

/// RPC 收口回归：transport 曾把 URLError 包成 DSHError.transport，
/// 导致飞行模式下发消息被判成「发送失败」而不是「断网暂存」。
final class TransientNetworkTests: XCTestCase {
    func testURLErrorStillTransient() {
        XCTAssertTrue(DSHNetworkErrorPolicy.isTransient(URLError(.notConnectedToInternet)))
        XCTAssertTrue(DSHNetworkErrorPolicy.isTransient(URLError(.timedOut)))
    }

    func testTransportErrorIsTransientFallback() {
        XCTAssertTrue(DSHNetworkErrorPolicy.isTransient(DSHError.transport("boom")))
    }

    func testBusinessErrorsAreNotTransient() {
        XCTAssertFalse(DSHNetworkErrorPolicy.isTransient(DSHError.unauthorized))
        XCTAssertFalse(DSHNetworkErrorPolicy.isTransient(DSHError.server(status: 400, message: nil)))
    }

    func testFlightModeFailureHoldsOfflineNotFailed() {
        // 飞行模式：不允许上网 → 应写入断网暂存，联网后自动补发。
        let action = SendFailurePolicy.action(
            isCancelled: false,
            isUnauthorized: false,
            isTransient: DSHNetworkErrorPolicy.isTransient(URLError(.notConnectedToInternet)),
            isStaleTunnel: false
        )
        XCTAssertEqual(action, .holdOffline)
    }
}
