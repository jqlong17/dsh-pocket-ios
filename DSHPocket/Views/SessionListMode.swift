// SessionListMode

import SwiftUI
import Security
import Textual
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



enum SessionListMode: String, CaseIterable, Identifiable {
    case grouped
    case timeline
    var id: String { rawValue }
    func title() -> String {
        switch self {
        case .grouped: L10n.t("按工作区分组")
        case .timeline: L10n.t("按时间线")
        }
    }
}
