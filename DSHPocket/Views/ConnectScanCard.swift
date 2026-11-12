// ConnectScanCard

import SwiftUI

/// 连接页的「扫码连接电脑」卡片：准备条件 + 三步引导 + 扫码按钮。
///
/// 为什么单独成文件：这一块是纯展示，只依赖品牌色与「扫码页是否展开」一个绑定，
/// 从 ConnectView（原本 505 行）里拆出来既能降行数，也让修改文案时不必读整页。
struct ConnectScanCard: View {
    @Binding var showingScanner: Bool

    private var brand: Color { Color(red: 0.08, green: 0.48, blue: 0.37) }
    private var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.headline.weight(.semibold))
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
                .font(.footnote.weight(.medium))
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
}
