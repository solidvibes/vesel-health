// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VeselSync",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "VeselSync", targets: ["VeselSync"])
    ],
    dependencies: [
        .package(path: "../VeselCore"),
        .package(path: "../VeselStorage"),
    ],
    targets: [
        .target(name: "VeselSync", dependencies: ["VeselCore", "VeselStorage"]),
        .testTarget(
            name: "VeselSyncTests",
            dependencies: ["VeselSync", "VeselCore", "VeselStorage"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
