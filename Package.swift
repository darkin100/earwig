// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Earwig",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")
    ],
    targets: [
        .executableTarget(
            name: "Earwig",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/Earwig",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
