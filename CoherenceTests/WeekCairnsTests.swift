import XCTest
// WeekCairns is compiled into this test target via Shared/ (see project.yml).

/// Deterministic tests — explicit `today` and a fixed UTC Gregorian calendar,
/// like `StreakCalculatorTests`, so day boundaries never depend on the test
/// machine's locale.
final class WeekCairnsTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func fact(_ date: Date, minutes: Int) -> WeekCairns.SessionFact {
        WeekCairns.SessionFact(startedAt: date, durationSec: minutes * 60)
    }

    func test_emptyHistoryIsSevenBareDays() {
        let week = WeekCairns.week(from: [], today: day(2026, 1, 10), calendar: cal)
        XCTAssertEqual(week.count, 7)
        XCTAssertTrue(week.allSatisfy { $0.sessionMinutes.isEmpty && !$0.isRestDay })
        XCTAssertEqual(week.last?.date, cal.startOfDay(for: day(2026, 1, 10)))
        XCTAssertTrue(week.last!.isToday)
        XCTAssertFalse(week.dropLast().contains { $0.isToday })
    }

    /// The strip ends TODAY, not the calendar week — day 0 is six days back,
    /// day 6 is today, whatever weekday that is.
    func test_rollingSevenDaysEndingToday() {
        let week = WeekCairns.week(from: [], today: day(2026, 1, 10), calendar: cal)
        let expectedFirst = cal.startOfDay(for: day(2026, 1, 4))
        XCTAssertEqual(week.first?.date, expectedFirst)
    }

    /// Two sessions the same day are two stones, both there, oldest first.
    func test_twoSessionsSameDayAreTwoStones() {
        let sessions = [fact(day(2026, 1, 10, 8), minutes: 12), fact(day(2026, 1, 10, 20), minutes: 30)]
        let week = WeekCairns.week(from: sessions, today: day(2026, 1, 10), calendar: cal)
        XCTAssertEqual(week.last?.sessionMinutes, [12, 30])
        XCTAssertEqual(week.last?.sessionCount, 2)
    }

    /// A session under a minute still stacks a stone — `MinutesPuck`'s own
    /// floor of at least 1 shown minute, so the same session reads the same
    /// length everywhere.
    func test_shortSessionFloorsToOneMinute() {
        let sessions = [fact(day(2026, 1, 10), minutes: 0)]
        let week = WeekCairns.week(from: sessions, today: day(2026, 1, 10), calendar: cal)
        XCTAssertEqual(week.last?.sessionMinutes, [1])
    }

    /// A forgiven rest day (missed, bridging a run) draws a leaf. Must agree
    /// with `StreakCalculator`: the same history reports a live 3-day streak
    /// with a rest day used.
    func test_forgivenRestDayIsMarked() {
        let sessions = [fact(day(2026, 1, 6), minutes: 10),
                        fact(day(2026, 1, 7), minutes: 10),
                        // 1/8 missed, forgiven
                        fact(day(2026, 1, 9), minutes: 10)]
        let week = WeekCairns.week(from: sessions, today: day(2026, 1, 9), calendar: cal)
        let missed = week.first { cal.isDate($0.date, inSameDayAs: day(2026, 1, 8)) }
        XCTAssertEqual(missed?.isRestDay, true)
        XCTAssertTrue(missed!.sessionMinutes.isEmpty, "a rest day is never a practised day")

        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt),
                                             today: day(2026, 1, 9), calendar: cal)
        XCTAssertEqual(streak.current, 3)
    }

    /// Two missed days in a row break the run — neither draws a leaf.
    func test_twoMissedDaysAreJustEmpty() {
        let sessions = [fact(day(2026, 1, 5), minutes: 10), fact(day(2026, 1, 9), minutes: 10)]
        let week = WeekCairns.week(from: sessions, today: day(2026, 1, 9), calendar: cal)
        for offset in [6, 7] {
            let d = week.first { cal.isDate($0.date, inSameDayAs: day(2026, 1, offset)) }
            XCTAssertEqual(d?.isRestDay, false)
        }
    }

    func test_summarySumsMinutesAndCounts() {
        let sessions = [fact(day(2026, 1, 8), minutes: 10),
                        fact(day(2026, 1, 9, 8), minutes: 5), fact(day(2026, 1, 9, 20), minutes: 20)]
        let week = WeekCairns.week(from: sessions, today: day(2026, 1, 9), calendar: cal)
        let summary = WeekCairns.summary(week)
        XCTAssertEqual(summary.sessions, 3)
        XCTAssertEqual(summary.minutes, 35)
    }
}
