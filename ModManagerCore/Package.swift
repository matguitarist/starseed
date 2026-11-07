// swift-tools-version: 6.0
import PackageDescription

// Filesystem, manifest and Nexus/SMAPI logic, kept free of UI code so it can
// be tested on its own (`swift test` here, or ⌘U in Xcode).
let package = Package(
    name: "ModManagerCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ModManagerCore", targets: ["ModManagerCore"]),
    ],
    dependencies: [
        // SMAPI's log is parsed and shown with the log viewer the apps share.
        .package(url: "https://github.com/matguitarist/LogKit", from: "0.2.0"),
    ],
    targets: [
        .target(name: "ModManagerCore",
                dependencies: [.product(name: "LogKit", package: "LogKit")],
                resources: [.process("Resources")]),
        .testTarget(name: "ModManagerCoreTests", dependencies: ["ModManagerCore"]),
    ]
)
