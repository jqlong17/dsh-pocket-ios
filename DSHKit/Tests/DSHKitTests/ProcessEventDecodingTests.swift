import XCTest
@testable import DSHKit

/// 过程事件 / 分页记录 / 附件解析的统一入口（App 层不再手工拆字典）。
final class ProcessEventDecodingTests: XCTestCase {
    // MARK: - 单条记录 → 过程事件

    func testStepEventFromRecordDecodesToolCall() {
        let record: [String: Any] = ["event": [
            "type": "tool/call", "seq": 5, "time": 1794177002500,
            "data": [
                "turn": 1, "step": 2, "callId": "call-1", "name": "bash",
                "arguments": #"{"command": "ls -la"}"#
            ]
        ]]
        guard case .toolCall(let seq, let turn, let callId, let name, let detail, let arguments)? =
                DSHDecoding.stepEvent(fromRecord: record) else {
            return XCTFail("expected toolCall")
        }
        XCTAssertEqual(seq, 5)
        XCTAssertEqual(turn, 1)
        XCTAssertEqual(callId, "call-1")
        XCTAssertEqual(name, "bash")
        XCTAssertEqual(detail, "ls -la")
        XCTAssertEqual(arguments, #"{"command": "ls -la"}"#)
    }

    func testStepEventFromRecordDecodesToolResultWithImages() {
        let record: [String: Any] = ["event": [
            "type": "tool/result", "seq": 6,
            "data": [
                "turn": 1, "toolCallId": "call-1", "isError": true,
                "message": ["role": "tool", "content": [
                    ["type": "text", "text": "screenshot saved"],
                    ["type": "image", "attachment": [
                        "attachmentId": "sha256:abc", "mediaType": "image/png",
                        "bytes": 343367, "width": 2160, "height": 1350, "name": "shot.png"
                    ]]
                ]]
            ]
        ]]
        guard case .toolResult(let seq, let turn, let callId, let text, let isError, let images)? =
                DSHDecoding.stepEvent(fromRecord: record) else {
            return XCTFail("expected toolResult")
        }
        XCTAssertEqual(seq, 6)
        XCTAssertEqual(turn, 1)
        XCTAssertEqual(callId, "call-1")
        XCTAssertEqual(text, "screenshot saved")
        XCTAssertTrue(isError)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.attachmentId, "sha256:abc")
        XCTAssertEqual(images.first?.mediaType, "image/png")
        XCTAssertEqual(images.first?.bytes, 343367)
        XCTAssertEqual(images.first?.width, 2160)
        XCTAssertEqual(images.first?.height, 1350)
        XCTAssertEqual(images.first?.name, "shot.png")
    }

    func testStepEventFromRecordToolResultCallIdFallsBackToDataCallId() {
        // App 旧解析读 data.callId；统一入口必须也能兜到。
        let record: [String: Any] = ["event": [
            "type": "tool/result", "seq": 9,
            "data": ["turn": 2, "callId": "call-from-data",
                     "message": ["content": [["type": "text", "text": "ok"]]]]
        ]]
        guard case .toolResult(_, _, let callId, _, _, _)? = DSHDecoding.stepEvent(fromRecord: record) else {
            return XCTFail("expected toolResult")
        }
        XCTAssertEqual(callId, "call-from-data")
    }

    func testStepEventFromRecordTurnBoundariesWithoutData() {
        let start: [String: Any] = ["event": ["type": "turn/start", "seq": 7]]
        guard case .turnStart(let startSeq, let startTurn)? = DSHDecoding.stepEvent(fromRecord: start) else {
            return XCTFail("expected turnStart")
        }
        XCTAssertEqual(startSeq, 7)
        XCTAssertEqual(startTurn, 0)

        let end: [String: Any] = ["event": ["type": "turn/end", "seq": 8, "data": ["turn": 2]]]
        guard case .turnEnd(let endSeq, let endTurn, let failure)? = DSHDecoding.stepEvent(fromRecord: end) else {
            return XCTFail("expected turnEnd")
        }
        XCTAssertEqual(endSeq, 8)
        XCTAssertEqual(endTurn, 2)
        XCTAssertNil(failure)
    }

