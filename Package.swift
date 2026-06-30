// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GoDex",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GoDexCore", targets: ["GoDexCore"]),
        .executable(name: "godex", targets: ["GoDexCLI"]),
    ],
    targets: [
        .executableTarget(
            name: "GoDex",
            dependencies: ["GoDexCore"],
            path: "Sources/GoDex"
        ),
        .executableTarget(
            name: "GoDexCLI",
            dependencies: ["GoDexCore"],
            path: "Sources/GoDexCLI"
        ),
        .target(
            name: "GoDexCore",
            path: "Sources/GoDexCore"
        ),
        .testTarget(
            name: "GoDexCoreTests",
            dependencies: ["GoDexCore"],
            path: "Tests/GoDexCoreTests"
        ),
    ]
)
