// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WhisperWrap",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.13.4"),
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
    ]
)
