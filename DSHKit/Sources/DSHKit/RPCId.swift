import Foundation

/// rpcId 规范化与匹配（大小写无关）。
///
/// 背景：客户端用 `UUID().uuidString`（大写）作为 requestId，DSH 落库时会回填
/// `source.rpcId` 为**小写**。若直接做字符串比较，pending 永远无法被确认，
/// 表现为消息一直卡在"发送中"。所有 rpcId 比较都必须经过这里。
public enum RPCId {
    public static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    public static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalized(lhs), let rhs = normalized(rhs) else { return false }
        return lhs == rhs
    }
}
