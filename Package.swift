// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacAgent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacAgent", targets: ["MacAgent"]),
        .library(name: "MacAgentCore", targets: ["MacAgentCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.5")
    ],
    targets: [
        .target(
            name: "MacAgentCore",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            path: "Sources/MacAgentCore"
        ),
        .executableTarget(
            name: "MacAgent",
            dependencies: ["MacAgentCore"],
            path: "Sources/MacAgent",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MacAgentCoreTests",
            dependencies: ["MacAgentCore"],
            path: "Tests/MacAgentCoreTests"
        )
    ]
)
