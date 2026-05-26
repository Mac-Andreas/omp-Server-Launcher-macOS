// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ServerLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ServerLauncher",
            path: "Sources/ServerLauncher",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
