// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AgenticUsageMeter",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "UsageMeterCore", targets: ["UsageMeterCore"]),
        .executable(name: "UsageMeterProbe", targets: ["UsageMeterProbe"])
    ],
    targets: [
        .target(name: "UsageMeterCore"),
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
        )
    ],
    swiftLanguageModes: [.v6]
)
