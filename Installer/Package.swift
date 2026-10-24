// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DarkstarInstaller",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DarkstarInstaller",
            path: "Sources/DarkstarInstaller",
            resources: [
                .process("installer-logo.png"),
                .copy("Payload")
            ]
        )
    ]
)
