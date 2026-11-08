// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DSHKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "DSHKit", targets: ["DSHKit"])
    ],
    targets: [
        .target(
            name: "DSHKit",
            path: "Sources/DSHKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DSHKitTests",
            dependencies: ["DSHKit"],
            path: "Tests/DSHKitTests",
            resources: [.process("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
