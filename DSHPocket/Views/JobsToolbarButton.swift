// JobsToolbarButton

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


/// 右上角后台任务入口。没有在跑的任务时不出现；有几个在跑就显示几，点开才看具体任务。
struct JobsToolbarButton: View {
    @Bindable var model: ConnectionModel

    private var running: [PocketJob] { model.runningJobs }

    var body: some View {
        if !running.isEmpty {
            Button {
                model.showingJobs = true
            } label: {
                Text("\(running.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(PocketChrome.brand)
                    .frame(minWidth: 22, minHeight: 22)
            }
            .accessibilityLabel("\(running.count) 个后台任务")
            .sheet(isPresented: $model.showingJobs) {
                JobsSheet(model: model)
            }
        }
    }
}

enum PocketChrome {
    static let brand = Color(red: 0.08, green: 0.48, blue: 0.37)
}

extension View {
    /// 系统玻璃按钮，和设置页右上角「完成」同一套。不自己描边。
    @ViewBuilder
    func pocketSystemGlassButton() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    func pocketSystemGlassField(cornerRadius: CGFloat = 18) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// 圆形玻璃控件。高度由调用方给定，不额外外扩，便于和输入框对齐。
    @ViewBuilder
    func pocketSystemGlassCircle(size: CGFloat) -> some View {
        if #available(iOS 26, *) {
            self
                .frame(width: size, height: size)
                .glassEffect(.regular, in: Circle())
        } else {
            self
                .frame(width: size, height: size)
                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
        }
    }
}
