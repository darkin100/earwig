import SwiftUI

/// The People section: lists enrolled voice identities and lets the user forget one.
/// Enrolment happens from a meeting's transcript (see `NameSpeakerSheet`).
struct PeopleView: View {
    let store: IdentityStore

    private static let explainer =
        "Name a speaker in any meeting and Earwig recognises their voice in future meetings."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                content
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("People")
                .font(.pageTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(Self.explainer)
                .font(.bodyText)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if store.people.isEmpty {
            emptyState
        } else {
            GlossyCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.people.enumerated()), id: \.element.name) { index, person in
                        if index > 0 { Hairline().padding(.leading, Spacing.lg) }
                        personCard(person)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        GlossyCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: "person.2")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.accent)
                Text("No voices enrolled yet")
                    .font(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(Self.explainer)
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func personCard(_ person: VoiceIdentity) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.sm) {
                    Text(person.name)
                        .font(.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    if person.isMe {
                        Badge(text: "Me", style: .dot)
                    }
                }
                Text(sampleLabel(person.samples.count))
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            forgetButton(person)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private func forgetButton(_ person: VoiceIdentity) -> some View {
        Button("Forget") {
            try? IdentityService.forget(person.name, voicesURL: Config.voicesURL)
            store.reload()
            NotificationCenter.default.post(name: .earwigIdentitiesChanged, object: nil)
            ToastCenter.shared.success("Removed \(person.name)")
        }
        .buttonStyle(SecondaryButtonStyle(role: Theme.danger))
    }

    private func sampleLabel(_ count: Int) -> String {
        "\(count) voiceprint\(count == 1 ? "" : "s")"
    }
}
