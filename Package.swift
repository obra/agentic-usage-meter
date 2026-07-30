// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AgenticUsageMeter",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "UsageMeterCore", targets: ["UsageMeterCore"])
    ],
    targets: [
        .target(name: "UsageMeterCore"),
        .testTarget(
            name: "UsageMeterCoreTests",
            dependencies: ["UsageMeterCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
