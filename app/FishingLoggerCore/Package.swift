// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FishingLoggerCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "FishingLoggerCore", targets: ["FishingLoggerCore"])
    ],
    targets: [
        .target(
            name: "FishingLoggerCore",
            dependencies: []
        ),
        .testTarget(
            name: "FishingLoggerCoreTests",
            dependencies: ["FishingLoggerCore"]
        )
    ]
)
