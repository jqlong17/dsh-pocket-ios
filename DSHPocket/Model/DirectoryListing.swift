// DirectoryListing

import Foundation

/// Mac 上的一个子目录（新建工作区时挑目录用）。
///
/// 由插件端点 `dir.list` 返回：只列目录、不列文件，避免把 Mac 上的文件名带到手机上。
struct DirectoryEntry: Identifiable, Hashable {
    let name: String
    let path: String
    var id: String { path }
}

/// 一次目录列举的结果。
struct DirectoryListing: Hashable {
    /// 当前目录的绝对路径（已 realpath，符号链接会被展开）。
    let path: String
    /// 上一级；到白名单根部时为 nil。
    let parent: String?
    let dirs: [DirectoryEntry]

    /// 面包屑：把 `/Users/ruska/projects/foo` 拆成可点的层级。
    var crumbs: [(name: String, path: String)] {
        var result: [(String, String)] = []
        var current = ""
        for part in path.split(separator: "/") {
            current += "/" + part
            result.append((String(part), current))
        }
        return result
    }
}
