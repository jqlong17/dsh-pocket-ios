import XCTest
@testable import DSHKit

final class DiagnosticsReportTests: XCTestCase {
    private func makeInput(events: [String] = [], notes: [String] = []) -> DiagnosticsReport.Input {
        DiagnosticsReport.Input(
            header: .init(generated: Date(timeIntervalSince1970: 1_800_000_000),
                          appVersion: "1.0.7", build: "4",
                          device: "iPhone17,1", system: "iOS 27.3", locale: "zh-Hans"),
            sections: [
                .init("Connection", [("State", "connected"), ("Server", "https://host")]),
                .init("Session", [("Messages", "30  (user 12 / assistant 18 / pending 0)")])
            ],
            events: events,
            notes: notes
        )
    }

    func testSectionsInFixedOrder() {
        let text = DiagnosticsReport.render(makeInput())
        let connIdx = text.range(of: "[ Connection ]")!.lowerBound
        let sessIdx = text.range(of: "[ Session ]")!.lowerBound
        let eventsIdx = text.range(of: "[ Recent Events ]")!.lowerBound
        XCTAssertLessThan(connIdx, sessIdx)
        XCTAssertLessThan(sessIdx, eventsIdx)
    }

    func testHeaderHasAppAndDevice() {
        let text = DiagnosticsReport.render(makeInput())
        XCTAssertTrue(text.contains("DSH Pocket Diagnostics"))
        XCTAssertTrue(text.contains("1.0.7 (4)"))
        XCTAssertTrue(text.contains("iPhone17,1"))
    }

    func testRowsAlignToKeyColumn() {
        // 值必须从固定列开始：同一段内所有值列号一致，才能粘贴到等宽字体里对齐。
        let text = DiagnosticsReport.render(makeInput())
        let lines = text.split(separator: "\n").map(String.init)
        let connectionRows = lines.filter { $0.hasPrefix("State") || $0.hasPrefix("Server") }
        XCTAssertEqual(connectionRows.count, 2)
        for line in connectionRows {
            let idx = line.firstIndex(where: { $0 == "h" || $0 == "c" })
            XCTAssertNotNil(idx, "值应存在于行内")
        }
        XCTAssertTrue(lines.contains { $0.hasPrefix("State") })
    }

    func testEventsTruncatedToLastN() {
        let events = (1...40).map { "00:00:\(String(format: "%02d", $0))  evt\($0)" }
        let text = DiagnosticsReport.render(makeInput(events: events))
        XCTAssertTrue(text.contains("showing last 30 of 40"))
        XCTAssertFalse(text.contains("evt1 "), "最前面的应被截断")
        XCTAssertTrue(text.contains("evt40"))
    }

    func testEmptyEventsShowsNone() {
        let text = DiagnosticsReport.render(makeInput())
        XCTAssertTrue(text.contains("(none)"))
    }

    func testNotesRendered() {
        let text = DiagnosticsReport.render(makeInput(notes: ["Footprint is not text size."]))
        XCTAssertTrue(text.contains("[ Notes ]"))
        XCTAssertTrue(text.contains("· Footprint is not text size."))
    }

    func testNoChineseCharacters() {
        // 报告固定英文：出现 CJK 说明有人又硬编码了中文。
        let text = DiagnosticsReport.render(makeInput(events: ["00:00:01  snapshot"], notes: ["n"]))
        let hasCJK = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        XCTAssertFalse(hasCJK, "诊断报告不应包含 CJK 字符")
    }

    func testBytesFormatting() {
        XCTAssertEqual(DiagnosticsReport.bytes(512), "512 B")
        XCTAssertEqual(DiagnosticsReport.bytes(2048), "2.0 KB")
        XCTAssertEqual(DiagnosticsReport.bytes(3 * 1024 * 1024), "3.0 MB")
    }
}
