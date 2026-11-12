import Foundation

/// 图片字节来源。把「怎么拿到原始字节」与「拿到之后怎么缓存/降采样」分开。
///
/// 为什么需要这层：附件图片走 `session/attachment` RPC（支持 maxPixel 尺寸协商），
/// Markdown 内嵌图走 HTTP（`api/file`）。两者取字节的方式不同，但之后的
/// 内存缓存、磁盘缓存、in-flight 去重、按目标尺寸降采样**完全一样**。
/// 没有这层时两条链路各写一份，结果就是「附件图点开清晰、Markdown 图点开糊」——
/// 因为其中一条忘了做 full 层。
public protocol ImageByteSource: Sendable {
    /// 缓存键。不同来源必须不同；同一来源的不同尺寸由调用方拼后缀。
    var cacheKey: String { get }

    /// 取原始字节。`maxPixel` 是给「支持尺寸协商的来源」的提示，
    /// 不支持（如普通 HTTP）的实现可以忽略它。
    func data(maxPixel: Int) async throws -> Data
}

public enum ImageSourceKey {
    /// 附件来源的键前缀。
    public static let attachmentPrefix = "att:"
    /// 远程 URL 来源的键前缀。
    public static let remotePrefix = "url:"

    public static func attachment(_ attachmentId: String) -> String {
        attachmentPrefix + attachmentId
    }

    public static func remote(_ url: URL) -> String {
        remotePrefix + url.absoluteString
    }
}
