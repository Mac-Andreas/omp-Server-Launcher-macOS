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
            ],
            swiftSettings: [
                // Run the Wine wrapper + CrossOver tools as subprocesses; no
                // sandbox so we can reach /Applications/CrossOver.app and the
                // server folder beside the .app.
                .unsafeFlags([], .when(platforms: [.macOS])),
            ]
        ),
    ]
)
