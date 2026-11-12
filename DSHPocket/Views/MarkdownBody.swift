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
            // 手机上别把表格列挤成一字一行：宽表横向滚动，宽度上限给到容器的 2.2 倍。
            // 必须放在 structuredTextStyle **之前**：.gitHub 会重置表格样式，放在后面等于没设。
            .textual.tableStyle(PhoneTableStyle())
            .textual.structuredTextStyle(.gitHub)
            .foregroundStyle(foreground)
    }
}


/// 手机上的 Markdown 表格。
///
/// Textual 自带的 `.gitHub` 有网格线但会把列挤窄（中文变成一字一行），
/// `.overflow` 能横滑却没有网格线。这里把两者合成：横滑 + 网格线 + 外框，
/// 字号比正文小一点（正文 17，表格 15）。
struct PhoneTableStyle: StructuredText.TableStyle {
    /// 内部网格线的厚度（单元格间距就是线宽）。0.5 点在 3x 屏上是 1.5 像素，比 1 点细一半。
    private static let gridWidth: CGFloat = 0.5
    /// 外框单独一条，略粗于内部线。
    private static let borderWidth: CGFloat = 1
    private static let maxWidthRatio: CGFloat = 2.2
    private static let fontSize: CGFloat = 15
    private static let line = Color.primary.opacity(0.14)
    private static let zebra = Color.primary.opacity(0.035)

    func makeBody(configuration: StructuredText.TableStyleConfiguration) -> some View {
        Overflow { state in
            let maxWidth = state.containerWidth.map { $0 * Self.maxWidthRatio }
            configuration.label
                .font(.system(size: Self.fontSize))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .textual.tableCellSpacing(horizontal: Self.gridWidth, vertical: Self.gridWidth)
                .textual.tableBackground { layout in
                    Canvas { context, _ in
                        for row in layout.rowIndices.dropFirst() where row.isMultiple(of: 2) {
                            context.fill(Path(layout.rowBounds(row).integral), with: .style(Self.zebra))
                        }
                    }
                }
                .textual.tableOverlay { layout in
                    Canvas { context, _ in
                        for divider in layout.dividers() {
                            context.fill(Path(divider), with: .style(Self.line))
                        }
                    }
                }
                .padding(Self.borderWidth)
                .border(Self.line, width: Self.borderWidth)
        }
        .textual.blockSpacing(.fontScaled(top: 1.4, bottom: 1.4))
    }
}