    func testStepEventFromRecordAcceptsBareEventAndWrapper() {
        let event: [String: Any] = ["type": "tool/call", "seq": 11,
                                    "data": ["turn": 3, "callId": "c", "name": "read",
                                             "arguments": #"{"file_path":"/tmp/a.txt"}"#]]
        let fromWrapper = DSHDecoding.stepEvent(fromRecord: ["event": event])
        let fromBare = DSHDecoding.stepEvent(fromRecord: event)
        XCTAssertEqual(fromWrapper, fromBare)
        XCTAssertEqual(fromWrapper, DSHDecoding.stepEvent(fromEvent: event))
    }

    func testStepEventFromRecordBadRowsReturnNil() {
        // 空记录
        XCTAssertNil(DSHDecoding.stepEvent(fromRecord: [:]))
        // 记录里没有 event，也不是事件本体
        XCTAssertNil(DSHDecoding.stepEvent(fromRecord: ["payload": ["type": "tool/call"]]))
        // event 不是字典
        XCTAssertNil(DSHDecoding.stepEvent(fromRecord: ["event": "not-a-dict"]))
        // 缺 seq
        XCTAssertNil(DSHDecoding.stepEvent(fromRecord: ["event": ["type": "turn/start", "data": ["turn": 1]]]))
        // 未知事件类型
        XCTAssertNil(DSHDecoding.stepEvent(fromRecord: ["event": ["type": "unknown/event", "seq": 3]]))
        // 消息事件不是过程事件
        XCTAssertNil(DSHDecoding.stepEvent(fromRecord: ["event": [
            "type": "assistant/message", "seq": 4,
            "data": ["message": ["content": [["type": "text", "text": "hi"]]]]
        ]]))
        // tool/call 缺 callId / name
        XCTAssertNil(DSHDecoding.stepEvent(fromRecord: ["event": [
            "type": "tool/call", "seq": 5, "data": ["turn": 1, "name": "bash"]
        ]]))
        XCTAssertNil(DSHDecoding.stepEvent(fromRecord: ["event": [
            "type": "tool/call", "seq": 5, "data": ["turn": 1, "callId": "call-1"]
        ]]))
        // seq 类型不对
        XCTAssertNil(DSHDecoding.stepEvent(fromRecord: ["event": ["type": "turn/start", "seq": "5"]]))
    }

    // MARK: - records → 事件数组

    func testStepEventsFromRecordsDropsBadAndNonStepRows() {
        let records: [[String: Any]] = [
            ["event": ["type": "tool/call", "seq": 1, "data": ["turn": 1, "callId": "c1", "name": "bash"]]],
            ["event": ["type": "user/message", "seq": 2, "data": [
                "content": [["type": "text", "text": "你好"]],
                "source": ["kind": "user"]
            ]]],
            ["event": ["type": "session/title", "seq": 3, "data": ["title": "标题"]]],
            ["event": ["type": "turn/start", "seq": 4, "data": ["turn": 1]]],
            ["event": ["type": "unknown/event", "seq": 5, "data": [:]]],
            ["event": ["type": "tool/call", "data": ["turn": 1, "callId": "bad", "name": "bash"]]],
            ["payload": "not-a-record"],
            ["event": ["type": "turn/end", "seq": 8, "data": ["turn": 1]]]
        ]
        let steps = DSHDecoding.stepEvents(fromRecords: records)
        XCTAssertEqual(steps.count, 3)
        if case .toolCall(let seq, _, _, _, _, _) = steps[0] { XCTAssertEqual(seq, 1) } else {
            XCTFail("expected toolCall first")
        }
        if case .turnStart(let seq, _) = steps[1] { XCTAssertEqual(seq, 4) } else {
            XCTFail("expected turnStart second")
        }
        if case .turnEnd(let seq, _, _) = steps[2] { XCTAssertEqual(seq, 8) } else {
            XCTFail("expected turnEnd third")
        }
    }

    func testStepEventsFromEmptyRecordsIsEmpty() {
        XCTAssertTrue(DSHDecoding.stepEvents(fromRecords: []).isEmpty)
    }

    func testStepEventsFromFixturePageMatchesPageDecoder() throws {
        let json = try fixtureJSON("session_page")
        let records = try XCTUnwrap(json["records"] as? [[String: Any]])
        let steps = DSHDecoding.stepEvents(fromRecords: records)
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps.map(Self.sequence(of:)), [4, 5, 6, 8])
        XCTAssertTrue(steps.contains { if case .toolResult = $0 { return true }; return false })

        let pageSteps = DSHDecoding.page(fromValue: json).records.compactMap { record -> DSHStepEvent? in
            if case .step(let step) = record { return step }
            return nil
        }
        XCTAssertEqual(steps, pageSteps)
    }

    private static func sequence(of step: DSHStepEvent) -> Int {
        switch step {
        case .toolCall(let seq, _, _, _, _, _),
             .toolResult(let seq, _, _, _, _, _),
             .turnStart(let seq, _),
             .turnEnd(let seq, _, _):
            return seq
        }
    }

    // MARK: - 单条记录 → 类型化条目

    func testRecordFromEventClassifiesMessageStepTitleAndUnknown() {
        let messageEvent: [String: Any] = [
            "type": "user/message", "seq": 2,
            "data": ["content": [["type": "text", "text": "你好"]], "source": ["kind": "user", "rpcId": "rpc-1"]]
        ]
        if case .message(let message) = DSHDecoding.record(fromEvent: messageEvent) {
            XCTAssertEqual(message.text, "你好")
            XCTAssertEqual(message.rpcId, "rpc-1")
        } else {
            XCTFail("expected message")
        }

        let stepEvent: [String: Any] = ["type": "turn/start", "seq": 4, "data": ["turn": 1]]
        if case .step(let step) = DSHDecoding.record(fromEvent: stepEvent) {
            XCTAssertEqual(step, .turnStart(seq: 4, turn: 1))
        } else {
            XCTFail("expected step")
        }

        let titleEvent: [String: Any] = ["type": "session/title", "seq": 3, "data": ["title": "问候"]]
        if case .title(let seq, let title) = DSHDecoding.record(fromEvent: titleEvent) {
            XCTAssertEqual(seq, 3)
            XCTAssertEqual(title, "问候")
        } else {
            XCTFail("expected title")
        }

        XCTAssertEqual(DSHDecoding.record(fromEvent: ["type": "unknown/event", "seq": 9]), .unknown)
        XCTAssertEqual(DSHDecoding.record(fromEvent: [:]), .unknown)
    }

    func testRecordFromRecordHandlesWrapperAndBadRows() {
        let record: [String: Any] = ["event": ["type": "session/title", "seq": 3, "data": ["title": "标题"]]]
        if case .title(_, let title) = DSHDecoding.record(fromRecord: record) {
            XCTAssertEqual(title, "标题")
        } else {
            XCTFail("expected title")
        }
        XCTAssertEqual(DSHDecoding.record(fromRecord: [:]), .unknown)
        XCTAssertEqual(DSHDecoding.record(fromRecord: ["event": "not-a-dict"]), .unknown)
    }

    func testRecordsFromFixturePageKeepsOrderAndClassifiesEveryRow() throws {
        let json = try fixtureJSON("session_page")
        let rawRecords = try XCTUnwrap(json["records"] as? [[String: Any]])
        let records = DSHDecoding.records(fromRecords: rawRecords)
        XCTAssertEqual(records.count, rawRecords.count)

        var messages = 0, steps = 0, titles = 0, unknowns = 0
        for record in records {
            switch record {
            case .message: messages += 1
            case .step: steps += 1
            case .title: titles += 1
            case .unknown: unknowns += 1
            }
        }
        XCTAssertEqual(messages, 3)   // seq 2/7/9；注入的 runtime-context 不算消息
        XCTAssertEqual(steps, 4)      // seq 4/5/6/8
        XCTAssertEqual(titles, 1)     // seq 1
        XCTAssertEqual(unknowns, 2)   // seq 3（注入上下文）与 seq 10（未知事件）

        if case .title(let seq, let title) = records[0] {
            XCTAssertEqual(seq, 1)
            XCTAssertEqual(title, "问候")
        } else {
            XCTFail("expected title first")
        }
        if case .step(let step) = records[3] {
            XCTAssertEqual(step, .turnStart(seq: 4, turn: 1))
        } else {
            XCTFail("expected turnStart at index 3")
        }
        XCTAssertTrue(DSHDecoding.records(fromRecords: []).isEmpty)
    }

    // MARK: - 事件时间

    func testEventTimestampFromEvent() {
        let date = DSHDecoding.eventTimestamp(fromEvent: ["type": "turn/start", "seq": 1, "time": 1794177000000])
        XCTAssertNotNil(date)
        XCTAssertEqual(date?.timeIntervalSince1970 ?? 0, 1794177000, accuracy: 0.001)
        XCTAssertNil(DSHDecoding.eventTimestamp(fromEvent: ["type": "turn/start", "seq": 1]))
        XCTAssertNil(DSHDecoding.eventTimestamp(fromEvent: ["type": "turn/start", "time": 0]))
        XCTAssertNil(DSHDecoding.eventTimestamp(fromEvent: ["type": "turn/start", "time": "1794177000000"]))
    }

    // MARK: - 图片附件

    func testImageRefFromAttachmentFullFields() {
        let ref = DSHDecoding.imageRef(fromAttachment: [
            "attachmentId": "sha256:abc", "mediaType": "image/jpeg",
            "bytes": 1024, "width": 640, "height": 420, "name": "photo.jpg"
        ])
        XCTAssertEqual(ref, DSHImageRef(attachmentId: "sha256:abc", mediaType: "image/jpeg",
                                        bytes: 1024, width: 640, height: 420, name: "photo.jpg"))
    }

    func testImageRefFromAttachmentOnlyRequiresID() {
        // 缺字段兜底：只有 attachmentId 也要能出来，其余为 nil，不崩。
        let ref = DSHDecoding.imageRef(fromAttachment: ["attachmentId": "sha256:only"])
        XCTAssertEqual(ref?.attachmentId, "sha256:only")
        XCTAssertNil(ref?.mediaType)
        XCTAssertNil(ref?.bytes)
        XCTAssertNil(ref?.width)
        XCTAssertNil(ref?.height)
        XCTAssertNil(ref?.name)

        // 空字符串字段等同于缺字段
        let sparse = DSHDecoding.imageRef(fromAttachment: [
            "attachmentId": "sha256:sparse", "mediaType": "", "name": ""
        ])
        XCTAssertNil(sparse?.mediaType)
        XCTAssertNil(sparse?.name)
    }

    func testImageRefFromAttachmentBadRowsReturnNil() {
        XCTAssertNil(DSHDecoding.imageRef(fromAttachment: [:]))
        XCTAssertNil(DSHDecoding.imageRef(fromAttachment: ["mediaType": "image/png"]))
        XCTAssertNil(DSHDecoding.imageRef(fromAttachment: ["attachmentId": ""]))
        XCTAssertNil(DSHDecoding.imageRef(fromAttachment: ["attachmentId": "   "]))
        XCTAssertNil(DSHDecoding.imageRef(fromAttachment: ["attachmentId": 42]))
    }

    func testImageBlockDelegatesToAttachmentDecoding() {
        let block: [String: Any] = [
            "type": "image",
            "attachment": ["attachmentId": "sha256:block", "mediaType": "image/png", "width": 100]
        ]
        XCTAssertEqual(DSHDecoding.imageRef(from: block)?.attachmentId, "sha256:block")
        XCTAssertEqual(DSHDecoding.imageRef(from: block)?.width, 100)

        // attachment 被拍平到 block 上时的兜底
        let flattened: [String: Any] = ["type": "image", "attachmentId": "sha256:flat"]
        XCTAssertEqual(DSHDecoding.imageRef(from: flattened)?.attachmentId, "sha256:flat")

        XCTAssertNil(DSHDecoding.imageRef(from: ["type": "text", "attachment": ["attachmentId": "x"]]))
        XCTAssertNil(DSHDecoding.imageRef(from: ["type": "image"]))
    }
}
