// ChatHeadingStyle

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


/// 聊天气泡里的标题：比默认更克制（默认 H1/H2 太大）。
struct ChatHeadingStyle: StructuredText.HeadingStyle {
    // 以 Textual 基准字号 17pt（iOS .body）计算：
    // H1 17 / H2 16.5 / H3 16 / H4 15.5 / H5 15 / H6 14.5。移动端与正文接近。
    // 移动端：标题贴近正文大小，避免在气泡里过于抢眼。
    // 注意：Textual 的 fontScale 会叠加在 .gitHub 默认大标题之上（实测 H1 ≈ 1.4 倍正文），
    // 所以这里直接用显式字号覆盖，保证移动端标题与正文接近。
    // fontScale 是乘在 .gitHub 默认标题字号上的（H1≈24pt），因此用 ~0.7 压到正文附近。
    private static let fontScales: [CGFloat] = [0.72, 0.78, 0.84, 0.90, 0.93, 0.96]

    func makeBody(configuration: Configuration) -> some View {
        let index = min(max(configuration.headingLevel - 1, 0), Self.fontScales.count - 1)
        configuration.label
            .textual.fontScale(Self.fontScales[index])
            .fontWeight(.semibold)
            .textual.blockSpacing(.fontScaled(top: 0.8, bottom: 0.3))
    }
}
