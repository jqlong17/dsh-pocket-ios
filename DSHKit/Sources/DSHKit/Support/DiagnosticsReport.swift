import Foundation

/// 诊断报告的结构化渲染。
///
/// 为什么在 DSHKit 而不是 App 层：列对齐、字段缺省、事件截断都是纯逻辑，
/// 可以穷举测试；App 层没有测试 target，放进去就测不到。
///
/// 为什么全英文：诊断日志的读者是「排查问题的人」，不一定是说中文的人。
/// iOS 生态里崩溃报告、控制台输出、sysdiagnose 都是英文，跨语言沟通不需要再翻译一遍。
/// App 内其他文案继续本地化，只有这份报告固定英文。
///
/// 格式参考 Apple 系统诊断报告：头部元信息 → 分区 → 键值对齐 → 最近事件。
/// 不逐字段写解释——那会让报告变成教程，真正的数字被解释淹没。
public struct DiagnosticsReport: Sendable {
    public struct Header: Sendable {
        public var generated: Date
        public var appVersion: String
        public var build: String
        public var device: String
        public var system: String
        public var locale: String

        public init(generated: Date, appVersion: String, build: String,
                    device: String, system: String, locale: String) {
            self.generated = generated
            self.appVersion = appVersion
            self.build = build
            self.device = device
            self.system = system
            self.locale = locale
        }
    }

    /// 一段报告：标题 + 有序键值对。
    public struct Section: Sendable {
        public var title: String
        public var rows: [(String, String)]

        public init(_ title: String, _ rows: [(String, String)]) {
            self.title = title
            self.rows = rows
        }
    }

    public struct Input: Sendable {
        public var header: Header
        public var sections: [Section]
        /// 最近事件（已格式化好的单行文本，按时间升序）。
        public var events: [String]
        /// 末尾固定说明（只放真正容易误读的几条）。
        public var notes: [String]

        public init(header: Header, sections: [Section],
                    events: [String] = [], notes: [String] = []) {
            self.header = header
            self.sections = sections
            self.events = events
            self.notes = notes
        }
    }

    /// 键列宽：所有键左对齐到这一列，值从固定列开始。
    /// 12 是实测最长的键（`Compressed` = 10，`Last frame` = 10），留 2 位余量。
    public static let keyColumnWidth = 14
    /// 事件最多保留条数（手机粘贴到聊天里，太长反而没人看）。
    public static let maxEvents = 30

    public static func render(_ input: Input) -> String {
        var out: [String] = []

        // 头部：一行标题 + 元信息
        out.append("DSH Pocket Diagnostics")
        out.append(String(repeating: "=", count: 52))
        for (key, value) in [
            ("Generated", isoString(input.header.generated)),
            ("App", "\(input.header.appVersion) (\(input.header.build))"),
            ("Device", input.header.device),
            ("System", input.header.system),
            ("Locale", input.header.locale)
        ] {
            out.append(row(key, value))
        }

        // 分区
        for section in input.sections {
            out.append("")
            out.append("[ \(section.title) ]")
            for (key, value) in section.rows {
                out.append(row(key, value))
            }
        }

        // 说明：只放真正容易误读的
        if !input.notes.isEmpty {
            out.append("")
            out.append("[ Notes ]")
            for note in input.notes {
                out.append("· \(note)")
            }
        }

        // 最近事件
        out.append("")
        out.append("[ Recent Events ]")
        if input.events.isEmpty {
            out.append("(none)")
        } else {
            let shown = input.events.count > maxEvents
                ? Array(input.events.suffix(maxEvents))
                : input.events
            if input.events.count > maxEvents {
                out.append("(showing last \(maxEvents) of \(input.events.count))")
            }
            out.append(contentsOf: shown)
        }

        return out.joined(separator: "\n")
    }

    // MARK: - 行格式

    /// `key` 左对齐到固定列，值从固定列开始。粘贴到等宽字体里是对齐的。
    static func row(_ key: String, _ value: String) -> String {
        let pad = max(1, keyColumnWidth - key.count)
        return key + String(repeating: " ", count: pad) + value
    }

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// 事件行：`HH:mm:ss  text`。时间列固定，方便扫读。
    public static func eventLine(at date: Date, text: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return "\(formatter.string(from: date))  \(text)"
    }

    /// 字节数转可读（KB / MB）。
    public static func bytes(_ value: Int) -> String {
        if value < 1024 { return "\(value) B" }
        let kb = Double(value) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    /// 缺省值：没打开会话时用它，而不是留空或崩。
    public static let missing = "—"
}
