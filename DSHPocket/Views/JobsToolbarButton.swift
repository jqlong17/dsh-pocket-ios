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


/// 右上角后台任务入口。
///
/// 刻意不持有 model：只要它读 model 上的任何状态，工具栏就会随任务名单刷新反复求值，
/// 图标看起来会跟着任务数变。这里只收一个动作，弹窗由页面自己管。
struct JobsToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checklist")
        }
        .accessibilityLabel(L10n.t("后台任务"))
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
