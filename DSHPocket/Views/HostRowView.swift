// HostRowView

import SwiftUI
import DSHKit

/// 主机行：**连接页与设置页共用同一个结构**（2026-11-25 用户反馈两页不一致）。
///
/// 之前两页各写一套：连接页是「图标 + 名字 + 地址 + 铅笔/垃圾桶」，设置页是
/// 「勾选框 + 名字 + 地址 + 状态」。同一个东西两种长相，用户要在两处学两遍。
/// 现在统一为：**勾选框 + 名字（+地址数）+ 最优地址 / 右侧状态 / 重命名 + 删除**，
/// 当前主机的地址铺在下面，每条地址单独删除。
///
/// 交互约定：
/// - 整行点按 = 切换（失败要明示，见调用方）
/// - 行内按钮（重命名/删除/删地址）用 `.borderless`，**外层不用 Button 包**——
///   SwiftUI 里按钮套按钮，内层永远收不到点击（实测点了没反应）。
struct HostRowView: View {
    @Bindable var model: ConnectionModel
    let host: DSHHost
    let isCurrent: Bool
    /// 正在切换到这台（显示转圈 + 文案）。
    let isSwitching: Bool
    /// 是否铺开地址子行（目前只给当前主机铺）。
    let showsAddresses: Bool
    var onTap: () -> Void
    var onRename: () -> Void
    var onDeleteHost: () -> Void
    var onDeleteEndpoint: (SavedEndpoint) -> Void
    var onSelectEndpoint: (SavedEndpoint) -> Void

    /// 勾选框列宽：主机行与地址子行共用，保证左边缘对齐。
    private let checkColumn: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            mainRow
            if showsAddresses, isCurrent, host.endpoints.count > 1 {
                ForEach(host.endpoints) { endpoint in
                    addressRow(endpoint, isActive: endpoint.address == model.connection.serverAddress)
                        .padding(.leading, checkColumn + 10)
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrent ? "checkmark.square.fill" : "square")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(width: checkColumn, alignment: .center)

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

            if isSwitching {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("正在切换…")).font(.caption).foregroundStyle(.secondary)
                }
            } else if isCurrent {
                Text(model.connection.isConnected ? L10n.t("已连接") : L10n.t("未连接"))
                    .font(.caption)
                    .foregroundStyle(model.connection.isConnected ? Color.accentColor : Color.secondary)
            }

            Button(action: onRename) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.t("重命名这台主机"))
            .accessibilityIdentifier("host-rename-\(host.name)")

            Button(action: onDeleteHost) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.t("删除这台主机"))
            .accessibilityIdentifier("host-delete-\(host.name)")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func addressRow(_ endpoint: SavedEndpoint, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.square.fill" : "square")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(width: checkColumn, alignment: .center)
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
            if !isActive {
                Button {
                    onDeleteEndpoint(endpoint)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.t("删除这条地址"))
                .accessibilityIdentifier("endpoint-delete-\(endpoint.address)")
            }
        }
        .frame(minHeight: 36)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isActive else { return }
            onSelectEndpoint(endpoint)
        }
        .contextMenu {
            Button(role: .destructive) {
                onDeleteEndpoint(endpoint)
            } label: {
                Label(L10n.t("删除这条地址"), systemImage: "trash")
            }
        }
    }
}
