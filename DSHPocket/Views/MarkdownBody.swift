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
/// 只画 1 像素的线与外框，不铺隔行底色：Textual 的 dividers 给的是整段间隙，
/// 直接填会变成粗灰带（踩过）。
struct PhoneTableStyle: StructuredText.TableStyle {
    private static let hairline: CGFloat = 1
    private static let maxWidthRatio: CGFloat = 2.2
    private static let fontSize: CGFloat = 15
    private static let line = Color.primary.opacity(0.16)

    func makeBody(configuration: StructuredText.TableStyleConfiguration) -> some View {
        Overflow { state in
            let maxWidth = state.containerWidth.map { $0 * Self.maxWidthRatio }
            configuration.label
                .font(.system(size: Self.fontSize))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .textual.tableCellSpacing(horizontal: 0, vertical: 0)
                .textual.tableOverlay { layout in
                    Canvas { context, _ in
                        // 行线：每行顶部一条 1 点
                        for row in layout.rowIndices.dropFirst() {
                            let bounds = layout.rowBounds(row)
                            let rect = CGRect(x: bounds.minX, y: bounds.minY - Self.hairline / 2,
                                              width: bounds.width, height: Self.hairline)
                            context.fill(Path(rect), with: .style(Self.line))
                        }
                        // 列线：只取竖直方向的分隔，压成 1 点宽
                        for divider in layout.dividers() where divider.height > divider.width {
                            let rect = CGRect(x: divider.midX - Self.hairline / 2, y: divider.minY,
                                              width: Self.hairline, height: divider.height)
                            context.fill(Path(rect), with: .style(Self.line))
                        }
                    }
                }
                .padding(Self.hairline)
                .border(Self.line, width: Self.hairline)
        }
        .textual.blockSpacing(.fontScaled(top: 1.4, bottom: 1.4))
    }
}
