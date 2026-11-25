// AppSettingsSheet+Connection

import SwiftUI
import DSHKit

/// 设置页里「主机 / 地址」相关的行视图。
///
/// 拆出来的原因：AppSettingsSheet 本身已经 690 行（app 阈值 600），
/// 而连接这块的视图与其它设置项（语言、工作区、调试）没有耦合，
/// 放在一起只会让「这一页有哪些设置」变得难读。
extension AppSettingsSheet {
    /// 当前主机（顶部那块用）。
    /// 当前连接的主机：**由实际地址反推**，不是「上次选中的主机」。
    /// 两者在回滚/兜底时会分叉，用它才能保证「界面显示的那台 == 会话列表那台」。
    var currentHost: DSHHost? {
        model.connectedHost
    }


    /// 主机一行：**与连接页共用 HostRowView**（结构一致，2026-11-25）。
    /// 设置页额外提供左滑动作（这里是 List，连接页不是）。
    @ViewBuilder
    func hostRow(_ host: DSHHost) -> some View {
        let isCurrent = host.id == model.connectedHost?.id
        HostRowView(
            model: model,
            host: host,
            isCurrent: isCurrent,
            isSwitching: switchingTo == host.id,
            showsAddresses: isCurrent,
            onTap: { switchTo(host) },
            onRename: {
                renamingHostId = host.id
                renameHostText = host.name
            },
            onDeleteHost: { pendingHostDelete = host },
            onDeleteEndpoint: { endpoint in pendingEndpointDelete = endpoint },
            onSelectEndpoint: { endpoint in
                Task { await model.switchToEndpoint(endpoint) }
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingHostDelete = host
            } label: {
                Label(L10n.t("删除整台"), systemImage: "trash")
            }
            Button {
                renamingHostId = host.id
                renameHostText = host.name
            } label: {
                Label(L10n.t("重命名"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    /// 点主机即切换；失败明示，不静默回退。
    private func switchTo(_ host: DSHHost) {
        guard host.id != model.currentHostId, switchingTo == nil else { return }
        switchingTo = host.id
        Task {
            let ok = await model.switchHost(to: host.id)
            switchingTo = nil
            if !ok {
                switchError = L10n.t("连不上 ") + host.name
                    + L10n.t("，已保持原连接不变。检查那台机器的 DSH 是否在运行。")
            }
        }
    }
}
