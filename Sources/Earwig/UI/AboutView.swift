import AppKit
import SwiftUI

/// Settings → About: app identity + version/build, and the release notes ("What's new").
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("About").font(.pageTitle).foregroundStyle(Theme.textPrimary)
                GlossyCard {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        identity
                        Hairline()
                        story
                        Hairline()
                        credits
                        Hairline()
                        privacy
                        Hairline()
                        releaseNotes
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var privacy: some View {
        FlatSection("Privacy") {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Theme.accent)
                Text("On-device by default. Audio, transcripts, summaries and voiceprints never leave your Mac. Models download once, then run offline. If you turn on the optional Claude engine, your transcript text is sent to Anthropic for that request.")
                    .font(.bodyText).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Earwig").font(.sectionLarge).foregroundStyle(Theme.textPrimary)
                ClearRouteByline()
                Text("Version \(AppInfo.version) · build \(AppInfo.build)")
                    .font(.captionText).foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .padding(.top, Spacing.xxs)
                if let sha = AppInfo.gitSHA {
                    Text(sha).font(.captionText).monospaced()
                        .foregroundStyle(Theme.textTertiary).textSelection(.enabled)
                }
            }
            Spacer(minLength: Spacing.md)
            Button("ClearRoute") {
                NSWorkspace.shared.open(URL(string: "https://clearroute.io")!)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var story: some View {
        FlatSection("Why Earwig exists") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Earwig began as Glyn Darkin's lightweight answer to Granola: a little Mac menu-bar app that quietly watches for online meetings, records them, and saves the transcripts to disk. The idea was deliberately simple, so you can wire up your own Claude Cowork flow to grab actions and risks and push them wherever you like, whether that is Notion, Slack or anywhere else.")
                    .font(.bodyText).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Navnit Anuth then ran with it, adding speaker identification so you can tell who said what, and growing it into what you are using today: search across every meeting, ask your meetings questions, on-device summaries, notes, and a fair bit of polish. Have fun.")
                    .font(.bodyText).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("View on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/darkin100/earwig")!)
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, Spacing.xxs)
            }
        }
    }

    private var credits: some View {
        FlatSection("Credits") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                creditRow("Lead developer", "Navnit Anuth")
                creditRow("Creator", "Glyn Darkin")
            }
        }
    }

    private func creditRow(_ role: String, _ name: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(role)
                .font(.captionText).foregroundStyle(Theme.textTertiary)
                .frame(width: 120, alignment: .leading)
            Text(name)
                .font(.bodyText).fontWeight(.medium).foregroundStyle(Theme.textPrimary)
        }
    }

    private var releaseNotes: some View {
        FlatSection("What's new") {
            ForEach(Array(ReleaseNotes.all.enumerated()), id: \.element.id) { index, note in
                if index > 0 { Hairline() }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Text(note.version).font(.rowTitle).foregroundStyle(Theme.textPrimary)
                        Text(note.date).font(.captionText).foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(note.highlights, id: \.self) { highlight in
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 7)
                            Text(highlight)
                                .font(.bodyText).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
