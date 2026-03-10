// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Embeddings",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../")],
    targets: [
        .executableTarget(
            name: "Embeddings",
            dependencies: [.product(name: "AI", package: "swift-ai-sdk")]
        )
    ]
)
