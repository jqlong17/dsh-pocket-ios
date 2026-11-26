// DirectoryError

import Foundation

/// 目录浏览/添加工作区的错误：只带一句人话，界面直接显示。
struct DirectoryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
