import SwiftUI

/// The "How to use Earwig" guide: a flow diagram of how Earwig works, then topic cards.
struct HelpView: View {
    private struct Step: Identifiable {
        let icon: String
        let label: String
        var id: String { label }
    }

    private struct Topic: Identifiable {
        let icon: String
        let title: String
        let body: String
        var id: String { title }
    }

    private let flow: [Step] = [
        Step(icon: "record.circle", label: "Record"),
        Step(icon: "text.alignleft", label: "Transcribe"),
        Step(icon: "person.2.fill", label: "Name voices"),
        Step(icon: "sparkles", label: "Summarise"),
    ]

    private let topics: [Topic] = [
        Topic(icon: "record.circle",
              title: "Recording a meeting",
              body: "When you join a Teams, Slack, Zoom or Google Meet call, Earwig shows a **Meeting detected** prompt. Tap **Record**. You can also start it yourself with **Record** in the sidebar. A small pill shows that it is recording. Press **Stop** when you are done and Earwig transcribes the meeting on your Mac."),
        Topic(icon: "person.2.fill",
              title: "Naming speakers",
              body: "Open a meeting and tap the speaker chip, then give each voice a name. Pick someone you have named before in one tap, or add a new name. Earwig then recognises that voice in your future meetings. Mark your own voice with **This is me**."),
        Topic(icon: "sparkles",
              title: "Summaries",
              body: "Earwig summarises every meeting on your Mac. Choose the engine in **Settings › Summary**. Use **Ollama** (install it from ollama.com, then download a model), **Apple Intelligence** (macOS 26, nothing to download), or **Claude** (Anthropic cloud, best quality, requires an API key). Pick a template, and tap **Regenerate** whenever you like."),
        Topic(icon: "lock.shield.fill",
              title: "Privacy",
              body: "Everything runs on your Mac by default. Your audio, transcripts, summaries and voiceprints never leave your device. If you turn on the optional Claude engine, your transcript text is sent to Anthropic for that request."),
        Topic(icon: "wrench.and.screwdriver.fill",
              title: "Tips",
              body: "Run the welcome flow again from **Settings › Setup**. Transcribe a meeting again, or copy its transcript, from the meeting's **Details** tab. Your notes live in the folder shown under **Settings › Storage**."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                flowCard
                topicsCard
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Help").font(.pageTitle).foregroundStyle(Theme.textPrimary)
            Text("How to get the most out of Earwig.")
                .font(.bodyText).foregroundStyle(Theme.textSecondary)
        }
    }

    private var flowCard: some View {
        GlossyCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SectionHeader("How Earwig works")
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(flow.enumerated()), id: \.element.id) { index, step in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                        stepChip(step)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func stepChip(_ step: Step) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: step.icon)
                .font(.title2).foregroundStyle(Theme.accent)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Theme.accent.opacity(0.12)))
            Text(step.label).font(.captionText).foregroundStyle(Theme.textSecondary)
        }
    }

    private var topicsCard: some View {
        GlossyCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                    if index > 0 { Hairline().padding(.vertical, Spacing.lg) }
                    row(topic)
                }
            }
        }
    }

    private func row(_ topic: Topic) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: topic.icon)
                .font(.title3).foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(topic.title).font(.rowTitle).foregroundStyle(Theme.textPrimary)
                Text(.init(topic.body))
                    .font(.bodyText).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
