import SwiftUI

/// Renders the current `ToastCenter` toast as a glassy capsule that slides in from the top and
/// fades out. Mounted as a non-interactive overlay on the main window.
struct ToastOverlay: View {
    @State private var center = ToastCenter.shared

    var body: some View {
        VStack {
            if let toast = center.current {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: toast.style.icon)
                        .foregroundStyle(toast.style.tint)
                    Text(toast.message)
                        .font(.label).foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .padding(.top, Spacing.lg)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.3), value: center.current)
    }
}
