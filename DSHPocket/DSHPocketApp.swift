// 应用入口

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


@main
struct DSHPocketApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @State private var model = ConnectionModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model, sessionStore: model.sessionStore)
                .preferredColorScheme(.light)
        }
    }
}
