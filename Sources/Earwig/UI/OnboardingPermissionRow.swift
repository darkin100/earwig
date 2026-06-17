import SwiftUI

/// One permission line in the onboarding Permissions step: an icon, a title + explanation,
/// a live status pill, and a contextual action (Grant when undetermined, Open Settings
/// when denied, a checkmark when granted).
struct OnboardingPermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let isRequired: Bool
    let status: Authorization
    /// Request access (or, when denied, open System Settings). The view decides which by
    /// inspecting `status`.
    let onGrant: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.elevated)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.accent))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.sm) {
                    Text(title)
                        .font(.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    if !isRequired {
                        Badge(text: "Optional")
                    }
                }
                Text(detail)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.md)
            action
        }
        .padding(.vertical, Spacing.md)
    }

    @ViewBuilder
    private var action: some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.captionText).fontWeight(.semibold)
                .foregroundStyle(Theme.accent)
        case .notDetermined:
            Button("Grant", action: onGrant)
                .buttonStyle(SecondaryButtonStyle())
        case .denied:
            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(SecondaryButtonStyle(role: Theme.amber))
        }
    }
}
