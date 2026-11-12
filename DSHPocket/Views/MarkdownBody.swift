// MarkdownBody

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


struct MarkdownBody: View {
    let text: String
    var foreground: Color = .primary

    var body: some View {
        StructuredText(markdown: text)
            .textual.textSelection(.enabled)
            // 注意顺序：headingStyle 必须放在 structuredTextStyle 之前（更靠近内容），
            // 否则会被 .gitHub 内置的 headingStyle 覆盖（踩过：改字号完全不生效）。
            .textual.headingStyle(ChatHeadingStyle())
            .textual.structuredTextStyle(.gitHub)
            // 手机上别把表格列挤成一字一行：宽表改成横向滚动，宽度上限给到容器的 2.2 倍。
            // 注：tableStyle 要放在 structuredTextStyle 之后才生效（同 headingStyle 的覆盖规则）。
            .textual.tableStyle(.overflow(relativeWidth: 2.2))
            .foregroundStyle(foreground)
    }
}
