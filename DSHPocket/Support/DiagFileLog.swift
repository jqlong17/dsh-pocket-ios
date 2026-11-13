// DiagFileLog

import Foundation

/// 写文件的诊断日志。
///
/// 为什么不用 `os.Logger`：unified log 在真机上要靠 `log stream --device` 才读得到，
/// 而 `devicectl device console` 只显示 stdout——排查时等于没打。
/// 这个实现把行追加到沙盒 Documents 下的固定文件，`devicectl device copy` 能直接拷出来。
enum DiagFileLog {
    private static let queue = DispatchQueue(label: "com.ruska.dsh-pocket-ios.diaglog", qos: .utility)
    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("diag.log")
    }
    /// 单文件上限，超过后截断重写（只在启动时清，避免频繁 IO）。
    private static let maxBytes = 512 * 1024

    static func reset() {
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func log(_ message: String) {
        let line = "\(Self.stamp()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            let manager = FileManager.default
            if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int,
               size > maxBytes {
                try? manager.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
