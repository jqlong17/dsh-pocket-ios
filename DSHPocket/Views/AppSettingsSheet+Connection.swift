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


    /// 当前主机下的一条地址：类型 + 地址；正在用的标「使用中」，其余可点或删。
    ///
    /// 不用左滑：这些是嵌套在主机行里的子行，滑动容易和父行冲突，
    /// 所以删除给一个明确的小按钮。
    @ViewBuilder
    func addressSubRow(_ endpoint: SavedEndpoint, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Text(endpoint.kind.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(endpoint.address)
                .font(.caption.monospaced())
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isActive {
                Text(L10n.t("使用中"))
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            } else {
                Button {
                    Task { await model.switchToEndpoint(endpoint) }
                } label: {
                    Text(L10n.t("用这条")).font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                model.removeEndpoint(endpoint.address)
            } label: {
                Label(L10n.t("删除这条地址"), systemImage: "trash")
            }
        }
    }

    /// 主机一行：名字 + 地址数 + 当前用的那条地址。
    @ViewBuilder
    func hostRow(_ host: DSHHost) -> some View {
        let isCurrent = host.id == model.connectedHost?.id
        // 外层 VStack：主行(可点/可滑) + 当前主机的地址子行。
        // 之前把 if 直接插在 HStack 的修饰符链中间，导致 contentShape 无处可挂。
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(host.name).font(.body.weight(.medium))
                        if host.endpoints.count > 1 {
                            Text(L10n.tf("%d 条地址", host.endpoints.count))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let endpoint = host.preferredEndpoint {
                        // 地址 + 连接方式：用户问「现在走的是哪种」时，答案就在这一行。
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
                    if model.connection.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(L10n.t("当前连接的机器"))
                    }
                    Text(model.connection.isConnected ? L10n.t("已连接") : L10n.t("未连接"))
                        .font(.caption)
                        .foregroundStyle(model.connection.isConnected ? Color.accentColor : Color.secondary)
                }
            }
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

            // 当前主机的地址铺在它下面：只有「现在这台怎么连」需要看到多条，
            // 别的机器不展开，否则列表立刻变长一倍。
            if isCurrent, host.endpoints.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(host.endpoints) { endpoint in
                        addressSubRow(endpoint, isActive: endpoint.address == model.connection.serverAddress)
                            .padding(.leading, 38)
                    }
                }
            }
        }
          // 整块可点可滑：以前 contentShape 只盖住上半行，点地址行没反应，
          // 用户反馈「切换区域太小」（2026-11-25）。46pt 满足 HIG 最小点按尺寸。
          .frame(minHeight: 46, alignment: .leading)
          .contentShape(Rectangle())
          .onTapGesture {
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
}
