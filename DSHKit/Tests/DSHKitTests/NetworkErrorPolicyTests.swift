import XCTest
@testable import DSHKit

final class NetworkErrorPolicyTests: XCTestCase {
    func testTransientURLErrorCodes() {
        let codes: [URLError.Code] = [
            .timedOut,
            .networkConnectionLost,
            .notConnectedToInternet,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
            .secureConnectionFailed,
        ]
        for code in codes {
            XCTAssertTrue(DSHNetworkErrorPolicy.isTransient(URLError(code)), "expected transient: \(code)")
        }
    }

    func testNonTransientErrors() {
        XCTAssertFalse(DSHNetworkErrorPolicy.isTransient(URLError(.cancelled)))
        XCTAssertFalse(DSHNetworkErrorPolicy.isTransient(URLError(.badURL)))
        XCTAssertFalse(DSHNetworkErrorPolicy.isTransient(URLError(.userAuthenticationRequired)))
        XCTAssertFalse(DSHNetworkErrorPolicy.isTransient(NSError(domain: "DSH", code: 1)))
    }
}
