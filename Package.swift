// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SavePoint",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SavePoint", path: "Sources/SavePoint")
    ]
)
