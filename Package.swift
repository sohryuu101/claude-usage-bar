// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClaudeUsageCore", targets: ["ClaudeUsageCore"]),
        .executable(name: "ClaudeUsageBar", targets: ["ClaudeUsageBar"]),
        .executable(name: "claude-usage", targets: ["ClaudeUsageCLI"])
    ],
    targets: [
        .target(name: "ClaudeUsageCore"),
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["ClaudeUsageCore"]
        ),
        .executableTarget(
            name: "ClaudeUsageCLI",
            dependencies: ["ClaudeUsageCore"]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"]
        )
    ]
)
