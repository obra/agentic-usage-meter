// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AgenticUsageMeter",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "UsageMeterCore", targets: ["UsageMeterCore"]),
        .library(name: "UsageMeterClaudeWeb", targets: ["UsageMeterClaudeWeb"]),
        .executable(name: "UsageMeterProbe", targets: ["UsageMeterProbe"])
    ],
    targets: [
        .target(name: "UsageMeterCore"),
        .target(
            name: "UsageMeterClaudeWeb",
            dependencies: ["UsageMeterCore"]
        ),
        .executableTarget(
            name: "UsageMeterProbe",
            dependencies: ["UsageMeterCore"]
        ),
        .testTarget(
            name: "UsageMeterCoreTests",
            dependencies: ["UsageMeterCore"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "UsageMeterClaudeWebTests",
            dependencies: ["UsageMeterClaudeWeb", "UsageMeterCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
