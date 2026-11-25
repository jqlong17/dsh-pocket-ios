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


    /// 勾选框列宽：主机行与地址子行共用同一列，保证左侧边缘对齐。
    private var hostCheckColumn: CGFloat { 26 }

    /// 一条地址：勾选框 + 连接方式 + 地址。
    ///
    /// 以前这里放的是「用这条」文字按钮，用户以为只是一行说明（2026-11-25 反馈）。
    /// 改成勾选框：**当前这条打勾，其余是空框**，整行可点即可切换，不再需要文字提示。
    @ViewBuilder
    func addressSubRow(_ endpoint: SavedEndpoint, isActive: Bool) -> some View {
        Button {
            guard !isActive else { return }
            Task { await model.switchToEndpoint(endpoint) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: hostCheckColumn, alignment: .center)
                Text(endpoint.kind.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .leading)
                Text(endpoint.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .contextMenu {
            Button(role: .destructive) {
                model.removeEndpoint(endpoint.address)
            } label: {
                Label(L10n.t("删除这条地址"), systemImage: "trash")
            }
        }
    }

    /// 主机一行：勾选框 + 名字 + 地址数 + 当前用的那条地址。
    ///
    /// 交互约定：整行（勾选框 + 文案 + 右侧状态）都可点即切换；左滑可删除/重命名。
    /// 当前主机的地址子行铺在下面，**与主机名左对齐**（缩进一列勾选框的宽度）。
    @ViewBuilder
    func hostRow(_ host: DSHHost) -> some View {
        let isCurrent = host.id == model.connectedHost?.id
        VStack(alignment: .leading, spacing: 2) {
            Button {
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
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isCurrent ? "checkmark.square.fill" : "square")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(width: hostCheckColumn, alignment: .center)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(host.name).font(.body.weight(.medium))
                            if host.endpoints.count > 1 {
                                Text(L10n.tf("%d 条地址", host.endpoints.count))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let endpoint = host.preferredEndpoint {
                            Text("\(endpoint.address) · \(endpoint.kind.label)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 6)
                    if switchingTo == host.id {
                        ProgressView().controlSize(.small)
                    } else if isCurrent {
                        Text(model.connection.isConnected ? L10n.t("已连接") : L10n.t("未连接"))
                            .font(.caption)
                            .foregroundStyle(model.connection.isConnected ? Color.accentColor : Color.secondary)
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    model.removeHost(id: host.id)
                } label: {
                    Label(L10n.t("删除"), systemImage: "trash")
                }
                Button {
                    renamingHostId = host.id
                    renameHostText = host.name
                } label: {
                    Label(L10n.t("重命名"), systemImage: "pencil")
                }
                .tint(.blue)
            }

            // 当前主机的地址铺在它下面，缩进一列勾选框：左边缘与主机名对齐。
            if isCurrent, host.endpoints.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(host.endpoints) { endpoint in
                        addressSubRow(endpoint, isActive: endpoint.address == model.connection.serverAddress)
                            .padding(.leading, hostCheckColumn + 10)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }
}
