// TurnFailureRow

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


struct TurnFailureRow: View {
    let failure: TurnFailureNotice

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("本轮运行失败"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                Text(failure.displayText)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let code = failure.code, !code.isEmpty {
                    Text(code)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.t("本轮运行失败")) \(failure.displayText)")
    }
}
