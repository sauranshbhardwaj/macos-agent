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
    targets: [
        .target(
            name: "MacAgentCore",
            path: "Sources/MacAgentCore"
        ),
        .executableTarget(
            name: "MacAgent",
            dependencies: ["MacAgentCore"],
            path: "Sources/MacAgent"
        ),
        .testTarget(
            name: "MacAgentCoreTests",
            dependencies: ["MacAgentCore"],
            path: "Tests/MacAgentCoreTests"
        )
    ]
)
