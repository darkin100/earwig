import Foundation
import Testing

/// Swift Testing entry point, invoked directly because bare Command Line
/// Tools installs lack a working SwiftPM test runner for swift-testing.
/// Run with: swift run earwig-tests
@main struct EarwigTestRunner {
    static func main() async {
        exit(await Testing.__swiftPMEntryPoint(passing: nil) as Int32)
    }
}
