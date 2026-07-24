// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Earwig",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Earwig",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/Earwig",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
