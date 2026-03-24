// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "yoink",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "yoink", path: "Sources")
    ]
)
