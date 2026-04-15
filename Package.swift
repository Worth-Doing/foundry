// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Foundry",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Foundry",
            path: "Sources/Foundry",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "FoundryTests",
            dependencies: ["Foundry"],
            path: "Tests/FoundryTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
