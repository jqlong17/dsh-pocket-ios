// ConversationMoreMenu

import SwiftUI

/// 对话页右上角「更多」菜单：复制会话地址/日志路径/诊断信息、选择模型。
///
/// 为什么单独成文件：这一块只依赖几个只读字符串、一个 sheet 开关和「已复制」提示，
/// 从 655 行的 ConversationView 里拆出来后，改菜单项不必读整套滚动逻辑。
struct ConversationMoreMenu: View {
    @Bindable var model: ConnectionModel
    @Binding var showingModelPicker: Bool
    /// 复制成功后把内容回传给父视图弹「已复制」。
    var onCopied: (String) -> Void

    var body: some View {
        Menu {
            Button {
                UIPasteboard.general.string = model.sessionAddress
                onCopied(model.sessionAddress)
            } label: {
                Label(L10n.t("复制会话地址"), systemImage: "link")
            }
            Button {
                if let path = model.sessionLogPath {
                    UIPasteboard.general.string = path
                    onCopied(path)
                }
            } label: {
                Label(L10n.t("复制会话日志路径"), systemImage: "doc.on.doc")
            }
            Divider()
            Button {
                showingModelPicker = true
            } label: {
                Label(model.selectedModelLabel.map { L10n.t("选择模型") + "：" + $0 } ?? L10n.t("选择模型"),
                      systemImage: "cpu")
            }
            Button {
                let report = model.diagnosticReport()
                UIPasteboard.general.string = report
                onCopied(report)
            } label: {
                Label(L10n.t("复制诊断信息"), systemImage: "stethoscope")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(L10n.t("更多"))
    }
}
