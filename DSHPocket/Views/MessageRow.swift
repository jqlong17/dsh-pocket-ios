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
    /// 精简模式：只渲染纯文本摘要，不跑 Markdown。
    ///
    /// 用户明确说「只关心最近 3 条，更早的不关注」（2026-11-21）。
    /// Markdown 富文本是滚动掉帧的主要成本（实测滚动时 20ms/帧 = 50fps），
    /// 把更早的消息降级成纯文本能把「同时参与绘制的富文本行数」压到常数级。
    var isCompact: Bool = false
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
        if isCompact {
            compactContent
        } else if message.isUser, let quoted = leadingQuote {
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
                        MarkdownBody(text: markdown, foreground: .white).equatable()
                            .textSelection(.enabled)
                            .tint(Color(red: 0.10, green: 0.35, blue: 0.95))
                    case .image(let url, let caption):
                        RemoteMarkdownImage(url: url, caption: caption,
                                        allImageURLs: model.conversationMarkdownImageURLs)
                    }
                }
            }
        }
        
    }

    /// 精简模式的内容块。
    ///
    /// 为什么按块而不是一整段纯文本：表格压成纯文本后变成满屏 `|` 和 `---`，
    /// 完全读不了（2026-11-22 截图反馈）。所以保留「表格」这个结构，
    /// 但用一个**极简渲染器**（VStack + HStack + Text），不走 `Textual`。
    enum CompactBlock: Equatable {
        case text(String)
        case table(header: [String], rows: [[String]])
    }

    /// 精简模式：按块渲染（文本 + 极简表格），不解析完整 Markdown、不渲染图片。
    @ViewBuilder
    private var compactContent: some View {
        let blocks = Self.compactBlocks(message.text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    Text(text)
                        .font(.body)
                        .foregroundStyle(message.isUser ? .white : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .table(let header, let rows):
                    CompactTable(header: header, rows: rows,
                                 tint: message.isUser ? .white : .primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 解析成块：连续的表格行合成一个表格块，其余按段落合并成文本块。
    ///
    /// 只做「行级」判断，不解析语法树——这是精简模式省成本的关键。
    static func compactBlocks(_ raw: String) -> [CompactBlock] {
        var blocks: [CompactBlock] = []
        var textLines: [String] = []
        var tableLines: [[String]] = []
        var inCode = false

        func flushText() {
            guard !textLines.isEmpty else { return }
            let text = flatten(textLines)
            if !text.isEmpty { blocks.append(.text(text)) }
            textLines.removeAll()
        }
        func flushTable() {
            guard !tableLines.isEmpty else { return }
            let header = tableLines.first ?? []
            let rows = Array(tableLines.dropFirst())
            if !header.isEmpty { blocks.append(.table(header: header, rows: rows)) }
            tableLines.removeAll()
        }

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inCode.toggle(); continue }
            if inCode { continue }

            // 表格行：以 | 开头（或首尾都有 |）
            if trimmed.hasPrefix("|") || (trimmed.hasSuffix("|") && trimmed.contains("|")) {
                let cells = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // 分隔行（--- / :--:）不是数据
                if cells.allSatisfy({ $0.allSatisfy { ch in ch == "-" || ch == ":" } && !$0.isEmpty }) {
                    continue
                }
                flushText()
                tableLines.append(cells)
                continue
            }

            // 非表格行：结束当前表格
            flushTable()
            if trimmed.isEmpty { continue }
            var body = trimmed
            while body.hasPrefix("#") { body.removeFirst() }
            while body.hasPrefix(">") { body.removeFirst() }
            body = body.trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("- ") || body.hasPrefix("* ") || body.hasPrefix("+ ") {
                body = "· " + String(body.dropFirst(2))
            }
            textLines.append(body)
        }
        flushTable()
        flushText()
        return blocks
    }

    /// 把多行合并成一段，去掉最常见的行内记号。
    private static func flatten(_ lines: [String]) -> String {
        var text = lines.joined(separator: " ")
        for token in ["**", "__", "`", "~~"] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 把 Markdown 压成适合「一行行读」的纯文本。
    ///
    /// 只处理**最常见**的记号（粗体、行内代码、标题、引用、列表）。
    /// 不走完整 Markdown 解析：那是我们要省掉的开销，精简模式的意义就在这里。
    static func plainPreview(_ raw: String) -> String {
        var inCode = false
        var kept: [String] = []
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inCode.toggle(); continue }
            if inCode { continue }
            if trimmed.isEmpty { continue }
            // 去掉行首结构记号：标题 #、引用 >、有序/无序列表
            var body = trimmed
            while body.hasPrefix("#") { body.removeFirst() }
            while body.hasPrefix(">") { body.removeFirst() }
            body = body.trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("- ") || body.hasPrefix("* ") || body.hasPrefix("+ ") {
                body = "· " + String(body.dropFirst(2))
            }
            kept.append(body)
        }
        var text = kept.joined(separator: " ")
        for token in ["**", "__", "`", "~~"] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var plainMarkdownContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(model.markdownSegments(message.text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let markdown):
                    MarkdownBody(text: markdown, foreground: message.isUser ? .white : .primary)
                .equatable()
                .layoutDebug("C4", text: LayoutDebug.font(.body))
                        .textSelection(.enabled)
                        // 绿色气泡里选区高亮默认取全局绿色 tint → 选中几乎看不出来。
                        // 保持同一绿色色系，用更浅的薄荷绿做选区高亮，和深绿气泡形成明暗对比；
                        // 助手气泡保持默认主题色。
                        .tint(message.isUser ? Color(red: 0.66, green: 0.95, blue: 0.84) : nil)
                case .image(let url, let caption):
                    RemoteMarkdownImage(url: url, caption: caption,
                                        allImageURLs: model.conversationMarkdownImageURLs)
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

    private func pendingStateColor(_ state: PendingSendState) -> Color {
        switch state {
        case .failed: return Color.red.opacity(0.85)
        case .queued: return Color.orange
        default: return Color.secondary
        }
    }

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            // 8 → 4：真机反馈消息头里图标之间偏散。
            HStack(spacing: 4) {
                if !message.isUser {
                    Image(systemName: "sparkle").foregroundStyle(PocketChrome.brandText)
                        .layoutDebug("C6", gap: "8pt", text: LayoutDebug.font(.caption2))
                }
                Text(message.isUser ? L10n.t("你") : "DSH").foregroundStyle(.secondary)
                    .layoutDebug("C7", text: LayoutDebug.font(.caption2))
                if !message.text.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.text
                        copyHapticTick &+= 1
                        AccessibilityAnnouncer.announce(L10n.t("已复制整条消息"))
                        withAnimation(PocketMotion.animation(.easeInOut(duration: 0.15))) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            withAnimation(PocketMotion.animation(.easeInOut(duration: 0.15))) { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.caption2.weight(.medium))
                            .layoutDebug("C8", text: "14pt 图标")
                            .foregroundStyle(copied ? PocketChrome.brandText : .secondary)
                            .frame(width: 14, height: 14)
                            .scaleEffect(copied ? 1.15 : 1)
                            .animation(PocketMotion.animation(.spring(response: 0.22, dampingFraction: 0.6)), value: copied)
                            // 图标本身 14pt，补到 44pt 的可点区域，手抖也能点中。
                            // 44 → 32：可点区仍然够（HIG 建议 44，但这里图标很小、
                            // 相邻按钮之间还有间距），视觉高度能明显收紧。
                            .frame(minWidth: 32, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t(copied ? "已复制" : "复制整条消息"))
                    .sensoryFeedback(.success, trigger: copyHapticTick)
                    Button {
                        model.beginQuote(message)
                    } label: {
                        Image(systemName: "quote.bubble")
                            .font(.caption2.weight(.medium))
                            .layoutDebug("C9", text: "14pt 图标")
                            .foregroundStyle(.secondary)
                            // 44 → 32：可点区仍然够（HIG 建议 44，但这里图标很小、
                            // 相邻按钮之间还有间距），视觉高度能明显收紧。
                            .frame(minWidth: 32, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("引用这条消息"))
                }
            }
            .font(.caption2.weight(.semibold))
            .layoutDebug("C2", gap: "8pt", text: LayoutDebug.font(.caption2))
            HStack {
                if message.isUser { Spacer(minLength: 44) }
                VStack(alignment: .leading, spacing: 8) {
                    if message.isUser, hasUserImages {
                        // 用户发送的图片：作为小缩略图放在气泡内的左下角。
                        VStack(alignment: .leading, spacing: 8) {
                            if !message.text.isEmpty { markdownContent }
                            userImageThumbnails
                                .layoutDebug("C5")
                        }
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Color(red: 0.08, green: 0.48, blue: 0.37),
                                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .layoutDebug("C3", text: LayoutDebug.font(.body))
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
                                    .layoutDebug("C5")
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
                        Text(L10n.t("等待联网后一并发送"))
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


/// 精简模式下的极简表格：等宽字体 + 细边框，纯 Text 拼装。
///
/// 刻意不依赖 `Textual`：历史消息只需要「看清表格内容」，
/// 不需要富文本排版、也不需要它的解析开销（这是精简模式存在的理由）。
private struct CompactTable: View {
    let header: [String]
    let rows: [[String]]
    var tint: Color

    /// 列数取所有行里最宽的那行，避免缺格导致错位。
    private var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !header.isEmpty {
                row(cells: header, isHeader: true)
                Divider().opacity(0.35)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                row(cells: cells, isHeader: false)
                if index < rows.count - 1 {
                    Divider().opacity(0.15)
                }
            }
        }
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func row(cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { index in
                Text(index < cells.count ? cells[index] : "")
                    .font(.footnote)
                    .fontWeight(isHeader ? .semibold : .regular)
                    .foregroundStyle(isHeader ? tint : tint.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
    }
}
