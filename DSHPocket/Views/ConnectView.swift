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
    @State private var showingScanner = false
    @State private var showingPin = false
    @State private var renamingEndpoint: SavedEndpoint?
    @State private var renameText = ""
    @State private var deletingEndpoint: SavedEndpoint?
    @State private var scanHint: String?

    /// 产品使用说明（飞书文档，已设置"获得链接的人可阅读"）。
    private static let usageDocURL = URL(string: "https://my.feishu.cn/docx/XyhpdKD2Uo5y1ZxXFbscTpizntc")!

    private var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    private var pageBackground: Color { Color(uiColor: .systemGroupedBackground) }
    private var brand: Color { Color(red: 0.08, green: 0.48, blue: 0.37) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                if let error = model.errorMessage { errorBanner(error) }
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
                        if !model.pin.isEmpty || model.pendingPairToken != nil || model.pendingLoginToken != nil {
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
        .onAppear { model.errorMessage = nil }
        .onChange(of: model.serverAddress) { _, _ in model.errorMessage = nil }
        .alert(L10n.t("命名连接地址"), isPresented: Binding(
            get: { renamingEndpoint != nil },
            set: { if !$0 { renamingEndpoint = nil } }
        )) {
            TextField("例如：公司 / 家", text: $renameText)
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

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(brand)
                .frame(width: 38, height: 38)
                .background(brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("连接你的 DSH")).font(.headline)
            }
            Spacer(minLength: 8)
            Link(destination: Self.usageDocURL) {
                HStack(spacing: 4) {
                    Image(systemName: "book").font(.caption)
                    Text(L10n.t("使用说明")).font(.footnote.weight(.medium))
                }
                .foregroundStyle(brand)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel(L10n.t("打开 DSH Pocket iOS 使用说明"))
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 12))
    }

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
                    model.serverAddress = endpoint.address
                    model.errorMessage = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: endpoint.kind == .lan ? "wifi" : "globe")
                            .font(.system(size: 15, weight: .medium))
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
                        .accessibilityLabel("重命名\(endpoint.kind.label)地址")
                        if model.serverAddress == endpoint.address {
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
    private var scanConnectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(brand)
                Text(L10n.t("扫码连接电脑"))
                    .font(.headline)
                Spacer()
                Text(L10n.t("推荐"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(brand.opacity(0.12), in: Capsule())
                    .foregroundStyle(brand)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("准备（二选一）"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                prereqRow(
                    icon: "network",
                    title: L10n.t("方式一（推荐）：Tailscale"),
                    detail: L10n.t("电脑装 Tailscale + dsh-pocket-ios 连接器，手机装 Tailscale 和本 App；扫码即连，地址固定")
                )
                prereqRow(
                    icon: "puzzlepiece.extension",
                    title: L10n.t("方式二：dsh-pocket"),
                    detail: L10n.t("电脑装 dsh-pocket 插件（可选再加 dsh-pocket-ios 连接器）；扫它的局域网/公网二维码后输入访问密码")
                )
                Divider().padding(.vertical, 2)
                Text(L10n.t("然后"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                guideStep("1", L10n.t("按你选的路线装好对应插件（方式一：dsh-pocket-ios；方式二：dsh-pocket）"))
                guideStep("2", L10n.t("打开电脑 DSH → 设置 → 手机访问"))
                guideStep("3", L10n.t("扫码：方式一自动连接；方式二输入访问密码"))
            }
            Button {
                showingScanner = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text(L10n.t("扫一扫，连接电脑"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(.white)
                .background(brand, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scan-connect-button")
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func prereqRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(brand)
                .frame(width: 22, height: 22)
                .background(brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func guideStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(brand, in: Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var manualSectionTitle: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            Text(L10n.t("或手动连接（输入地址与密码）"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
        }
        .padding(.top, 4)
    }

    private var inputCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("http://192.168.1.10:3081", text: $model.serverAddress)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .font(.subheadline)
                Button { showingScanner = true } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(brand)
                        .frame(width: 34, height: 34)
                        .background(brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("扫描 Pocket 二维码")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().padding(.leading, 14)

            HStack(spacing: 8) {
                Group {
                    if showingPin {
                        TextField(L10n.t("访问密码（扫码连接可跳过）"), text: $model.pin)
                    } else {
                        SecureField(L10n.t("访问密码（扫码连接可跳过）"), text: $model.pin)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                Button {
                    if let pasted = UIPasteboard.general.string {
                        model.pin = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 15, weight: .medium))
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
                        .font(.system(size: 15, weight: .medium))
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
                Image(systemName: model.addressNeedsRescan ? "qrcode.viewfinder" : "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.addressNeedsRescan {
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
                .disabled(model.isConnecting)
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
                if model.isConnecting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                }
                Text(model.isConnecting ? L10n.t("正在连接") : L10n.t("连接"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.white)
            .background(brand, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(model.isConnecting)
        .opacity(model.isConnecting ? 0.7 : 1)
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
        .accessibilityHint("没有电脑时查看内置示例会话与对话")
    }
}
