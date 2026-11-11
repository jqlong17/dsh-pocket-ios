// PocketDraftImage

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


/// 待发送的本地图片（照片库 / 相机）。
struct PocketDraftImage: Identifiable {
    let id = UUID()
    let data: Data
    let mediaType: String
    let name: String
    let uiImage: UIImage
}
