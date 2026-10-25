// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NPpp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "NPpp", path: "Sources/NPpp")
    ]
)
