// UserQuestionCard

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


/// 一步或一轮的工具过程，折叠成一行，展开看细节和图片。
/// 电脑端 `ask_user_question` 等待选择时显示的问题卡片。
struct UserQuestionCard: View {
    let request: PendingUserQuestion
    @Bindable var model: ConnectionModel
    @State private var selected: [String: Set<String>] = [:]
    @State private var custom: [String: String] = [:]

    private var complete: Bool {
        request.questions.allSatisfy { question in
            if !(selected[question.id]?.isEmpty ?? true) { return true }
            return !(custom[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(.orange)
                Text(L10n.t("需要你确认")).font(.footnote.weight(.semibold))
                Spacer()
                Text(L10n.t("来自电脑端 DSH")).font(.caption2).foregroundStyle(.secondary)
            }

            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 6) {
                    if let header = question.header, !header.isEmpty {
                        Text(header).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(question.question).font(.subheadline.weight(.medium))
                    if let detail = question.detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(question.options) { option in
                        Button { toggle(question, option) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: isSelected(question, option) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected(question, option) ? Color.green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label).font(.footnote)
                                    if let description = option.description, !description.isEmpty {
                                        Text(description).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .background(isSelected(question, option) ? Color.green.opacity(0.08) : Color(uiColor: .tertiarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    TextField(L10n.t("其他答案（可选）"), text: Binding(
                        get: { custom[question.id] ?? "" },
                        set: { custom[question.id] = $0 }
                    ))
                    .font(.footnote)
                    .textFieldStyle(.roundedBorder)
                }
            }

            Button {
                model.answerQuestion(request, selected: selected, custom: custom)
            } label: {
                Text(L10n.t("提交回答"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.08, green: 0.48, blue: 0.37).opacity(complete ? 1 : 0.35),
                                in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!complete)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func isSelected(_ question: PendingUserQuestion.Item, _ option: PendingUserQuestion.Option) -> Bool {
        selected[question.id]?.contains(option.label) ?? false
    }

    private func toggle(_ question: PendingUserQuestion.Item, _ option: PendingUserQuestion.Option) {
        var set = selected[question.id] ?? []
        if question.multiSelect {
            if set.contains(option.label) { set.remove(option.label) } else { set.insert(option.label) }
        } else {
            set = [option.label]
            custom[question.id] = ""
        }
        selected[question.id] = set
    }
}
