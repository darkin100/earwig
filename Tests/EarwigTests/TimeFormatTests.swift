import XCTest
@testable import Earwig

final class TimeFormatTests: XCTestCase {
    func testUnderAnHourIsMmSs() {
        XCTAssertEqual(TimeFormat.timestamp(0), "00:00")
        XCTAssertEqual(TimeFormat.timestamp(7), "00:07")
        XCTAssertEqual(TimeFormat.timestamp(67), "01:07")
        XCTAssertEqual(TimeFormat.timestamp(222), "03:42")
    }

    func testOverAnHourIsHMmSs() {
        XCTAssertEqual(TimeFormat.timestamp(3725), "1:02:05")
    }

    func testRoundsDownToWholeSeconds() {
        XCTAssertEqual(TimeFormat.timestamp(7.9), "00:07")
    }

    func testExactHourBoundary() {
        XCTAssertEqual(TimeFormat.timestamp(3600), "1:00:00")
    }

    func testNegativeClampsToZero() {
        XCTAssertEqual(TimeFormat.timestamp(-65), "00:00")
    }
}
