// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FinSense",
    defaultLocalization: "pt",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FinSense",
            targets: ["FinSense"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FinSense",
            path: "Sources/FinSense",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "FinSenseTests",
            dependencies: ["FinSense"],
            path: "Tests/FinSenseTests"
        )
    ]
)
