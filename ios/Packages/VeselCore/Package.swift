// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VeselCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "VeselCore", targets: ["VeselCore"])
    ],
    targets: [
        .target(name: "VeselCore"),
        .testTarget(name: "VeselCoreTests", dependencies: ["VeselCore"]),
    ]
)
