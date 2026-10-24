// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RoboticsControlCenter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RoboticsControlCenter", targets: ["RoboticsControlCenter"])
    ],
    targets: [
        .executableTarget(
            name: "RoboticsControlCenter",
            resources: [.process("hangar-bay-logo.png")]
        )
    ]
)
