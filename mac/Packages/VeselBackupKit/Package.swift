// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VeselBackupKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "VeselBackupKit", targets: ["VeselBackupKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(
            name: "VeselBackupKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "VeselBackupKitTests", dependencies: ["VeselBackupKit"]),
    ]
)
