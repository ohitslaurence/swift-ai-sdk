// swift-tools-version: 6.0

import PackageDescription

var swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "swift-ai",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "AI", targets: ["AI"]),
        .library(name: "AICore", targets: ["AICore"]),
        .library(name: "AIProviderAnthropic", targets: ["AIProviderAnthropic"]),
        .library(name: "AIProviderOpenAI", targets: ["AIProviderOpenAI"]),
        .library(name: "AISwiftUI", targets: ["AISwiftUI"]),
    ],
    targets: [
        .target(
            name: "AI",
            dependencies: [
                "AICore",
                "AIProviderAnthropic",
                "AIProviderOpenAI",
                "AISwiftUI",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AICore",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AIProviderAnthropic",
            dependencies: ["AICore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AIProviderOpenAI",
            dependencies: ["AICore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AISwiftUI",
            dependencies: ["AICore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AITestSupport",
            dependencies: ["AICore"],
            path: "Tests/AITestSupport",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AICoreTests",
            dependencies: ["AICore", "AITestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AIProviderAnthropicTests",
            dependencies: ["AIProviderAnthropic", "AITestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AIProviderOpenAITests",
            dependencies: ["AIProviderOpenAI", "AITestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AISwiftUITests",
            dependencies: ["AISwiftUI", "AITestSupport"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "AIIntegrationTests",
            dependencies: ["AICore", "AIProviderOpenAI", "AIProviderAnthropic"],
            path: "Tools/AIIntegrationTests",
            swiftSettings: swiftSettings
        ),
    ]
)
