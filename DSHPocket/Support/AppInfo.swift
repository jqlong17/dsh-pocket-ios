// AppInfo

import Foundation
import UIKit

/// 报告头部要用的 App 与设备信息（诊断报告、崩溃辅助、反馈都从这里取）。
enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// 机型标识（如 iPhone18,1）：从 uname 的 machine 取，
    /// `UIDevice.current.model` 只会返回「iPhone」，不够定位问题。
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        if machine.isEmpty { return UIDevice.current.model }
        // 模拟器上 uname 返回 arm64/x86_64，那不是机型标识，标清楚免得误判为真机。
        #if targetEnvironment(simulator)
        return "Simulator (\(machine))"
        #else
        return machine
        #endif
    }

    static var systemVersion: String {
        "iOS \(UIDevice.current.systemVersion)"
    }

    /// BCP 47 标识（如 zh-Hans-CN）。`Locale.current.identifier` 在部分系统上给
    /// `zh_CN` 这种旧格式，诊断报告里用规范形式更专业。
    static var localeIdentifier: String {
        let locale = Locale.current
        var parts: [String] = [locale.language.languageCode?.identifier ?? locale.identifier]
        if let script = locale.language.script?.identifier { parts.append(script) }
        if let region = locale.language.region?.identifier { parts.append(region) }
        return parts.joined(separator: "-")
    }
}
