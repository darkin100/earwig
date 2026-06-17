import Foundation

/// A release's user-facing highlights, shown in About. Kept in step with `CHANGELOG.md`.
struct ReleaseNote: Identifiable {
    let version: String
    let date: String
    let highlights: [String]

    var id: String { version }
}

enum ReleaseNotes {
    static let all: [ReleaseNote] = [
        ReleaseNote(
            version: "0.5",
            date: "2026-06-17",
            highlights: [
                "Search across every meeting, with a ⌘K spotlight to jump to any of them instantly.",
                "Ask your meetings: pose a question and get an answer drawn from your transcripts, with clickable sources.",
                "Claude is now an optional summary engine alongside on-device Ollama and Apple Intelligence.",
                "Local summaries upgraded to Qwen2.5 14B, much closer to cloud quality.",
                "Faster, lighter transcription using Whisper large-v3 turbo.",
                "Jot notes on any meeting; they are folded into the summary when you regenerate.",
                "Send feedback straight from the app, and delete meetings you no longer need.",
                "Live CPU meter in the sidebar, a new app icon, and a lot of UI and performance polish.",
            ]),
        ReleaseNote(
            version: "0.2.0",
            date: "2026-06-16",
            highlights: [
                "Help and About now live in the sidebar, with a how to use guide.",
                "App version and build number shown in About.",
                "Release notes you can read in the app.",
            ]),
        ReleaseNote(
            version: "0.1.0",
            date: "2026-06-16",
            highlights: [
                "On device meeting summaries via Ollama or Apple Intelligence. Pick the engine in Settings.",
                "Light, glossy redesign throughout.",
                "Reliable summaries: long meetings no longer fail, with automatic retry, and past meetings fill in on their own.",
                "Name a speaker once and Earwig recognises them in future meetings. Now pick existing people in one tap.",
                "Smarter meeting detection prompt for Teams, Slack, Zoom and more.",
            ]),
    ]
}
