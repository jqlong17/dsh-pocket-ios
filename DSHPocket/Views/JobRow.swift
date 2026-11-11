// JobRow

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


struct JobRow: View {
    let job: PocketJob
    @State private var now = Date()

    private var duration: String {
        let start = Date(timeIntervalSince1970: job.startedAt / 1000)
        let end = job.finishedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds) 秒" }
        if seconds < 3600 { return "\(seconds / 60) 分 \(seconds % 60) 秒" }
        return "\(seconds / 3600) 时 \(seconds % 3600 / 60) 分"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(job.isRunning ? Color(red: 0.08, green: 0.48, blue: 0.37) : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(job.statusLabel)
                        .font(.caption2)
                        .foregroundStyle(job.isRunning ? Color(red: 0.08, green: 0.48, blue: 0.37) : .secondary)
                    Text(duration)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !job.startedLabel.isEmpty {
                        Text("\(L10n.t("开始于")) \(job.startedLabel)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 6) {
                    Text(job.kindLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let progress = job.progress, !progress.isEmpty {
                        Text(progress).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let detail = job.detail, !detail.isEmpty {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .task(id: job.isRunning) {
            // 运行中每秒刷新一次时长；结束后不再打表。
            guard job.isRunning else { return }
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
