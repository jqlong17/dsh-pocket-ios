// ProcessRow

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


struct ProcessRow: View {
    let group: PocketStepGroup
    let expanded: Bool
    var loading = false
    @Bindable var model: ConnectionModel
    let toggle: () -> Void

    /// 最后一条未完成的步骤 = 当前正在执行的动作。
    private var runningStep: PocketStep? {
        group.steps.last(where: { !$0.finished })
    }

    private var summary: String {
        if let runningStep {
            return "\(runningStep.runningLabel) · \(group.steps.count) 步"
        }
        var seen = Set<String>()
        var labels: [String] = []
        for step in group.steps where !seen.contains(step.label) {
            seen.insert(step.label)
            labels.append(step.label)
        }
        let joined = labels.prefix(3).joined(separator: "、")
        return "过程 · \(group.steps.count) 步 · \(joined)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 16, height: 16)
                    Text(summary).font(.footnote).lineLimit(2)
                        .foregroundStyle(runningStep == nil ? .secondary : Color(red: 0.08, green: 0.48, blue: 0.37))
                    if runningStep != nil {
                        ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 整行朗读成一句，不要逐字读「过程 · 4 步 · …」里的分隔符。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AccessibilityLabels.processGroup(
                stepLabels: group.steps.map(\.label),
                runningLabel: runningStep?.runningLabel
            ))
            .accessibilityHint(expanded ? "双击收起过程" : "双击展开过程")

            if expanded {
                if loading {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("正在读取过程…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(group.steps) { step in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .top, spacing: 8) {
                                Group {
                                    if step.finished {
                                        Image(systemName: step.icon).font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        ProgressView().scaleEffect(0.55)
                                    }
                                }.frame(width: 16)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(step.finished ? step.label : step.runningLabel)
                                        .font(.footnote)
                                        .foregroundStyle(step.finished ? .primary : Color(red: 0.08, green: 0.48, blue: 0.37))
                                    if !step.detail.isEmpty {
                                        Text(ProcessResultSummary.shortPath(step.detail))
                                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    let summary = ProcessResultSummary.display(tool: step.name, raw: step.resultText)
                                    if !summary.isEmpty {
                                        Text(summary).font(.caption2)
                                            .foregroundStyle(.secondary).lineLimit(4)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            ForEach(step.images) { ref in
                                AttachmentThumbnail(ref: ref, model: model, size: 180)
                            }
                        }
                    }
                }
                .padding(.leading, 2)
                // 展开：淡入 + 顶部锚点微缩放。不要用 .move(edge: .top)，文字会从上一行上方滑下来。
                // 收起：不要淡出。opacity 的 removal 会把字画在旧位置的浮层上，卡片高度先塌，字就压到下一条消息。
                .padding(.top, 4)
                .padding(.horizontal, 12)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                    removal: .identity
                ))
                .clipped()
            }
        }
        .animation(PocketMotion.animation(.easeInOut(duration: 0.22)), value: expanded)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
