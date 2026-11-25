import Foundation

/// 主机命名的纯逻辑。
///
/// 抽出来的原因（2026-11-25 实际故障）：应用层只比对「完全相等」的名字，
/// 用户把 `DSH 2` 改名成 `DSH 2 阿里云` 之后，`DSH 2` 又被判定为空闲，
/// 于是新机器也叫 `DSH 2`，列表里出现两台同名主机。
public enum HostNaming {
    public static let prefix = "DSH"

    /// 取下一个可用的默认名：`DSH 1`、`DSH 2`……
    ///
    /// 「已占用」的判据是**前缀匹配**：`DSH 2` 被占用时，`DSH 2 阿里云`
    /// 也算占用 `DSH 2`（用户改名通常会保留编号前缀）。
    public static func nextName(existing: [String]) -> String {
        var n = 1
        while existing.contains(where: { isTakenBy($0, number: n) }) {
            n += 1
        }
        return "\(prefix) \(n)"
    }

    /// 某个名字是否占用了编号 `n`。
    ///
    /// - `DSH 2`        → 占用
    /// - `DSH 2 阿里云`  → 占用（改名后缀）
    /// - `DSH 20`       → 不占用（数字必须整段匹配，避免 2 被 20 误判）
    public static func isTakenBy(_ name: String, number: Int) -> Bool {
        let target = "\(prefix) \(number)"
        guard name.hasPrefix(target) else { return false }
        let rest = name.dropFirst(target.count)
        if rest.isEmpty { return true }
        // 后面必须是非数字分隔（空格/括号/连字符等），否则是 DSH 20 之类
        guard let first = rest.first else { return true }
        return !first.isNumber
    }
}
