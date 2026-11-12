// DraftImageStore

import SwiftUI
import DSHKit

/// 草稿里的图片也落盘：App 被杀或崩溃后，配好的图还能回来。
///
/// 目录：Application Support/dsh-pocket/drafts/<sessionId>/
/// 和发件箱分开，互不影响；发送成功、清空草稿、删除会话时整目录删除。
enum DraftImageStore {
    private static let metaName = "draft.json"

    private static var root: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dsh-pocket/drafts", isDirectory: true)
    }

    private static func directory(for sessionId: String) -> URL? {
        root?.appendingPathComponent(sessionId, isDirectory: true)
    }

    private struct Meta: Codable {
        let fileName: String
        let mediaType: String
        let name: String
    }

    /// 整份覆盖保存：草稿图数量很少，简单直接。
    static func save(_ images: [PocketDraftImage], sessionId: String) {
        guard let dir = directory(for: sessionId) else { return }
        if images.isEmpty {
            try? FileManager.default.removeItem(at: dir)
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var metas: [Meta] = []
        for (index, image) in images.enumerated() {
            let ext = image.mediaType.contains("png") ? "png" : "jpg"
            let fileName = "draft-\(index).\(ext)"
            guard (try? image.data.write(to: dir.appendingPathComponent(fileName), options: .atomic)) != nil else { continue }
            metas.append(Meta(fileName: fileName, mediaType: image.mediaType, name: image.name))
        }
        if let data = try? JSONEncoder().encode(metas) {
            try? data.write(to: dir.appendingPathComponent(metaName), options: .atomic)
        }
    }

    /// 进入会话时恢复草稿图。
    static func load(sessionId: String) -> [PocketDraftImage] {
        guard let dir = directory(for: sessionId),
              let data = try? Data(contentsOf: dir.appendingPathComponent(metaName)),
              let metas = try? JSONDecoder().decode([Meta].self, from: data) else { return [] }
        return metas.compactMap { meta in
            guard let raw = try? Data(contentsOf: dir.appendingPathComponent(meta.fileName)),
                  let ui = UIImage(data: raw) else { return nil }
            return PocketDraftImage(data: raw, mediaType: meta.mediaType, name: meta.name, uiImage: ui)
        }
    }

    static func clear(sessionId: String) {
        guard let dir = directory(for: sessionId) else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
