// 图片来源实现

import Foundation
import DSHKit

/// 附件来源：走 `session/attachment` RPC，支持服务端按 `maxPixel` 协商尺寸。
///
/// 与 `RemoteURLByteSource` 的区别只在这里——拿到字节之后的缓存、降采样、
/// 分层（thumbnail / full）完全共用 `ImagePipeline`。
struct AttachmentByteSource: ImageByteSource {
    let attachmentId: String
    let sessionId: String
    let requestJSON: [String: Any]
    /// 附件字节大小（用于判断是否懒加载高清）；0 表示未知。
    let knownBytes: Int
    /// RPC 客户端。用闭包而不是具体类型，避免让协议依赖 DSHClient。
    let rpc: @Sendable (String, [String: Any]) async throws -> [String: Any]

    var cacheKey: String { ImageSourceKey.attachment(attachmentId) }

    func data(maxPixel: Int) async throws -> Data {
        let payload = ImageFetchPolicy.requestArgs(sessionId: sessionId,
                                                  attachment: requestJSON,
                                                  maxPixel: maxPixel)
        let value = try await rpc("session/attachment", ["request": payload])
        guard let base64 = value["data"] as? String,
              let data = Data(base64Encoded: base64) else {
            throw ImageSourceError.empty
        }
        return data
    }
}

/// 远程 URL 来源：Markdown 内嵌图、以及任何 HTTP 图片。
///
/// `maxPixel` 会被忽略——服务端不支持尺寸协商，拿到什么就是什么；
/// 缩放发生在客户端解码阶段（`ImageMemory.thumbnail` 的 maxPixelSize）。
struct RemoteURLByteSource: ImageByteSource {
    let url: URL

    var cacheKey: String { ImageSourceKey.remote(url) }

    func data(maxPixel: Int) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImageSourceError.badStatus(http.statusCode)
        }
        return data
    }
}

enum ImageSourceError: Error, Equatable {
    case empty
    case badStatus(Int)
}
