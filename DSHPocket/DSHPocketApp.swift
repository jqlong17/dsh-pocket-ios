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
    @State private var model = ConnectionModel()

    init() {
        // 必须在 didFinishLaunching 之前注册，否则首次唤醒会失败。
        BackgroundRefresh.register()
        // 记录启动瞬间的内存，用来判断「空载高」是框架开销还是我们自己的问题。
        // 写到文件而不是 os.Logger：真机上只有文件能用 devicectl 直接拷出来。
        DiagFileLog.reset()
        DiagFileLog.log("boot-t0 footprint=\(Int(Diagnostics.memoryFootprintMB()))MB")
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, sessionStore: model.sessionStore)
                .preferredColorScheme(.light)
                .task {
                    // DEBUG 自动化：地址和密码都从环境变量来，启动即连，
                    // 供手机端插件面板的截图/端到端验证使用（正式包恒为 false）。
                    guard ConnectionModel.debugAutoConnect else { return }
                    await model.connect()
                }
        }
    }
}
