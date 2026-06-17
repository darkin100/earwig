import SwiftUI

/// A premium, animated empty state for the detail pane when no meeting is selected: a breathing
/// gradient equaliser over a soft pulsing glow, with a gentle float and an entrance pop. Falls
/// back to a calm static version under Reduce Motion.
struct EmptyMeetingState: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let count = 9
    private let barWidth: CGFloat = 9
    private let gap: CGFloat = 7
    private let maxHeight: CGFloat = 84
    private let minHeight: CGFloat = 16

    var body: some View {
        VStack(spacing: Spacing.xl) {
            equaliser
            VStack(spacing: Spacing.xs) {
                Text("Select a meeting")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Pick one from the list, or hit Record to capture a new one.")
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
        }
    }

    private var equaliser: some View {
        Group {
            if reduceMotion {
                glow(scale: 1).overlay(bars { staticHeight($0) })
            } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    glow(scale: 1 + 0.10 * CGFloat(sin(t * 1.6)))
                        .overlay(bars { height($0, t) })
                        .offset(y: CGFloat(sin(t * 1.2)) * 4)
                }
            }
        }
        .frame(width: 180, height: 180)
    }

    private func glow(scale: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Theme.accent.opacity(0.28), Theme.accent2.opacity(0.10), .clear],
                    center: .center, startRadius: 4, endRadius: 110))
            .frame(width: 200, height: 200)
            .blur(radius: 12)
            .scaleEffect(scale)
    }

    private func bars(_ height: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .center, spacing: gap) {
            ForEach(0 ..< count, id: \.self) { index in
                Capsule()
                    .fill(Theme.primaryGradient)
                    .frame(width: barWidth, height: height(index))
            }
        }
        .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 2)
    }

    /// Organic detuned-sine motion, tallest near the centre, so it reads as a living equaliser.
    private func height(_ index: Int, _ t: Double) -> CGFloat {
        let centre = Double(count - 1) / 2
        let falloff = 1 - abs(Double(index) - centre) / centre * 0.45
        let phase = Double(index) * 0.7
        let unit = (sin(t * 3.2 + phase) + sin(t * 5.1 + phase * 1.7) + 2) / 4
        return minHeight + (maxHeight - minHeight) * CGFloat(unit * falloff)
    }

    private func staticHeight(_ index: Int) -> CGFloat {
        let centre = Double(count - 1) / 2
        let falloff = 1 - abs(Double(index) - centre) / centre * 0.5
        return minHeight + (maxHeight - minHeight) * 0.5 * CGFloat(falloff)
    }
}
