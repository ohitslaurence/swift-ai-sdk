// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BasicCompletion",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "BasicCompletion",
            dependencies: [
                .product(name: "AI", package: "swift-ai-sdk")
            ]
        )
    ]
)
