// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Bare Command Line Tools installs ship Swift Testing as a framework that
// needs explicit search paths (full Xcode handles this itself, in which case
// these flags are omitted).
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltHasTesting = FileManager.default.fileExists(atPath: cltFrameworks + "/Testing.framework")
let testingSwiftFlags: [SwiftSetting] =
    cltHasTesting ? [.unsafeFlags(["-F", cltFrameworks])] : []
let testingLinkerFlags: [LinkerSetting] =
    cltHasTesting
    ? [.unsafeFlags([
        "-F", cltFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
        "-Xlinker", "-rpath", "-Xlinker",
        "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
    ])]
    : []

let package = Package(
    name: "Earwig",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")
    ],
    targets: [
        .target(
            name: "EarwigKit",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/EarwigKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Earwig",
            dependencies: ["EarwigKit"],
            path: "Sources/Earwig",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Tests run via `swift run earwig-tests` (Swift Testing, invoked
        // directly — SwiftPM's own test runner doesn't work with swift-testing
        // on bare Command Line Tools installs).
        .executableTarget(
            name: "earwig-tests",
            dependencies: ["EarwigKit"],
            path: "Tests/EarwigTests",
            swiftSettings: [.swiftLanguageMode(.v5)] + testingSwiftFlags,
            linkerSettings: testingLinkerFlags
        )
    ]
)
