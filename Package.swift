// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Bare Command Line Tools installs ship Swift Testing as a framework that
// needs explicit search paths (full Xcode handles this itself, in which case
// these flags are omitted).
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltHasTesting = FileManager.default.fileExists(atPath: cltFrameworks + "/Testing.framework")
// The swift-testing macro plugin lives beside the toolchain, not the SDK, so
// when SDKROOT is pointed at an older SDK (see build.sh) the compiler no
// longer finds it on its own.
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let cltHasTestingPlugins = FileManager.default.fileExists(atPath: cltTestingPlugins)
let testingSwiftFlags: [SwiftSetting] =
    (cltHasTesting ? [.unsafeFlags(["-F", cltFrameworks])] : [])
    + (cltHasTestingPlugins ? [.unsafeFlags(["-plugin-path", cltTestingPlugins])] : [])
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
        // Objective-C shim: converts raised NSExceptions into NSErrors.
        // AVFoundation reports some invalid-argument cases by raising, which
        // Swift cannot catch — an uncaught one aborts the process.
        .target(
            name: "EarwigObjC",
            path: "Sources/EarwigObjC"
        ),
        .target(
            name: "EarwigKit",
            dependencies: [
                "EarwigObjC",
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
