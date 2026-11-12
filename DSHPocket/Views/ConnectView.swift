// ConnectView

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


struct ConnectView: View {
    @Bindable var model: ConnectionModel
    /// 状态对象单独持有：`@Bindable` 需要一个可写引用才能取 `$connection.pin` 这类绑定。
    /// 这正是 spec/13 批次 3 想要的方向——视图直接依赖所属场景的状态对象，而不是穿过模型转发。
    @Bindable var connection: ConnectionState
    @State private var showingScanner = false
    @State private var showingPin = false
    @State private var renamingEndpoint: SavedEndpoint?
    @State private var renameText = ""
    @State private var deletingEndpoint: SavedEndpoint?
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
                scanConnectCard
                manualSectionTitle
                inputCard
                connectButton
                if !model.savedEndpoints.isEmpty { savedEndpointsCard }
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
                            // 扫的是 dsh-pocket 的「地址型」二维码（方式二）：需要手动输入访问密码。
                            scanHint = L10n.t("已填入地址，请输入电脑上显示的访问密码（方式二）")
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
        .alert(L10n.t("命名连接地址"), isPresented: Binding(
            get: { renamingEndpoint != nil },
            set: { if !$0 { renamingEndpoint = nil } }
        )) {
            TextField(L10n.t("例如：公司 / 家"), text: $renameText)
            Button(L10n.t("保存")) {
                if let endpoint = renamingEndpoint {
                    model.renameEndpoint(endpoint.address, label: renameText)
                }
                renamingEndpoint = nil
            }
            Button(L10n.t("清除"), role: .destructive) {
                if let endpoint = renamingEndpoint {
                    model.renameEndpoint(endpoint.address, label: nil)
                }
                renamingEndpoint = nil
            }
            Button(L10n.t("取消"), role: .cancel) { renamingEndpoint = nil }
        } message: {
            Text(L10n.t("给这个地址起一个有辨识度的名字，例如「公司」或「家」。"))
        }
        .alert(L10n.t("删除连接？"), isPresented: Binding(
            get: { deletingEndpoint != nil },
            set: { if !$0 { deletingEndpoint = nil } }
        ), presenting: deletingEndpoint) { endpoint in
            Button(L10n.t("删除"), role: .destructive) {
                model.removeEndpoint(endpoint.address)
                deletingEndpoint = nil
            }
            Button(L10n.t("取消"), role: .cancel) { deletingEndpoint = nil }
        } message: { endpoint in
            Text("\(endpoint.displayName)：\(endpoint.address)")
        }
    }

    /// 标题卡已拆到 ConnectHeaderCard.swift。
    private var header: some View { ConnectHeaderCard() }

    private var savedEndpointsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("已保存的连接"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.t("点按切换"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(Array(model.savedEndpoints.enumerated()), id: \.element.id) { index, endpoint in
                if index > 0 {
                    Divider().padding(.leading, 52)
                }
                Button {
                    connection.serverAddress = endpoint.address
                    connection.errorMessage = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: endpoint.kind == .lan ? "wifi" : "globe")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(brand)
                            .frame(width: 26, height: 26)
                            .background(brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                if endpoint.label != nil {
                                    Text(endpoint.displayName)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(endpoint.kind.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(endpoint.kind.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(endpoint.address)
                                .font(.footnote)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Button {
                            renamingEndpoint = endpoint
                            renameText = endpoint.label ?? ""
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        Button {
                            deletingEndpoint = endpoint
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("删除连接"))
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("重命名\(endpoint.kind.label)地址"))
                        if connection.serverAddress == endpoint.address {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(brand)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(L10n.t("局域网最多保留 3 个（可命名为「公司」「家」），公网保留最近 1 个；公网地址变化后重新扫码更新。"))
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
                            .accessibilityLabel(L10n.t("访问密码"))
                            .accessibilityHint(L10n.t("8 到 64 位英文字母或数字，在电脑的「手机访问」页上"))
                    } else {
                        SecureField(L10n.t("访问密码（扫码连接可跳过）"), text: $connection.pin)
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
