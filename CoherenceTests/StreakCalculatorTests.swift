import XCTest

/// Deterministic streak tests — explicit `today` and a fixed UTC Gregorian
/// calendar so day boundaries never depend on the test machine's locale.
final class StreakCalculatorTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func test_emptyReturnsZero() {
        let r = StreakCalculator.streak(from: [], today: day(2026, 1, 10), calendar: cal)
        XCTAssertEqual(r.current, 0)
        XCTAssertEqual(r.longest, 0)
    }

    /// Two sessions on the same local day count once — current stays 1.
    func test_sameDayDoesNotIncrement() {
        let sessions = [day(2026, 1, 10, 8), day(2026, 1, 10, 20)]
        let r = StreakCalculator.streak(from: sessions, today: day(2026, 1, 10), calendar: cal)
        XCTAssertEqual(r.current, 1)
    }

    /// Consecutive days extend the current streak.
    func test_oneDayGapContinues() {
        let sessions = [day(2026, 1, 8), day(2026, 1, 9), day(2026, 1, 10)]
        let r = StreakCalculator.streak(from: sessions, today: day(2026, 1, 10), calendar: cal)
        XCTAssertEqual(r.current, 3)
    }

    /// A gap > 1 day resets current to the run ending at the anchor (not the whole
    /// history), while longest remembers the earlier, longer run.
    func test_multiDayGapResets() {
        let sessions = [day(2026, 1, 1), day(2026, 1, 2), day(2026, 1, 3),
                        day(2026, 1, 9), day(2026, 1, 10)]
        let r = StreakCalculator.streak(from: sessions, today: day(2026, 1, 10), calendar: cal)
        XCTAssertEqual(r.current, 2)
        XCTAssertEqual(r.longest, 3)
    }

    /// Longest reflects the best past run even after the current streak is broken.
    func test_longestSurvivesBreak() {
        let sessions = [day(2026, 1, 1), day(2026, 1, 2), day(2026, 1, 3),
                        day(2026, 1, 4), day(2026, 1, 5),   // 5-day run
                        day(2026, 1, 10), day(2026, 1, 11)] // later 2-day run
        let r = StreakCalculator.streak(from: sessions, today: day(2026, 1, 20), calendar: cal)
        XCTAssertEqual(r.current, 0)   // nothing today or yesterday
        XCTAssertEqual(r.longest, 5)
    }
}
