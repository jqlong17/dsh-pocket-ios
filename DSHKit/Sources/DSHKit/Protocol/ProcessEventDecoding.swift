import Foundation

/// 过程事件 / 分页记录 / 图片附件的统一解析入口。
///
/// 约定：App 层不再自己 `as? [String: Any]` 拆协议字段，只消费这里的类型化结果。
/// 所有入口都对坏数据宽容——缺字段、类型不对、非过程事件一律丢弃（返回 nil / `.unknown` /
/// 空数组），绝不抛错，保证一条坏记录不会影响整页历史。
extension DSHDecoding {
    // MARK: - 单条记录 → 过程事件

    /// 一条 `session/page` 记录（`{"event": {...}}`）→ 过程事件。
    /// 直接传裸事件字典（follow 帧里的 `value["event"]`）也可以。
    /// 不是 tool/call、tool/result、turn/start、turn/end 的事件返回 nil。
    public static func stepEvent(fromRecord record: [String: Any]) -> DSHStepEvent? {
        guard let event = eventPayload(fromRecord: record) else { return nil }
        return stepEvent(fromEvent: event)
    }

    /// `session/page` 的 records → 过程事件数组。
    /// 坏行、消息事件、标题事件等非过程事件直接丢弃；空集合返回空数组。
    public static func stepEvents(fromRecords records: [[String: Any]]) -> [DSHStepEvent] {
        records.compactMap(stepEvent(fromRecord:))
    }

    // MARK: - 单条记录 → 类型化条目

    /// 一条事件的类型化分发：消息 / 过程事件 / 标题 / 无法识别。
    /// 与 `page(fromValue:)` 共用这一份分发逻辑，保证实时流与历史分页结果一致。
    public static func record(fromEvent event: [String: Any]) -> DSHRecord {
        if let message = message(fromEvent: event) { return .message(message) }
        if let step = stepEvent(fromEvent: event) { return .step(step) }
        if event["type"] as? String == "session/title",
           let seq = (event["seq"] as? NSNumber)?.intValue,
           let data = event["data"] as? [String: Any],
           let title = data["title"] as? String {
            return .title(seq: seq, title: title)
        }
        return .unknown
    }

    /// 一条 `session/page` 记录（`{"event": {...}}`）→ 类型化条目。
    /// 记录里既没有 event 也没有 type 时返回 `.unknown`。
    public static func record(fromRecord raw: [String: Any]) -> DSHRecord {
        guard let event = eventPayload(fromRecord: raw) else { return .unknown }
        return record(fromEvent: event)
    }

    /// `session/page` 的 records → 类型化条目数组（保持原始顺序，坏行为 `.unknown`）。
    /// App 的 `mergeSteps` 可直接消费：`.step` 交给过程列表、`.title` 更新标题、其余忽略。
    public static func records(fromRecords records: [[String: Any]]) -> [DSHRecord] {
        records.map(record(fromRecord:))
    }

    // MARK: - 事件时间

    /// 事件头部的 `time`（毫秒时间戳）→ `Date`。缺失、非数字、非正数时返回 nil。
    /// turn/start 的启动时刻在事件头部而不是 data 里，需要单独取。
    public static func eventTimestamp(fromEvent event: [String: Any]) -> Date? {
        guard let milliseconds = (event["time"] as? NSNumber)?.doubleValue,
              milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    // MARK: - 图片附件

    /// image block 里的 attachment 字典 → 图片引用。
    /// 只有 `attachmentId` 是必需的；mediaType/bytes/width/height/name 缺哪个就留 nil。
    public static func imageRef(fromAttachment attachment: [String: Any]) -> DSHImageRef? {
        guard let rawId = attachment["attachmentId"] as? String else { return nil }
        let attachmentId = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachmentId.isEmpty else { return nil }
        return DSHImageRef(
            attachmentId: attachmentId,
            mediaType: nonEmptyString(attachment["mediaType"]),
            bytes: (attachment["bytes"] as? NSNumber)?.intValue,
            width: (attachment["width"] as? NSNumber)?.intValue,
            height: (attachment["height"] as? NSNumber)?.intValue,
            name: nonEmptyString(attachment["name"])
        )
    }

    // MARK: - 内部工具

    /// 取事件本体：优先 record 包着的 `event`，否则把 record 当裸事件。
    static func eventPayload(fromRecord record: [String: Any]) -> [String: Any]? {
        if record["event"] != nil {
            return record["event"] as? [String: Any]
        }
        return record["type"] != nil ? record : nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        return string.isEmpty ? nil : string
    }
}
