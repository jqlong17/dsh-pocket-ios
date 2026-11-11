import Foundation

/// 已保存端点的类型。判断规则集中在这里，App 只负责持久化与编排。
public enum DSHEndpointKind: String, Sendable, Codable, Equatable {
    case lan
    case publicNetwork
    case custom
}

/// 去重/配额用的端点记录，不含 UI 文案。
public struct DSHSavedEndpointRecord: Equatable, Sendable {
    public var address: String
    public var kind: DSHEndpointKind
    public var lastUsedAt: Double
    public var label: String?

    public init(address: String, kind: DSHEndpointKind, lastUsedAt: Double, label: String? = nil) {
        self.address = address
        self.kind = kind
        self.lastUsedAt = lastUsedAt
        self.label = label
    }
}

/// 端点类型、去重配额，以及是否自动播种开发地址。
public enum DSHEndpointPolicy {
    /// 局域网最多 3 个（可分别命名「公司」「家」），公网 1 个，自定义 2 个。
    public static let lanLimit = 3
    public static let publicNetworkLimit = 1
    public static let customLimit = 2

    public static func kind(of address: String) -> DSHEndpointKind {
        guard let url = URL(string: address), let host = url.host?.lowercased() else { return .custom }
        if host == "localhost" || host.hasSuffix(".local") { return .lan }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            let a = parts[0], b = parts[1]
            if a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && (16...31).contains(b)) {
                return .lan
            }
        }
        if host.contains("trycloudflare.com") || url.scheme == "https" { return .publicNetwork }
        return .custom
    }

    /// 去重 + 配额：按最近使用排序，超出配额的丢掉。不删除用户仍在配额内的手工保存项。
    public static func dedup(_ list: [DSHSavedEndpointRecord]) -> [DSHSavedEndpointRecord] {
        var kept: [DSHSavedEndpointRecord] = []
        var seenAddresses = Set<String>()
        var lanCount = 0
        var publicCount = 0
        var customCount = 0
        for endpoint in list.sorted(by: { $0.lastUsedAt > $1.lastUsedAt }) {
            guard !seenAddresses.contains(endpoint.address) else { continue }
            switch endpoint.kind {
            case .lan:
                guard lanCount < lanLimit else { continue }
                lanCount += 1
            case .publicNetwork:
                guard publicCount < publicNetworkLimit else { continue }
                publicCount += 1
            case .custom:
                guard customCount < customLimit else { continue }
                customCount += 1
            }
            seenAddresses.insert(endpoint.address)
            kept.append(endpoint)
        }
        return kept
    }

    /// 正式包不得自动播种开发地址。DEBUG 下仅当列表里还没有同一地址时才播种。
    /// 不负责写入存储，也不删除已有端点。
    public static func shouldAutoSeedDevelopmentEndpoint(
        isDebugBuild: Bool,
        existingAddresses: [String],
        developmentAddress: String
    ) -> Bool {
        guard isDebugBuild else { return false }
        guard !developmentAddress.isEmpty else { return false }
        return !existingAddresses.contains(developmentAddress)
    }
}
