// JobsSheet

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


struct JobsSheet: View {
    @Bindable var model: ConnectionModel
    @Environment(\.dismiss) private var dismiss

    private var sorted: [PocketJob] {
        model.jobs.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
            return lhs.startedAt > rhs.startedAt
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sorted.isEmpty {
                    ContentUnavailableView(L10n.t("没有后台任务"), systemImage: "gearshape.2",
                                           description: Text(L10n.t("这个会话还没有启动后台任务。")))
                } else {
                    List(sorted) { job in
                        JobRow(job: job)
                    }
                }
            }
            .navigationTitle(L10n.t("后台任务"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("完成")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // 打开才订阅、关闭就取消：不可见的内容不占连接。
        .task { model.ensureJobRoster() }
        .onDisappear { model.stopJobRoster() }
    }
}
