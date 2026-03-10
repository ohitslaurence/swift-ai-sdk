// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StreamingChat",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../")],
    targets: [
        .executableTarget(
            name: "StreamingChat",
            dependencies: [.product(name: "AI", package: "swift-ai-sdk")]
        )
    ]
)
