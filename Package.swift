// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RoboticsControlCenter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RoboticsControlCenter", targets: ["RoboticsControlCenter"]),
        .library(name: "DarkstarCore", targets: ["DarkstarCore"]),
        .library(name: "DarkstarLink", targets: ["DarkstarLink"]),
        .executable(name: "darkstar", targets: ["DarkstarCLI"])
    ],
    targets: [
        .target(
            name: "DarkstarCore",
            path: "Sources/DarkstarCore"
        ),
        .target(
            name: "DarkstarLink",
            dependencies: ["DarkstarCore"],
            path: "Sources/DarkstarLink"
        ),
        .executableTarget(
            name: "DarkstarCLI",
            dependencies: ["DarkstarCore", "DarkstarLink"],
            path: "Sources/DarkstarCLI"
        ),
        .executableTarget(
            name: "RoboticsControlCenter",
            dependencies: ["DarkstarCore"],
            resources: [.process("hangar-bay-logo.png")]
        ),
        .testTarget(
            name: "DarkstarCoreTests",
            dependencies: ["DarkstarCore"],
            path: "Tests/Unit"
        ),
        .testTarget(
            name: "DarkstarIntegrationTests",
            dependencies: ["DarkstarCore"],
            path: "Tests/Integration"
        ),
        .testTarget(
            name: "DarkstarE2ETests",
            dependencies: ["DarkstarCore"],
            path: "Tests/E2E"
        ),
        .testTarget(
            name: "DarkstarLinkTests",
            dependencies: ["DarkstarLink"],
            path: "Tests/Link"
        )
    ]
)
