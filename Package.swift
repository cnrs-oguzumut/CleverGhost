// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleverGhost",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CleverGhost",
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=minimal")
            ]
        )
    ]
)
