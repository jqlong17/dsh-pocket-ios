import XCTest

/// 架构边界测试：把「纯逻辑层不得依赖 UI 框架」变成会随 `swift test` 永远生效的断言。
///
/// 为什么用测试而不是只靠 scripts/check-architecture.sh：
/// 脚本要有人记得跑；测试是 CI 与本地 `swift test` 的默认部分，跑不掉的。
final class ArchitectureBoundaryTests: XCTestCase {
    /// 纯逻辑层禁止导入的 UI 框架。
    private static let forbiddenImports = ["SwiftUI", "UIKit", "AppKit"]

    /// 扫描器：返回违反边界的文件与命中的框架。
    /// 抽成纯函数，这样「扫描器本身有没有扫到东西」也能被测（见下一个用例）。
    static func violations(in files: [URL]) -> [(file: String, framework: String)] {
        var result: [(String, String)] = []
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                let framework = trimmed.replacingOccurrences(of: "import ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if forbiddenImports.contains(framework) {
                    result.append((url.lastPathComponent, framework))
                }
            }
        }
        return result
    }

    func testPureLogicLayerHasNoUIImports() throws {
        let sources = Self.sourceFiles()
        XCTAssertFalse(sources.isEmpty, "没扫到任何源文件，说明路径推导错了")
        let found = Self.violations(in: sources)
        let detail = found.map { "\($0.file) → import \($0.framework)" }.joined(separator: "\n")
        XCTAssertTrue(found.isEmpty, "纯逻辑层出现 UI 依赖：\n\(detail)")
    }

    /// 自测：确保扫描器真的能抓到违规，否则上面那条可能因为「永远扫空」而假绿。
    func testScannerDetectsViolation() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("arch-boundary-\(UUID().uuidString).swift")
        try "import SwiftUI\nstruct X {}\n".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let found = Self.violations(in: [tmp])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.framework, "SwiftUI")
    }

    /// Sources 目录推导：从测试文件路径回溯到包根，避免依赖运行目录。
    static func sourceFiles() -> [URL] {
        let testFile = URL(fileURLWithPath: #filePath)          // <包根>/Tests/DSHKitTests/本文件
        let packageRoot = testFile
            .deletingLastPathComponent()                        // DSHKitTests
            .deletingLastPathComponent()                        // Tests
            .deletingLastPathComponent()                        // <包根>
        let sources = packageRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(at: sources,
                                                             includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }
}
