// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LegacyModules",
    // iOS is the only shipping platform; macOS is declared solely so `swift build`
    // can host-compile the non-UI modules in CI without full Xcode.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "APIClient", targets: ["APIClient"]),
        .library(name: "LocationEngine", targets: ["LocationEngine"]),
        .library(name: "DropFeature", targets: ["DropFeature"]),
        .library(name: "WanderFeature", targets: ["WanderFeature"]),
        .library(name: "MemoryLaneFeature", targets: ["MemoryLaneFeature"]),
        .library(name: "ImportFeature", targets: ["ImportFeature"]),
        .library(name: "AuthFeature", targets: ["AuthFeature"]),
        // Debug/test/preview support only — intentionally NOT a dependency of the app target.
        .library(name: "LegacyAPIStubs", targets: ["LegacyAPIStubs"]),
    ],
    dependencies: [
        // MapLibre Native — custom-styled vector-tile renderer powering the immersive
        // Wander map (pitched, heading-locked, art-directed style). iOS-only binary;
        // gated per-platform on the WanderFeature target so macOS host compiles (CI) stay clean.
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution.git", from: "6.27.0"),
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
            dependencies: ["APIClient"]
        ),
        .target(
            name: "DropFeature",
            dependencies: ["DesignSystem", "APIClient", "LocationEngine"]
        ),
        .target(
            name: "WanderFeature",
            dependencies: [
                "DesignSystem", "APIClient", "LocationEngine", "MemoryLaneFeature",
                .product(
                    name: "MapLibre",
                    package: "maplibre-gl-native-distribution",
                    condition: .when(platforms: [.iOS])
                ),
            ]
        ),
        .target(
            name: "MemoryLaneFeature",
            dependencies: ["DesignSystem", "APIClient", "LocationEngine"]
        ),
        .target(
            name: "ImportFeature",
            dependencies: ["DesignSystem", "APIClient", "LocationEngine", "DropFeature"]
        ),
        .target(
            name: "AuthFeature",
            dependencies: ["DesignSystem", "APIClient"]
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"]
        ),
        .target(
            name: "LegacyAPIStubs",
            dependencies: ["APIClient"]
        ),
        .testTarget(
            name: "APIClientTests",
            dependencies: ["APIClient", "LegacyAPIStubs"]
        ),
        .testTarget(
            name: "LocationEngineTests",
            dependencies: ["LocationEngine"]
        ),
        .testTarget(
            name: "DropFeatureTests",
            dependencies: ["DropFeature"]
        ),
        .testTarget(
            name: "WanderFeatureTests",
            dependencies: ["WanderFeature", "APIClient", "DesignSystem"]
        ),
        .testTarget(
            name: "ImportFeatureTests",
            dependencies: ["ImportFeature"]
        ),
        .testTarget(
            name: "MemoryLaneFeatureTests",
            dependencies: ["MemoryLaneFeature", "APIClient"]
        ),
    ]
)
