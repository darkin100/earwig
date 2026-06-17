import XCTest
@testable import Earwig

final class DayLabelTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testToday() {
        let now = date(2026, 6, 15, 16)
        XCTAssertEqual(DayLabel.relativeLabel(for: date(2026, 6, 15, 9), now: now, calendar: cal), "Today")
    }

    func testYesterday() {
        let now = date(2026, 6, 15, 16)
        XCTAssertEqual(DayLabel.relativeLabel(for: date(2026, 6, 14, 23), now: now, calendar: cal), "Yesterday")
    }

    func testOlderUsesWeekdayDate() {
        let now = date(2026, 6, 15, 16)
        XCTAssertEqual(DayLabel.relativeLabel(for: date(2026, 6, 12), now: now, calendar: cal), "Friday, Jun 12")
    }
}
