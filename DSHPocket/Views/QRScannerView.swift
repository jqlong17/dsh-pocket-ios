// QRScannerView

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


struct QRScannerView: View {
    let onCode: (String) -> Void
    var body: some View {
        Group {
            if DataScannerViewController.isSupported {
                if DataScannerViewController.isAvailable { PocketCodeScanner(onCode: onCode).ignoresSafeArea(edges: .bottom) }
                else { ContentUnavailableView("相机暂不可用", systemImage: "camera.fill", description: Text("请在设置中允许 DSH Pocket 使用相机，然后重试。")) }
            } else { ContentUnavailableView("此设备不支持扫码", systemImage: "qrcode", description: Text("请手动输入 DSH Pocket 地址。")) }
        }
    }
}
