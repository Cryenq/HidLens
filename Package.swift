// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HidLens",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "hidlens", targets: ["hidlens"]),
        .library(name: "HidLensCore", targets: ["HidLensCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        // Shared library — HID access, models, services, export
        .target(
            name: "HidLensCore",
            dependencies: [],
            path: "Sources/HidLensCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),

        // CLI executable
        .executableTarget(
            name: "hidlens",
            dependencies: [
                "HidLensCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/hidlens"
        ),

        // Unit tests
        .testTarget(
            name: "HidLensCoreTests",
            dependencies: ["HidLensCore"],
            path: "Tests/HidLensCoreTests"
        )
    ]
)
