// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DexFiller",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DexFillerCore", targets: ["DexFillerCore"]),
    ],
    targets: [
        .executableTarget(
            name: "DexFiller",
            dependencies: ["DexFillerCore"],
            path: "Sources/DexFiller"
        ),
        .target(
            name: "DexFillerCore",
            path: "Sources/DexFillerCore"
        ),
        .testTarget(
            name: "DexFillerCoreTests",
            dependencies: ["DexFillerCore"],
            path: "Tests/DexFillerCoreTests"
        ),
    ]
)
