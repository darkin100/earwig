// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Earwig",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Earwig",
            path: "Sources/Earwig",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
