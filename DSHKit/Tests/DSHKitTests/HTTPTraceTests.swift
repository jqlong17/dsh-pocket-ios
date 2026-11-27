import XCTest
@testable import DSHKit

final class HTTPTraceTests: XCTestCase {
    private func request(_ url: String, method: String = "GET", cookie: String? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = method
        if let cookie { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        return req
    }

    func testRecordsMethodPathStatusAndCookieFlags() {
        let trace = HTTPTrace(capacity: 4)
        trace.record(request("https://host.tail.ts.net/api/session/list", method: "POST",
                             cookie: "dsh-auth=1; dsh-pocket-device=2"),
                     status: 401, ms: 12, error: nil)
        let record = trace.snapshot().first
        XCTAssertEqual(record?.method, "POST")
        XCTAssertEqual(record?.path, "/api/session/list")
        XCTAssertEqual(record?.status, 401)
        XCTAssertEqual(record?.hasAuth, true)
        XCTAssertEqual(record?.hasDevice, true)
    }

    func testQueryStringIsRedacted() {
        let trace = HTTPTrace(capacity: 4)
        trace.record(request("https://host/?pair=secret-token&x=1"), status: 302, ms: 1, error: nil)
        XCTAssertEqual(trace.snapshot().first?.path, "/")
    }

    func testRingDropsOldestBeyondCapacity() {
        let trace = HTTPTrace(capacity: 3)
        for i in 0..<5 {
            trace.record(request("https://host/api/\(i)"), status: 200, ms: i, error: nil)
        }
        let paths = trace.snapshot().map { $0.path }
        XCTAssertEqual(paths, ["/api/2", "/api/3", "/api/4"])
    }

    func testNetworkErrorKeepsCode() {
        let trace = HTTPTrace(capacity: 2)
        trace.record(request("https://host/api/x"), status: nil, ms: 900, error: "URLError -1001")
        let line = HTTPTrace.line(trace.snapshot()[0])
        XCTAssertTrue(line.contains("ERR"))
        XCTAssertTrue(line.contains("URLError -1001"))
    }

    func testLineIncludesFlags() {
        let trace = HTTPTrace(capacity: 2)
        trace.record(request("https://host/api/x", cookie: "dsh-auth=a"), status: 200, ms: 5, error: nil)
        let line = HTTPTrace.line(trace.snapshot()[0])
        XCTAssertEqual(line, "GET /api/x 200 5ms auth")
    }
}
