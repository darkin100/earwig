import Foundation

/// App version info read from the bundle (written by `build.sh` from `VERSION` + git).
enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    static var gitSHA: String? {
        let sha = Bundle.main.infoDictionary?["EarwigGitSHA"] as? String
        return (sha?.isEmpty ?? true) || sha == "unknown" ? nil : sha
    }

    static var displayVersion: String { "\(version) (\(build))" }
}
