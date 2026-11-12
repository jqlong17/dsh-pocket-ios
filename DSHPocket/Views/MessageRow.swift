// MessageRow

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


struct MessageRow: View {
    let message: PocketMessage
    @Bindable var model: ConnectionModel
    @State private var previewItem: PreviewImageItem?
    @State private var copied = false
    /// 只在"复制成功"时递增，避免图标恢复时再触发一次触感。
    @State private var copyHapticTick = 0

    private var hasUserImages: Bool {
        message.isUser && (!message.localImages.isEmpty || !message.images.isEmpty)
    }

    /// 用户消息开头的 Markdown 引用块（`> ` 行）：单独渲染成白色半透明引用卡片，
    /// 否则会套用 Markdown 的深色 blockquote 样式，在绿色气泡上几乎看不见。
    private var leadingQuote: (quote: String, rest: String)? {
        guard message.isUser else { return nil }
        let lines = message.text.components(separatedBy: "\n")
        var quoteLines: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("> ") {
                quoteLines.append(String(line.dropFirst(2)))
                index += 1
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty,
                      !quoteLines.isEmpty,
                      index + 1 < lines.count,
                      lines[index + 1].hasPrefix("> ") {
                index += 1
            } else {
                break
            }
        }
        guard !quoteLines.isEmpty else { return nil }
        let rest = lines[index...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (quoteLines.joined(separator: "\n"), rest)
    }

    /// 气泡内的 Markdown（含原位置插图）。
    @ViewBuilder
    private var markdownContent: some View {
        if message.isUser, let quoted = leadingQuote {
            userQuotedContent(quoted)
        } else {
            plainMarkdownContent
        }
    }

    @ViewBuilder
    private func userQuotedContent(_ quoted: (quote: String, rest: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Capsule().fill(Color.white.opacity(0.7)).frame(width: 3)
                Text(quoted.quote)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            if !quoted.rest.isEmpty {
                ForEach(Array(model.markdownSegments(quoted.rest).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let markdown):
                        MarkdownBody(text: markdown, foreground: .white)
                            .textSelection(.enabled)
                            .tint(Color(red: 0.10, green: 0.35, blue: 0.95))
                    case .image(let url, let caption):
                        RemoteMarkdownImage(url: url, caption: caption)
                    }
                }
            }
        }
        
    }

    @ViewBuilder
    private var plainMarkdownContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(model.markdownSegments(message.text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let markdown):
                    MarkdownBody(text: markdown, foreground: message.isUser ? .white : .primary)
                        .textSelection(.enabled)
                        // 绿色气泡里选区高亮默认取全局绿色 tint → 选中几乎看不出来。
                        // 保持同一绿色色系，用更浅的薄荷绿做选区高亮，和深绿气泡形成明暗对比；
                        // 助手气泡保持默认主题色。
                        .tint(message.isUser ? Color(red: 0.66, green: 0.95, blue: 0.84) : nil)
                case .image(let url, let caption):
                    RemoteMarkdownImage(url: url, caption: caption)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 用户消息的图片缩略图（气泡内左下角，小尺寸）。
    @ViewBuilder
    private var userImageThumbnails: some View {
        HStack(spacing: 6) {
            if !message.localImages.isEmpty {
                ForEach(Array(message.localImages.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { previewItem = PreviewImageItem(image: image) }
                }
            } else {
                ForEach(message.images) { ref in
                    AttachmentThumbnail(ref: ref, model: model, size: 88)
                }
            }
        }
    }

    private func pendingStateColor(_ state: ConnectionModel.PendingSendState) -> Color {
        switch state {
        case .failed: return Color.red.opacity(0.85)
        case .queued: return Color.orange
        default: return Color.secondary
        }
    }

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !message.isUser {
                    Image(systemName: "sparkle").foregroundStyle(PocketChrome.brandText)
                }
                Text(message.isUser ? L10n.t("你") : "DSH").foregroundStyle(.secondary)
                if !message.text.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.text
                        copyHapticTick &+= 1
                        AccessibilityAnnouncer.announce("已复制整条消息")
                        withAnimation(PocketMotion.animation(.easeInOut(duration: 0.15))) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            withAnimation(PocketMotion.animation(.easeInOut(duration: 0.15))) { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(copied ? PocketChrome.brandText : .secondary)
                            .frame(width: 14, height: 14)
                            .scaleEffect(copied ? 1.15 : 1)
                            .animation(PocketMotion.animation(.spring(response: 0.22, dampingFraction: 0.6)), value: copied)
                            // 图标本身 14pt，补到 44pt 的可点区域，手抖也能点中。
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copied ? "已复制" : "复制整条消息")
                    .sensoryFeedback(.success, trigger: copyHapticTick)
                    Button {
                        model.beginQuote(message)
                    } label: {
                        Image(systemName: "quote.bubble")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("引用这条消息")
                }
            }.font(.caption2.weight(.semibold))
            HStack {
                if message.isUser { Spacer(minLength: 44) }
                VStack(alignment: .leading, spacing: 8) {
                    if message.isUser, hasUserImages {
                        // 用户发送的图片：作为小缩略图放在气泡内的左下角。
                        VStack(alignment: .leading, spacing: 8) {
                            if !message.text.isEmpty { markdownContent }
                            userImageThumbnails
                        }
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Color(red: 0.08, green: 0.48, blue: 0.37),
                                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .foregroundStyle(.white)
                    } else {
                        // 助手消息里的 attachment 图片仍显示在气泡上方。
                        if !message.isUser, !message.localImages.isEmpty {
                            ForEach(Array(message.localImages.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 150, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .contentShape(Rectangle())
                                    .onTapGesture { previewItem = PreviewImageItem(image: image) }
                            }
                        } else if !message.isUser, !message.images.isEmpty {
                            ForEach(message.images) { ref in
                                AttachmentThumbnail(ref: ref, model: model, size: 150)
                            }
                        }
                        if !message.text.isEmpty {
                            markdownContent
                                
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(message.isUser ? Color(red: 0.08, green: 0.48, blue: 0.37) : Color(red: 0.949, green: 0.949, blue: 0.965), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.primary.opacity(message.isUser ? 0 : 0.05), lineWidth: 0.5)
                                )
                                .foregroundStyle(message.isUser ? .white : .primary)
                        }
                    }
                }
                if !message.isUser { Spacer(minLength: 44) }
            }
            if message.isPending, let state = model.pendingSendState(for: message) {
                HStack(spacing: 5) {
                    switch state {
                    case .sending:
                        ProgressView().scaleEffect(0.55).frame(width: 11, height: 11)
                        Text(L10n.t("发送中…"))
                    case .acked(let steered):
                        Image(systemName: steered ? "arrow.triangle.branch" : "clock").font(.caption2)
                        Text(steered ? L10n.t("已引导，正在继续") : L10n.t("已发出，等待处理"))
                    case .failed:
                        Image(systemName: "exclamationmark.circle").font(.caption2)
                        Text(L10n.t("发送失败"))
                        Button(L10n.t("重新发送")) { model.retryPendingMessage(message) }
                            .buttonStyle(.borderless)
                            .font(.caption2.weight(.semibold))
                    case .queued:
                        Image(systemName: "wifi.slash").font(.caption2)
                        Text(L10n.t("等待网络，恢复后自动发送"))
                    }
                }
                .font(.caption2)
                .foregroundStyle(pendingStateColor(state))
                .padding(.horizontal, 4)
            }
        }.frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        .fullScreenCover(item: $previewItem) { item in
            FullscreenImageViewer(image: item.image)
        }
    }
}
