import Foundation

/// Formats time offsets for transcript display.
enum TimeFormat {
    /// `mm:ss`, or `h:mm:ss` past one hour. Truncates to whole seconds.
    /// Negative input is clamped to zero.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
