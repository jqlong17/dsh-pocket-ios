import XCTest
@testable import DSHKit

final class ConversationCachePolicyTests: XCTestCase {
    private func ref(_ id: String, _ minutesAgo: Double) -> CachedConversationRef {
        CachedConversationRef(id: id, lastOpenedAt: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60))
    }

    func testUnderLimitKeepsEverything() {
        let refs = [ref("a", 1), ref("b", 2)]
        XCTAssertEqual(ConversationCachePolicy.evictions(from: refs, keeping: []), [])
    }

    func testOverLimitEvictsOldestFirst() {
        let refs = [ref("a", 1), ref("b", 5), ref("c", 3), ref("d", 2)]
        XCTAssertEqual(ConversationCachePolicy.evictions(from: refs, keeping: []), ["b"])
    }

    func testExactlyLimitEvictsNothing() {
        let refs = [ref("a", 1), ref("b", 2), ref("c", 3)]
        XCTAssertEqual(ConversationCachePolicy.evictions(from: refs, keeping: []), [])
    }

    func testPinnedNeverEvictedEvenIfOldest() {
        // "old" 是最旧的，但被 pin 住；实际该淘汰剩下里最旧的 d。
        let refs = [ref("old", 99), ref("b", 2), ref("c", 3), ref("d", 4)]
        XCTAssertEqual(ConversationCachePolicy.evictions(from: refs, keeping: ["old"]), ["d"])
    }

    func testPinnedReducesCandidatesButStillFits() {
        let refs = [ref("a", 1), ref("b", 2), ref("c", 3), ref("d", 4)]
        XCTAssertEqual(ConversationCachePolicy.evictions(from: refs, keeping: ["a", "b"]), ["d"])
    }
}

final class SessionOpenPolicyTests: XCTestCase {
    func testEmptyCacheNeedsBaseline() {
        XCTAssertTrue(SessionOpenPolicy.shouldFetchHTTPBaseline(cachedMessageCount: 0))
    }

    func testCachedMessagesSkipBaseline() {
        XCTAssertFalse(SessionOpenPolicy.shouldFetchHTTPBaseline(cachedMessageCount: 1))
        XCTAssertFalse(SessionOpenPolicy.shouldFetchHTTPBaseline(cachedMessageCount: 36))
    }
}
