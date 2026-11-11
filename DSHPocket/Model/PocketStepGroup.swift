// PocketStepGroup

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


/// 同一 turn 内的一组步骤，UI 里折叠成一行"过程"。
struct PocketStepGroup: Identifiable {
    let turn: Int
    let sequence: Int
    let steps: [PocketStep]
    /// 同一 turn 里可能有多段"过程"（被助手文字分隔），用起始 seq 作为唯一 id。
    var id: String { "steps-\(sequence)" }
}
