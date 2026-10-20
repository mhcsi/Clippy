// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clippy",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Clippy", targets: ["ClipHistory"])
    ],
    targets: [
        .executableTarget(name: "ClipHistory"),
        .testTarget(name: "ClipHistoryTests", dependencies: ["ClipHistory"])
    ]
)
