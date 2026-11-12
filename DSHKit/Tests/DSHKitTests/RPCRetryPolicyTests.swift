import XCTest
@testable import DSHKit

/// 重试策略的边界：只有瞬时错误、且还有剩余次数时才重试。
///
/// 为什么单独抽策略：重试条件写在网络调用里就无法穷举测试，
/// 而「401 被重试 3 次」这种 bug 在生产里表现为「密码错了却一直转圈」。
final class RPCRetryPolicyTests: XCTestCase {
    func testTransientErrorRetriesWhenAttemptsRemain() {
        let error = URLError(.timedOut)
        XCTAssertTrue(RPCRetryPolicy.shouldRetry(error, attempt: 0, maxAttempts: 3))
        XCTAssertTrue(RPCRetryPolicy.shouldRetry(error, attempt: 1, maxAttempts: 3))
    }

    func testNoRetryOnLastAttempt() {
        XCTAssertFalse(RPCRetryPolicy.shouldRetry(URLError(.timedOut), attempt: 2, maxAttempts: 3))
        XCTAssertFalse(RPCRetryPolicy.shouldRetry(URLError(.timedOut), attempt: 0, maxAttempts: 1))
    }

    func testPermanentErrorsNeverRetry() {
        XCTAssertFalse(RPCRetryPolicy.shouldRetry(DSHError.unauthorized, attempt: 0, maxAttempts: 3))
        XCTAssertFalse(RPCRetryPolicy.shouldRetry(DSHError.invalidPayload, attempt: 0, maxAttempts: 3))
        XCTAssertFalse(RPCRetryPolicy.shouldRetry(DSHError.server(status: 500, message: nil),
                                                  attempt: 0, maxAttempts: 3))
    }

    func testBackoffGrows() {
        let first = RPCRetryPolicy.backoff(attempt: 0)
        let second = RPCRetryPolicy.backoff(attempt: 1)
        XCTAssertLessThanOrEqual(first, second)
        XCTAssertLessThanOrEqual(second, .seconds(3))
    }
}
