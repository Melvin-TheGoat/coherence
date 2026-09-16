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

    // MARK: - Rest days (one missed day per seven is forgiven)

    /// A single missed day between practised days bridges the run; it is not
    /// counted as a practised day.
    func test_oneMissedDayIsForgiven() {
        let sessions = [day(2026, 1, 8), day(2026, 1, 9), day(2026, 1, 11)]
        let r = StreakCalculator.streak(from: sessions, today: day(2026, 1, 11), calendar: cal)
        XCTAssertEqual(r.current, 3)
        XCTAssertEqual(r.longest, 3)
        XCTAssertFalse(r.restDayUsed, "the rest day is behind a practised day, nothing is pending")
    }

    /// Two missed days in a row are a break, not two rest days.
    func test_twoMissedDaysBreak() {
        let sessions = [day(2026, 1, 8), day(2026, 1, 9), day(2026, 1, 12)]
        let r = StreakCalculator.streak(from: sessions, today: day(2026, 1, 12), calendar: cal)
        XCTAssertEqual(r.current, 1)
        XCTAssertEqual(r.longest, 2)
    }

    /// A second rest day inside seven days is not forgiven.
    func test_secondRestWithinAWeekBreaks() {
        let sessions = [day(2026, 1, 1), day(2026, 1, 2), day(2026, 1, 4),   // rest on the 3rd
                        day(2026, 1, 5), day(2026, 1, 7)]                     // rest on the 6th: too soon
        let r = StreakCalculator.streak(from: sessions, today: day(2026, 1, 7), calendar: cal)
        XCTAssertEqual(r.current, 1)
        XCTAssertEqual(r.longest, 4)
    }

    /// Seven days after a rest day, another one is available.
    func test_restDayAWeekLaterIsForgivenAgain() {
        var sessions = [day(2026, 1, 1), day(2026, 1, 2)]                     // rest on the 3rd
        sessions += (4...9).map { day(2026, 1, $0) }                          // rest on the 10th, 7 days later
        sessions += [day(2026, 1, 11)]
        let r = StreakCalculator.streak(from: sessions, today: day(2026, 1, 11), calendar: cal)
        XCTAssertEqual(r.current, 9)
        XCTAssertEqual(r.longest, 9)
    }

    /// Missed yesterday, nothing yet today: the run is carried on a rest day
    /// and today is on the line.
    func test_yesterdayMissedIsCarriedAsARestDay() {
        let sessions = [day(2026, 1, 8), day(2026, 1, 9)]
        let r = StreakCalculator.streak(from: sessions, today: day(2026, 1, 11), calendar: cal)
        XCTAssertEqual(r.current, 2)
        XCTAssertTrue(r.restDayUsed)
        // And with no rest day available (one taken four days ago), it is over.
        let spent = [day(2026, 1, 4), day(2026, 1, 5), day(2026, 1, 7),      // rest on the 6th
                     day(2026, 1, 8), day(2026, 1, 9)]
        let r2 = StreakCalculator.streak(from: spent, today: day(2026, 1, 11), calendar: cal)
        XCTAssertEqual(r2.current, 0)
        XCTAssertFalse(r2.restDayUsed)
    }

    /// The runs the awards read carry the same rest days.
    func test_runsShareTheRuleWithAwards() {
        let sessions = [day(2026, 1, 8), day(2026, 1, 9), day(2026, 1, 11), day(2026, 1, 20)]
        let runs = StreakCalculator.runs(from: sessions, calendar: cal)
        XCTAssertEqual(runs.map(\.length), [3, 1])
        XCTAssertEqual(runs[0].restDays, [day(2026, 1, 10, 0)])
        XCTAssertEqual(AwardEngine.streakRuns(sessions, calendar: cal).map(\.length), [3, 1])
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
