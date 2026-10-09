// swift-tools-version: 6.0
import PackageDescription

// Filesystem, manifest and Nexus/SMAPI logic, kept free of UI code so it can
// be tested on its own (`swift test` here, or ⌘U in Xcode).
let package = Package(
    name: "ModManagerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ModManagerCore", targets: ["ModManagerCore"]),
    ],
    targets: [
        .target(name: "ModManagerCore"),
        .testTarget(name: "ModManagerCoreTests", dependencies: ["ModManagerCore"]),
    ]
)
