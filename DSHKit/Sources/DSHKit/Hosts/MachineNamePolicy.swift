// MachineNamePolicy

import Foundation

/// 一次连接里「这条地址属于哪台机器」的判定（纯逻辑，可单测）。
///
/// 背景（2026-11-26 iPad 实测）：机器名存在全局状态里，配对响应**没带**
/// `x-dsh-machine` 头时会沿用上一台机器的名字，于是 Mac 与阿里云被并成一台主机。
/// 判定规则必须显式：**本次响应没有就当作未知（nil），绝不继承**。
public enum MachineNamePolicy {
    /// - Parameters:
    ///   - header: 本次 HTTP 响应里的 `x-dsh-machine`（没有则 nil）
    ///   - previous: 上一次连接留下的机器名（仅用于日志/诊断，不参与判定）
    /// - Returns: 本次应该归属的机器名；没有就是 nil
    public static func resolve(header: String?, previous: String? = nil) -> String? {
        guard let header else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
