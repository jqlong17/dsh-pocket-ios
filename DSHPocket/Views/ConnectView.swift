// ConnectView

import SwiftUI
import Security
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


struct ConnectView: View {
    @Bindable var model: ConnectionModel
    /// 状态对象单独持有：`@Bindable` 需要一个可写引用才能取 `$connection.pin` 这类绑定。
    /// 这正是 spec/13 批次 3 想要的方向——视图直接依赖所属场景的状态对象，而不是穿过模型转发。
    @Bindable var connection: ConnectionState
    @State private var showingScanner = false
    @State private var showingPin = false
    @State private var renamingHost: DSHHost?
    @State private var renameText = ""
    @State private var deletingHost: DSHHost?
    /// 正在切换的主机（行内显示「正在切换…」）。
    @State private var switchingHostId: String?
    /// 待确认删除的单条地址（与设置页行为一致）。
    @State private var pendingEndpointDelete: SavedEndpoint?
    @State private var scanHint: String?


    private var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    private var pageBackground: Color { Color(uiColor: .systemGroupedBackground) }
    private var brand: Color { Color(red: 0.08, green: 0.48, blue: 0.37) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                if let error = connection.errorMessage { errorBanner(error) }
                if let hint = scanHint {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill").foregroundStyle(brand)
                        Text(hint).font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { scanHint = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                // 布局按「交互距离」排（2026-11-21 用户定的顺序）：
                // 1. 切换连接（主路径）
                // 2. 连接按钮——紧挨列表，一次点击就到；不用滚到底部找
                // 3. 扫码（低频，加新电脑时才用）
                // 4. 手动连接（更低频）折叠起来，默认不占首屏
                if model.hosts.isEmpty {
                    scanConnectCard
                    manualSectionTitle
                    inputCard
                    connectButton
                } else {
                    savedEndpointsCard
                    connectButton
                    scanConnectCard
                    manualConnectSection
                }
                demoButton
                Text(L10n.t("演示模式使用内置示例数据，不会连接或发送任何内容。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(pageBackground.ignoresSafeArea())
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                QRScannerView { value in
                    if model.useScannedAddress(value) {
                        showingScanner = false
                        // 配对码/认证 URL/PIN 任一命中都直接连接。
                        if !connection.pin.isEmpty || model.pendingPairToken != nil || model.pendingLoginToken != nil {
                            scanHint = nil
                            Task { await model.connect() }
                        } else {
                            // 扫的是「地址型」二维码（EasyTier 走 SOCKS5 时常见）：需要手动输入访问密码。
                            scanHint = L10n.t("已填入地址，请输入电脑上显示的访问密码")
                        }
                    }
                }
                    .navigationTitle(L10n.t("扫描二维码"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L10n.t("完成")) { showingScanner = false } } }
            }
        }
        .onAppear { connection.errorMessage = nil }
        .onChange(of: connection.serverAddress) { _, _ in connection.errorMessage = nil }
        .alert(L10n.t("命名这台主机"), isPresented: Binding(
            get: { renamingHost != nil },
            set: { if !$0 { renamingHost = nil } }
        )) {
            TextField(L10n.t("例如：Mac / 阿里云"), text: $renameText)
            Button(L10n.t("保存")) {
                if let host = renamingHost {
                    model.renameHost(id: host.id, name: renameText)
                }
                renamingHost = nil
            }
            Button(L10n.t("取消"), role: .cancel) { renamingHost = nil }
        } message: {
            Text(L10n.t("给这台机器起一个有辨识度的名字，例如「Mac」或「阿里云」。"))
        }
        .alert(L10n.t("删除这台主机？"), isPresented: Binding(
            get: { deletingHost != nil },
            set: { if !$0 { deletingHost = nil } }
        ), presenting: deletingHost) { host in
            Button(L10n.t("删除"), role: .destructive) {
                model.removeHost(id: host.id)
                deletingHost = nil
            }
            Button(L10n.t("取消"), role: .cancel) { deletingHost = nil }
        } message: { host in
            Text("\(host.name)：\(host.endpoints.count) 条地址")
        }
          .alert(L10n.t("删除这条地址？"), isPresented: Binding(
              get: { pendingEndpointDelete != nil },
              set: { if !$0 { pendingEndpointDelete = nil } }
          ), presenting: pendingEndpointDelete) { endpoint in
              Button(L10n.t("删除"), role: .destructive) {
                  model.removeEndpoint(endpoint.address)
                  pendingEndpointDelete = nil
              }
              Button(L10n.t("取消"), role: .cancel) { pendingEndpointDelete = nil }
          } message: { endpoint in
              Text(endpoint.address)
          }
          .alert(L10n.t("切换失败"), isPresented: Binding(
              get: { scanHint != nil },
              set: { if !$0 { scanHint = nil } }
          )) {
              Button(L10n.t("知道了"), role: .cancel) { scanHint = nil }
          } message: {
              Text(scanHint ?? "")
          }
    }

    /// 标题卡已拆到 ConnectHeaderCard.swift。
    /// 点一台主机即切换；失败必须明示，不静默回退（延用设置页的约定）。
    private func connect(to host: DSHHost) {
        guard host.id != model.connectedHost?.id, switchingHostId == nil else { return }
        switchingHostId = host.id
        Task {
            let ok = await model.switchHost(to: host.id)
            switchingHostId = nil
            if !ok {
                scanHint = L10n.t("连不上 ") + host.name
                    + L10n.t("，已保持原连接不变。检查那台机器的 DSH 是否在运行。")
            }
        }
    }

    private var header: some View { ConnectHeaderCard() }

      private var savedEndpointsCard: some View {
          VStack(spacing: 0) {
              HStack {
                  Text(L10n.t("已保存的主机"))
                      .font(.footnote.weight(.semibold))
                      .foregroundStyle(.secondary)
                  Spacer()
                  Text(L10n.t("点按连接"))
                      .font(.caption2)
                      .foregroundStyle(.secondary)
              }
              .padding(.horizontal, 14)
              .padding(.top, 12)
              .padding(.bottom, 6)

            // 与设置页共用 HostRowView：同一个东西只有一种长相。
            // 连接页不是 List，所以不带左滑动作，改用行内按钮。
            ForEach(Array(model.hosts.enumerated()), id: \.element.id) { index, host in
                if index > 0 {
                    Divider().padding(.leading, 52)
                }
                HostRowView(
                    model: model,
                    host: host,
                    isCurrent: host.id == model.connectedHost?.id,
                    isSwitching: host.id == switchingHostId,
                    showsAddresses: host.id == model.connectedHost?.id,
                    onTap: { connect(to: host) },
                    onRename: {
                        renamingHost = host
                        renameText = host.name
                    },
                    onDeleteHost: { deletingHost = host },
                    onDeleteEndpoint: { endpoint in pendingEndpointDelete = endpoint },
                    onSelectEndpoint: { endpoint in
                        Task { await model.switchToEndpoint(endpoint) }
                    }
                )
                .padding(.horizontal, 14)
            }

              Text(L10n.t("一台机器的多个地址会自动挑最优（局域网优先）。扫码可新增主机。"))
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 14)
                  .padding(.top, 6)
                  .padding(.bottom, 12)
          }
          .background(card, in: RoundedRectangle(cornerRadius: 12))
      }


