// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "yoink",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "YoinkLib", path: "Sources/YoinkLib"),
        .executableTarget(name: "yoink", dependencies: ["YoinkLib"], path: "Sources/YoinkApp"),
        .testTarget(name: "YoinkTests", dependencies: ["YoinkLib"], path: "Tests"),
    ]
)
