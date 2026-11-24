// SavedEndpoint

import SwiftUI
import Security
import DSHKit
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import Photos
import os
import AudioToolbox
import ImageIO
import UserNotifications


/// 记住连接过的地址（局域网/公网），供用户手动切换，避免每次重新扫码。
struct SavedEndpoint: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case lan
        case publicNetwork
        case custom

        var label: String {
            switch self {
            case .lan: return L10n.t("局域网")
            case .publicNetwork: return L10n.t("公网")
            case .custom: return L10n.t("自定义")
            }
        }
    }

    let address: String
    let kind: Kind
    var lastUsedAt: Double
    /// 用户自定义标签，例如「公司」「家」；为空时显示 kind.label。
    var label: String?
    /// 这台地址属于哪台 DSH（由插件报出的 hostname）。
    /// 同一台机器可能有多条地址（局域网 + Tailscale），靠它归组；老数据没有，保持 nil。
    var machine: String?

    var id: String { address }
    var displayName: String { label ?? kind.label }
}

extension SavedEndpoint.Kind {
    init(_ kind: DSHEndpointKind) {
        switch kind {
        case .lan: self = .lan
        case .publicNetwork: self = .publicNetwork
        case .custom: self = .custom
        }
    }

    var policyKind: DSHEndpointKind {
        switch self {
        case .lan: return .lan
        case .publicNetwork: return .publicNetwork
        case .custom: return .custom
        }
    }
}
