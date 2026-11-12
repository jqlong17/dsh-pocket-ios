// ConnectHeaderCard

import SwiftUI

/// 连接页顶部的标题卡：图标、标题、使用说明链接。
///
/// 单独成文件是为了让 ConnectView 回到 400 行以内（架构规范阈值），
/// 内容仍是纯展示，只有「使用说明」链接一个外部依赖。
struct ConnectHeaderCard: View {
    /// 使用说明文档地址。
    static let usageDocURL = URL(string: "https://my.feishu.cn/docx/XyhpdKD2Uo5y1ZxXFbscTpizntc")!

    private var brand: Color { Color(red: 0.08, green: 0.48, blue: 0.37) }
    private var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title3.weight(.medium))
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
}
