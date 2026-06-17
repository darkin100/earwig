import SwiftUI

/// A tiny live audio equaliser used as the status indicator. Capsule bars ripple with organic,
/// detuned-sine motion and a soft glow; colour comes from the caller (per state). Static when
/// `animated` is false or when Reduce Motion is enabled.
struct SoundBars: View {
    let color: Color
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let count = 5
    private let barWidth: CGFloat = 2.5
    private let gap: CGFloat = 2
    private let maxHeight: CGFloat = 16
    private let minHeight: CGFloat = 3

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    bars { height($0, t) }
                }
            } else {
                bars { _ in maxHeight * 0.45 }
            }
        }
        .frame(width: CGFloat(count) * barWidth + CGFloat(count - 1) * gap, height: maxHeight)
        .accessibilityHidden(true)
    }

    private func bars(_ height: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .center, spacing: gap) {
            ForEach(0 ..< count, id: \.self) { index in
                Capsule()
                    .fill(LinearGradient(colors: [color, color.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: barWidth, height: height(index))
            }
        }
        .shadow(color: color.opacity(0.5), radius: 2.5)
    }

    private func height(_ index: Int, _ t: Double) -> CGFloat {
        let phase = Double(index) * 0.9
        let unit = (sin(t * 4.0 + phase) + sin(t * 6.7 + phase * 1.6) + 2) / 4
        return minHeight + (maxHeight - minHeight) * unit
    }
}
