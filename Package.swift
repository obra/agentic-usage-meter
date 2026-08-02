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
        .executable(
            name: "AgenticUsageMeter",
            targets: ["AgenticUsageMeter"]
        ),
        .executable(name: "ClaudeWebProbe", targets: ["ClaudeWebProbe"]),
        .executable(name: "UsageMeterProbe", targets: ["UsageMeterProbe"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.4"
        )
    ],
    targets: [
        .target(name: "UsageMeterCore"),
        .target(name: "UsageMeterWeb"),
        .target(
            name: "UsageMeterClaudeWeb",
            dependencies: ["UsageMeterCore", "UsageMeterWeb"]
        ),
        .target(
            name: "UsageMeterUI",
            dependencies: [
                "UsageMeterCore",
                "UsageMeterClaudeWeb",
                "UsageMeterWeb",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "AgenticUsageMeter",
            dependencies: ["UsageMeterCore", "UsageMeterUI"]
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
            dependencies: [
                "AgenticUsageMeter",
                "UsageMeterUI",
                "UsageMeterCore"
            ]
        ),
        .testTarget(
            name: "UsageMeterWebTests",
            dependencies: ["UsageMeterWeb"]
        )
    ],
    swiftLanguageModes: [.v6]
)
