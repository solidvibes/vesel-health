// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VeselWearable",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "VeselWearable", targets: ["VeselWearable"]),
        .library(name: "VeselWearableTesting", targets: ["VeselWearableTesting"]),
    ],
    dependencies: [
        .package(path: "../VeselCore"),
        .package(path: "../VeselStorage"),
        .package(url: "https://github.com/polarofficial/polar-ble-sdk.git", exact: "8.5.0"),
        // The SDK asks for these with `from:`; pinned here so the app builds with the tested versions.
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.39.0"),
        .package(url: "https://github.com/marmelroy/Zip.git", exact: "2.1.2"),
    ],
    targets: [
        .target(
            name: "VeselWearable",
            dependencies: [
                "VeselCore",
                "VeselStorage",
                .product(name: "PolarBleSdk", package: "polar-ble-sdk"),
                // For the workout files' `serializedBytes()`, kept as the SDK handed them over.
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .target(
            name: "VeselWearableTesting",
            dependencies: ["VeselWearable", "VeselCore"],
            resources: [.copy("Resources/Fixtures")],
            swiftSettings: [.define("VESEL_FAKE_BAND", .when(configuration: .debug))]
        ),
        .testTarget(
            name: "VeselWearableTests",
            dependencies: [
                "VeselWearable",
                "VeselWearableTesting",
                .product(name: "PolarBleSdk", package: "polar-ble-sdk"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
    ]
)
