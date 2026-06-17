import AppKit
import SwiftUI

/// The glossy "Meeting detected" prompt shown top-right when a call is detected. Light card with
/// the Earwig mark, the detected app, and Ignore / Record actions (Record is the gradient primary).
struct RecordPromptView: View {
    let appName: String
    let onRecord: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.md) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Meeting detected")
                        .font(.rowTitle).foregroundStyle(Theme.textPrimary)
                    Text("\(appName) is on your mic")
                        .font(.captionText).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: Spacing.lg)
            }
            HStack(spacing: Spacing.sm) {
                ClearRouteByline()
                Spacer(minLength: Spacing.sm)
                Button("Ignore", action: onIgnore)
                    .buttonStyle(SecondaryButtonStyle())
                Button("Record", systemImage: "record.circle.fill", action: onRecord)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Spacing.lg)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        .padding(Spacing.md)   // room for the shadow inside the clear panel
        .preferredColorScheme(.light)
    }
}
