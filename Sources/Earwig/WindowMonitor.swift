import AppKit
import ApplicationServices

/// Reads window titles of meeting apps via the Accessibility API (requires the
/// Accessibility permission — deliberately not Screen Recording).
///
/// Used for two things:
///  - capturing the meeting title as context for the transcript
///  - a fast end-of-call signal: the call window closing
///
/// Everything degrades gracefully when the permission is missing: no titles
/// are captured and auto-stop falls back to microphone attribution alone.
enum WindowMonitor {
    struct CallWindow: Hashable {
        let app: String
        let title: String
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt directing the user to System Settings >
    /// Privacy & Security > Accessibility.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Windows of running meeting apps whose titles look like an active call.
    static func callWindowCandidates() -> [CallWindow] {
        guard isTrusted else { return [] }
        var results: [CallWindow] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  let meetingApp = MeetingDetector.knownApps.first(where: { known in
                      known.bundleIDPrefixes.contains(where: { bundleID.hasPrefix($0) })
                  }) else { continue }
            for title in windowTitles(pid: app.processIdentifier) {
                if let meetingTitle = meetingTitle(from: title, bundleID: bundleID) {
                    results.append(CallWindow(app: meetingApp.displayName, title: meetingTitle))
                }
            }
        }
        return results
    }

    private static func windowTitles(pid: pid_t) -> [String] {
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.compactMap { window in
            var title: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
                  let text = title as? String, !text.isEmpty else { return nil }
            return text
        }
    }

    /// Per-app heuristics separating call/meeting windows from an app's
    /// regular windows, returning a cleaned meeting title.
    private static func meetingTitle(from rawTitle: String, bundleID: String) -> String? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        if bundleID.hasPrefix("com.microsoft.teams") {
            // Main-window titles are "<Section> | Microsoft Teams"; meeting
            // windows carry the meeting subject.
            if title == "Microsoft Teams" { return nil }
            let sections = ["Chat", "Activity", "Teams", "Calendar", "Calls", "Files",
                            "Apps", "Notifications", "OneDrive", "Community"]
            for section in sections where title.hasPrefix("\(section) |") { return nil }
            return stripping(title, suffixes: [" | Microsoft Teams"])
        }

        if bundleID.hasPrefix("us.zoom.xos") {
            if ["Zoom", "Zoom Workplace", "Zoom Meeting Login"].contains(title) { return nil }
            if title.hasPrefix("Zoom -") { return nil }
            return title // "Zoom Meeting" or the meeting topic
        }

        if bundleID.hasPrefix("com.tinyspeck.slackmacgap") {
            return title.localizedCaseInsensitiveContains("huddle") ? title : nil
        }

        if bundleID.hasPrefix("net.whatsapp.WhatsApp") {
            // WhatsApp call windows aren't reliably distinguishable by title.
            return nil
        }

        // Browsers: only a Google Meet tab title marks a call window.
        if title.localizedCaseInsensitiveContains("Google Meet")
            || title.hasPrefix("Meet – ") || title.hasPrefix("Meet - ")
            || title.localizedCaseInsensitiveContains("meet.google.com") {
            return stripping(title, suffixes: [
                " - Google Chrome", " — Google Chrome",
                " - Microsoft Edge", " — Microsoft Edge",
                " - Brave", " — Brave",
                " — Mozilla Firefox", " - Mozilla Firefox",
                " - Safari", " — Arc",
            ])
        }
        return nil
    }

    private static func stripping(_ title: String, suffixes: [String]) -> String? {
        var cleaned = title
        for suffix in suffixes {
            if let range = cleaned.range(of: suffix) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
