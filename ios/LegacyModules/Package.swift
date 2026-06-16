// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LegacyModules",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "APIClient", targets: ["APIClient"]),
        .library(name: "LocationEngine", targets: ["LocationEngine"]),
        .library(name: "DropFeature", targets: ["DropFeature"]),
        .library(name: "WanderFeature", targets: ["WanderFeature"]),
        .library(name: "MemoryLaneFeature", targets: ["MemoryLaneFeature"]),
        .library(name: "ImportFeature", targets: ["ImportFeature"]),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: []
        ),
        .target(
            name: "APIClient",
            dependencies: []
        ),
        .target(
            name: "LocationEngine",
            dependencies: []
        ),
        .target(
            name: "DropFeature",
            dependencies: ["DesignSystem", "APIClient", "LocationEngine"]
        ),
        .target(
            name: "WanderFeature",
            dependencies: ["DesignSystem", "APIClient", "LocationEngine"]
        ),
        .target(
            name: "MemoryLaneFeature",
            dependencies: ["DesignSystem", "APIClient"]
        ),
        .target(
            name: "ImportFeature",
            dependencies: ["DesignSystem", "APIClient", "LocationEngine"]
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"]
        ),
        .testTarget(
            name: "APIClientTests",
            dependencies: ["APIClient"]
        ),
        .testTarget(
            name: "LocationEngineTests",
            dependencies: ["LocationEngine"]
        ),
    ]
)
