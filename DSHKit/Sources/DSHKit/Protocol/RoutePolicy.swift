import Foundation

/// 自动选路的偏好。
public enum RoutePreference: String, Sendable, Equatable {
    /// 不自动切换（默认）。尊重用户手选。
    case manual
    /// 局域网可达就用局域网；否则选 RTT 最低的可达地址。
    case lanFirst
}

/// 参与选路的一条地址。
public struct RouteCandidate: Equatable, Sendable {
    public let address: String
    public let kind: DSHEndpointKind
    public let reachable: Bool
    /// 只做了 TCP 探测时为 nil（能连通但没测到往返时延）。
    public let rttMs: Int?

    public init(address: String, kind: DSHEndpointKind, reachable: Bool, rttMs: Int?) {
        self.address = address
        self.kind = kind
        self.reachable = reachable
        self.rttMs = rttMs
    }
}

/// 选路策略：纯判断，无网络、无 UI。
public enum RoutePolicy {
    /// 返回应使用的地址；nil 表示「保持现状」。
    ///
    /// 判定顺序（每一层都有明确理由）：
    /// 1. `manual` 一律不动——用户手选过的路不该被悄悄改掉；
    /// 2. **可达的局域网优先**——即便它的 RTT 数字不是最小，局域网省掉的是
    ///    TLS 握手 + 隧道封装，这是固定开销，比几毫秒的 RTT 差异大得多；
    /// 3. 局域网都不可达时，选可达候选里 RTT 最小的；
    /// 4. 有候选但全不可达 → nil（宁可保持现状，也不切到一个已知不通的地址）。
    public static func choose(
        from candidates: [RouteCandidate],
        preference: RoutePreference
    ) -> String? {
        guard preference == .lanFirst else { return nil }
        guard !candidates.isEmpty else { return nil }

        let reachable = candidates.filter { $0.reachable }
        guard !reachable.isEmpty else { return nil }

        let lanReachable = reachable.filter { $0.kind == .lan }
        let pool = lanReachable.isEmpty ? reachable : lanReachable
        return sortByLatency(pool).first?.address
    }

    /// RTT 小的在前；没有 RTT 的排在最后（可选中，但优先级最低）。
    /// 同 RTT 时按地址字典序，保证结果稳定（避免每次选到不同地址）。
    static func sortByLatency(_ candidates: [RouteCandidate]) -> [RouteCandidate] {
        candidates.sorted { left, right in
            switch (left.rttMs, right.rttMs) {
            case let (l?, r?):
                if l != r { return l < r }
                return left.address < right.address
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.address < right.address
            }
        }
    }
}
