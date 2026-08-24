// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WhisperWrap",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0"),
        // Pre-1.0, so an open `from:` range risks resolving an API-breaking 0.15
        // (e.g. VadManager.chunkSize) on a fresh `swift package update`. Tightened
        // per AUDIT.md §6.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.14.7")),
    ],
    targets: [
        .executableTarget(
            name: "WhisperWrap",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            resources: [.copy("Resources/AppIcon.appiconset")]
        ),
        .testTarget(
            name: "WhisperWrapTests",
            dependencies: ["WhisperWrap"],
            path: "Tests/WhisperWrapTests"
        ),
    ]
)
