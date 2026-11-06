// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FinancialControl",
    defaultLocalization: "pt",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FinancialControl",
            targets: ["FinancialControl"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FinancialControl",
            path: "Sources/FinancialControl",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "FinancialControlTests",
            dependencies: ["FinancialControl"],
            path: "Tests/FinancialControlTests"
        )
    ]
)
