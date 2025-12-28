// swift-tools-version: 6.0
// SwiftLocalize - Automated localization using AI/ML translation providers

import PackageDescription

let package = Package(
    name: "SwiftLocalize",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        // Core library for programmatic use
        .library(
            name: "SwiftLocalizeCore",
            targets: ["SwiftLocalizeCore"]
        ),
        // Command-line tool
        .executable(
            name: "swiftlocalize",
            targets: ["SwiftLocalizeCLI"]
        ),
        // Build tool plugin (runs on every build)
        .plugin(
            name: "SwiftLocalizeBuildPlugin",
            targets: ["SwiftLocalizeBuildPlugin"]
        ),
        // Command plugin (on-demand)
        .plugin(
            name: "SwiftLocalizeCommandPlugin",
            targets: ["SwiftLocalizeCommandPlugin"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // MARK: - Core Library

        .target(
            name: "SwiftLocalizeCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // MARK: - CLI Tool

        .executableTarget(
            name: "SwiftLocalizeCLI",
            dependencies: [
                "SwiftLocalizeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // MARK: - Plugins

        .plugin(
            name: "SwiftLocalizeBuildPlugin",
            capability: .buildTool(),
            dependencies: []
        ),

        .plugin(
            name: "SwiftLocalizeCommandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "localize",
                    description: "Translate xcstrings files using AI/ML providers"
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Update xcstrings files with translations"),
                    .allowNetworkConnections(
                        scope: .all(ports: []),
                        reason: "Connect to translation APIs"
                    ),
                ]
            ),
            dependencies: []
        ),

        // MARK: - Tests

        .testTarget(
            name: "SwiftLocalizeCoreTests",
            dependencies: ["SwiftLocalizeCore"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
