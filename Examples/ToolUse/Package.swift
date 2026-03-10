// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ToolUse",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../")],
    targets: [
        .executableTarget(
            name: "ToolUse",
            dependencies: [.product(name: "AI", package: "swift-ai-sdk")]
        )
    ]
)
