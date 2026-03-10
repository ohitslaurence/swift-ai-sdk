// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StructuredOutput",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../")],
    targets: [
        .executableTarget(
            name: "StructuredOutput",
            dependencies: [.product(name: "AI", package: "swift-ai-sdk")]
        )
    ]
)
