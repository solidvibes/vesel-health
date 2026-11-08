// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VeselStorage",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "VeselStorage", targets: ["VeselStorage"])
    ],
    dependencies: [
        .package(path: "../VeselCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0"),
    ],
    targets: [
        .target(
            name: "VeselStorage",
            dependencies: [
                "VeselCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "VeselStorageTests", dependencies: ["VeselStorage"]),
    ]
)
