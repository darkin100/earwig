// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Earwig",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", from: "0.15.3"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        // Summaries run via an external engine, not an embedded library: Ollama (a local
        // daemon, the default) or Apple's built-in Foundation Models. So there's no LLM
        // SwiftPM dependency — see OllamaClient.swift / AppleSummaryEngine.swift.
    ],
    targets: [
        .executableTarget(
            name: "Earwig",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/Earwig",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EarwigTests",
            dependencies: ["Earwig"],
            path: "Tests/EarwigTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
