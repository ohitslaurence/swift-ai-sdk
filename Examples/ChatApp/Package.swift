// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChatApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "ChatApp",
            dependencies: [
                .product(name: "AI", package: "swift-ai-sdk")
            ]
        )
    ]
)
