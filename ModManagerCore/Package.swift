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
        .package(url: "https://github.com/matguitarist/LogKit", from: "0.6.0"),
        // Runs ditto, zip, tar and SMAPI's installer without blocking on a full pipe.
        .package(url: "https://github.com/matguitarist/ProcessKit", from: "0.1.1"),
    ],
    targets: [
        .target(name: "ModManagerCore",
                dependencies: [
                    .product(name: "LogKit", package: "LogKit"),
                    .product(name: "ProcessKit", package: "ProcessKit"),
                ],
                resources: [.process("Resources")]),
        .testTarget(name: "ModManagerCoreTests", dependencies: [
            "ModManagerCore",
            .product(name: "ProcessKit", package: "ProcessKit"),
        ]),
    ]
)
