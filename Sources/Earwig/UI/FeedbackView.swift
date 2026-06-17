import SwiftUI

/// Floating feedback form: a smiley mood toggle, a bug/feature/general picker, a message, and an
/// optional reply address. Sends via `ResendClient` and reports the outcome through `ToastCenter`.
struct FeedbackView: View {
    let onClose: () -> Void

    @State private var mood: Feedback.Mood = .happy
    @State private var category: Feedback.Category = .general
    @State private var message = ""
    @State private var email = ""
    @State private var sending = false

    private let client = ResendClient()

    var body: some View {
        ZStack {
            // Dimmed backdrop separates the white card from the (also white) window behind it,
            // and dismisses the form when tapped outside the card.
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            card
        }
        .preferredColorScheme(.light)
        .onExitCommand { onClose() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            moodPicker
            SegmentedControl(selection: $category, items: [
                SegmentItem(.general, title: "General"),
                SegmentItem(.bug, title: "Report a bug"),
                SegmentItem(.feature, title: "Suggest a feature"),
            ])
            PlaceholderTextEditor(
                placeholder: "What's on your mind?",
                text: $message,
                height: 120,
                autoFocus: true)
            emailField
            actions
        }
        .padding(Spacing.xl)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Color.black.opacity(0.28), radius: 40, y: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Send feedback")
                .font(.rowTitle)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
            Text("Tell us what you love or what's broken. It goes straight to the team.")
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var moodPicker: some View {
        HStack(spacing: Spacing.md) {
            ForEach(Feedback.Mood.allCases) { option in
                moodButton(option)
            }
        }
    }

    private func moodButton(_ option: Feedback.Mood) -> some View {
        let selected = mood == option
        return Button {
            mood = option
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: option.symbol)
                    .font(.system(size: 20, weight: .medium))
                Text(option.label)
                    .font(.label)
                    .fontWeight(selected ? .semibold : .regular)
            }
            .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? Theme.elevated : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(selected ? Theme.accent.opacity(0.5) : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var emailField: some View {
        TextField("Your email (optional, so we can reply)", text: $email)
            .textFieldStyle(.plain)
            .font(.label)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Theme.elevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }

    private var actions: some View {
        HStack(spacing: Spacing.md) {
            Spacer(minLength: 0)
            Button("Cancel") { onClose() }
                .buttonStyle(SecondaryButtonStyle())
            Button {
                send()
            } label: {
                HStack(spacing: Spacing.sm) {
                    if sending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.onAccent)
                    }
                    Text(sending ? "Sending..." : "Send feedback")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending)
        }
    }

    // MARK: - Actions

    private func send() {
        let feedback = Feedback(mood: mood, category: category, message: message, contactEmail: email)
        guard feedback.isValid else {
            ToastCenter.shared.warning("Please add a short message first")
            return
        }
        sending = true
        Task {
            do {
                try await client.send(feedback, version: AppInfo.displayVersion)
                ToastCenter.shared.success("Thanks for the feedback")
                onClose()
            } catch {
                ToastCenter.shared.error("Could not send feedback: \(error.localizedDescription)")
                sending = false
            }
        }
    }
}
