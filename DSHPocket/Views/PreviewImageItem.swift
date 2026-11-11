// PreviewImageItem

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


struct PreviewImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}
