import Foundation

/// Human-friendly day headers for the meetings list: "Today", "Yesterday", else a full
/// weekday + date (e.g. "Monday, Jun 15"). Pure so it's testable against a fixed `now`.
enum DayLabel {
    static func relativeLabel(for day: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return fullFormatter.string(from: day)
    }

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
}
