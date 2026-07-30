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
        .library(name: "UsageMeterUI", targets: ["UsageMeterUI"]),
        .executable(name: "ClaudeWebProbe", targets: ["ClaudeWebProbe"]),
        .executable(name: "UsageMeterProbe", targets: ["UsageMeterProbe"])
    ],
    targets: [
        .target(name: "UsageMeterCore"),
        .target(
            name: "UsageMeterClaudeWeb",
            dependencies: ["UsageMeterCore"]
        ),
        .target(
            name: "UsageMeterUI",
            dependencies: ["UsageMeterCore"]
        ),
        .executableTarget(
            name: "ClaudeWebProbe",
            dependencies: ["UsageMeterCore", "UsageMeterClaudeWeb"]
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
        ),
        .testTarget(
            name: "ClaudeWebProbeTests",
            dependencies: ["ClaudeWebProbe", "UsageMeterCore"]
        ),
        .testTarget(
            name: "UsageMeterProbeTests",
            dependencies: ["UsageMeterProbe", "UsageMeterCore"]
        ),
        .testTarget(
            name: "UsageMeterUITests",
            dependencies: ["UsageMeterUI", "UsageMeterCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