    /// 扫码连接（主入口）：三步引导 + 大按钮。
    /// 扫码卡已拆到 ConnectScanCard.swift（纯展示，便于改文案时不必读整页）。
    private var scanConnectCard: some View {
        ConnectScanCard(showingScanner: $showingScanner)
    }

    private var manualSectionTitle: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            Text(L10n.t("或手动连接（输入地址与密码）"))
                .font(.caption)
                .foregroundStyle(.secondary)
                // 大字号时要能换行，不能横向 fixedSize 把它截断。
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
        }
        .padding(.top, 4)
    }

    private var inputCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("http://192.168.1.10:3081", text: $connection.serverAddress)
                    .accessibilityIdentifier("connect-address")
                    .accessibilityLabel(L10n.t("电脑地址"))
                    .accessibilityHint(L10n.t("粘贴 DSH「手机访问」页上的地址，或直接扫码"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .font(.subheadline)
                Button { showingScanner = true } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(brand)
                        .frame(width: 34, height: 34)
                        .background(brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("扫描 Pocket 二维码"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().padding(.leading, 14)

            HStack(spacing: 8) {
                Group {
                    if showingPin {
                        TextField(L10n.t("访问密码（扫码连接可跳过）"), text: $connection.pin)
                            .accessibilityIdentifier("connect-pin")
                            .accessibilityLabel(L10n.t("访问密码"))
                            .accessibilityHint(L10n.t("8 到 64 位英文字母或数字，在电脑的「手机访问」页上"))
                    } else {
                        SecureField(L10n.t("访问密码（扫码连接可跳过）"), text: $connection.pin)
                            .accessibilityIdentifier("connect-pin")
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                Button {
                    if let pasted = UIPasteboard.general.string {
                        connection.pin = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(brand)
                        .frame(width: 32, height: 32)
                        .background(brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("粘贴"))
                Button {
                    showingPin.toggle()
                } label: {
                    Image(systemName: showingPin ? "eye.slash" : "eye")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingPin ? L10n.t("隐藏") : L10n.t("显示"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(card, in: RoundedRectangle(cornerRadius: 12))
    }

    /// 连接失败的红字。
    /// 文案本身全部来自 `ConnectFailureMessage`（超时/断连、认证失效、地址无效各有各的说法），
    /// 这里不再写任何一句提示，只按分类结果给下一步入口：
    /// 地址失效/认证失效显示「重新扫码连接」，暂时性失败显示「重试」——用户一眼能看出该等还是该重新配对。
    private func errorBanner(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: connection.addressNeedsRescan ? "qrcode.viewfinder" : "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if connection.addressNeedsRescan {
                Button { showingScanner = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode.viewfinder")
                        Text(L10n.t("重新扫码连接"))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(brand)
                }
            } else {
                Button { Task { await model.connect() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text(L10n.t("重试"))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(brand)
                }
                .disabled(connection.isConnecting)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    /// 折叠的手动连接：有历史连接时，它是最低频的入口，默认收起。
    @State private var manualConnectExpanded = false

    @ViewBuilder
    private var manualConnectSection: some View {
        DisclosureGroup(isExpanded: $manualConnectExpanded) {
            VStack(spacing: 10) {
                inputCard
                connectButton
            }
            .padding(.top, 10)
        } label: {
            Text(L10n.t("手动输入地址"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var connectButton: some View {
        Button {
            Task { await model.connect() }
        } label: {
            HStack(spacing: 6) {
                if connection.isConnecting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                }
                Text(connection.isConnecting ? L10n.t("正在连接") : L10n.t("连接"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.white)
            .background(brand, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(connection.isConnecting)
        .opacity(connection.isConnecting ? 0.7 : 1)
    }

    private var demoButton: some View {
        Button { model.startDemoMode() } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.circle")
                Text(L10n.t("体验演示模式"))
            }
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(brand)
            .background(card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.t("没有电脑时查看内置示例会话与对话"))
    }
}
