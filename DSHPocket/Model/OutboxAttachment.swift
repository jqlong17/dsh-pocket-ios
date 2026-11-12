// OutboxAttachment

import Foundation

/// 发件箱里的一条附件记录：只存文件名和元数据，图片本体落在磁盘目录里。
struct OutboxAttachment: Codable, Equatable {
    let fileName: String
    let mediaType: String
    let name: String
    let bytes: Int
}

/// 发件箱附件的磁盘仓库。
///
/// 目录：Application Support/dsh-pocket/outbox/<rpcId>/<fileName>
/// 不进 Documents：那里会被 iCloud 备份，附件属于用户内容，不往外传。
enum OutboxImageStore {
    private static var root: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("dsh-pocket/outbox", isDirectory: true)
    }

    private static func directory(for rpcId: String) -> URL? {
        root?.appendingPathComponent(rpcId.lowercased(), isDirectory: true)
    }

    /// 把这条消息的图片落盘，返回可以写进 OutboxEntry 的记录。
    static func save(_ images: [PocketDraftImage], rpcId: String) -> [OutboxAttachment] {
        guard let dir = directory(for: rpcId) else { return [] }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var saved: [OutboxAttachment] = []
        for (index, image) in images.enumerated() {
            let ext = image.mediaType.contains("png") ? "png" : "jpg"
            let fileName = "image-\(index).\(ext)"
            let url = dir.appendingPathComponent(fileName)
            guard (try? image.data.write(to: url, options: .atomic)) != nil else { continue }
            saved.append(OutboxAttachment(fileName: fileName,
                                          mediaType: image.mediaType,
                                          name: image.name,
                                          bytes: image.data.count))
        }
        return saved
    }

    /// 读回附件本体，用于补发。
    static func load(_ attachments: [OutboxAttachment], rpcId: String) -> [(attachment: OutboxAttachment, data: Data)] {
        guard let dir = directory(for: rpcId) else { return [] }
        return attachments.compactMap { attachment in
            let url = dir.appendingPathComponent(attachment.fileName)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return (attachment, data)
        }
    }

    /// 服务端确认或用户取消后回收磁盘。
    static func delete(rpcId: String) {
        guard let dir = directory(for: rpcId) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// 发件箱当前附件总占用。
    static func totalBytes() -> Int {
        guard let root else { return 0 }
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                             includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += size
        }
        return total
    }
}
