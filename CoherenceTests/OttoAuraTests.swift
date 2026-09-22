import XCTest

/// Otto's aura: the numbers promised in `mockups/otto-aura.html`, pinned. A
/// fixed UTC calendar and explicit `today`, as the streak tests do.
final class OttoAuraTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h))!
    }

    private func level(_ days: [Int], today: Int) -> Int {
        OttoAura.level(from: days.map { day($0) }, today: day(today), calendar: cal)
    }

    func test_aNewPersonMeetsCuriousOttoNotASadOne() {
        XCTAssertEqual(OttoAura.level(from: [], today: day(10), calendar: cal), 40)
        XCTAssertEqual(OttoAura.stage(from: [], today: day(10), calendar: cal), .curious)
    }

    func test_theFirstSessionLiftsHimToProgressing() {
        XCTAssertEqual(level([10], today: 10), 50)
        XCTAssertEqual(OttoAura.Stage(level: 50), .progressing)
    }

    func test_fiveDaysInARowReachEnlightened() {
        XCTAssertEqual(level([6, 7, 8, 9, 10], today: 10), 90)
        XCTAssertEqual(OttoAura.Stage(level: 90), .enlightened)
    }

    func test_itNeverPassesOneHundred() {
        XCTAssertEqual(level(Array(1...12), today: 12), 100)
    }

    /// Today is not over, so not having sat yet costs nothing.
    func test_anUnfinishedTodayIsNotAMissedDay() {
        XCTAssertEqual(level([8, 9], today: 10), 60)
    }

    func test_oneMissedDayIsARestDayAndFree() {
        XCTAssertEqual(level([8, 10], today: 10), 60)
    }

    func test_theSecondMissedDayCostsTwenty() {
        // 40 +10 (7) = 50; 8 rest; 9 costs 20 = 30; +10 (10) = 40.
        XCTAssertEqual(level([7, 10], today: 10), 40)
    }

    func test_aWeekAwayFromEnlightenedBringsHimToLow() {
        // Enlightened by the 5th, then seven days missed (one rest, six at 20).
        let away = level([1, 2, 3, 4, 5], today: 13)
        XCTAssertEqual(away, 0)
        XCTAssertEqual(OttoAura.Stage(level: away), .low)
    }

    func test_itNeverFallsBelowZero() {
        XCTAssertEqual(level([1], today: 28), 0)
    }

    func test_twoSessionsOnOneDayCountOnce() {
        let dates = [day(10, 8), day(10, 20)]
        XCTAssertEqual(OttoAura.level(from: dates, today: day(10), calendar: cal), 50)
    }

    /// One rest day a week, the streak's spacing: a second single miss inside
    /// seven days costs, one a week later is free again.
    func test_restDaysComeOncePerSevenDays() {
        // 1 +10=50; 2 rest; 3 +10=60; 4 missed within the week: -20=40; 5 +10=50.
        XCTAssertEqual(level([1, 3, 5], today: 5), 50)
        // 1 +10=50; 2 rest; 3..8 +60 capped=100; 9 rest again (7 days on); 10 +10.
        XCTAssertEqual(level([1, 3, 4, 5, 6, 7, 8, 10], today: 10), 100)
        // 1..5 = 80 with 2 as the rest; 6 and 7 missed inside the week: -40; 8 +10.
        XCTAssertEqual(level([1, 3, 4, 5, 8], today: 8), 50)
    }

    func test_stageBoundaries() {
        let cases: [(Int, OttoAura.Stage)] = [
            (0, .low), (9, .low), (10, .frustrated), (29, .frustrated),
            (30, .curious), (49, .curious), (50, .progressing), (69, .progressing),
            (70, .inFlow), (89, .inFlow), (90, .enlightened), (100, .enlightened),
        ]
        for (value, stage) in cases {
            XCTAssertEqual(OttoAura.Stage(level: value), stage, "level \(value)")
        }
    }
}
