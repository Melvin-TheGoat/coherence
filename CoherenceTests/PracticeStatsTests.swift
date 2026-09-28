import XCTest
@testable import Coherence

/// The pure computation behind what a friend's page shows: sessions and
/// minutes this week, the current streak, the total, and the last sit.
/// Deterministic: an explicit `now` and a fixed UTC Gregorian calendar, the
/// same pattern `StreakCalculatorTests` uses, so day boundaries never depend
/// on the test machine's locale.
final class PracticeStatsTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func test_noSessionsIsEmpty() {
        let stats = PracticeStats.compute(from: [], now: day(2026, 1, 10), calendar: cal)
        XCTAssertEqual(stats, .empty)
        XCTAssertEqual(stats.totalSessions, 0)
        XCTAssertNil(stats.lastSessionAt)
    }

    /// A session exactly seven days ago still counts as "this week"; one a
    /// second earlier than that does not.
    func test_sevenDayWindowIsInclusiveAtTheBoundary() {
        let now = day(2026, 1, 10)
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now)!
        let justOutside = sevenDaysAgo.addingTimeInterval(-1)
        let sessions = [(sevenDaysAgo, 600), (justOutside, 600)]
        let stats = PracticeStats.compute(from: sessions, now: now, calendar: cal)
        XCTAssertEqual(stats.sessions7d, 1, "only the one exactly seven days back counts")
        XCTAssertEqual(stats.totalSessions, 2, "both count towards the running total")
    }

    /// Sessions outside the window are excluded from the week's count and
    /// minutes, but not from the total or the last-sat date.
    func test_onlyRecentSessionsCountTowardsTheWeek() {
        let now = day(2026, 1, 10)
        let sessions: [(startedAt: Date, durationSec: Int)] = [
            (day(2026, 1, 9), 600),    // 1 day ago, in the window
            (day(2026, 1, 8), 900),    // 2 days ago, in the window
            (day(2025, 12, 1), 1_200), // over a month ago, outside it
        ]
        let stats = PracticeStats.compute(from: sessions, now: now, calendar: cal)
        XCTAssertEqual(stats.sessions7d, 2)
        XCTAssertEqual(stats.minutes7d, 25, "600 + 900 seconds, in minutes")
        XCTAssertEqual(stats.totalSessions, 3, "the old one still counts towards the total")
    }

    /// A session dated after `now` (a clock skew, or a stale read) never
    /// counts towards the week — the window looks backward only.
    func test_futureDatedSessionIsExcludedFromTheWeek() {
        let now = day(2026, 1, 10)
        let sessions: [(startedAt: Date, durationSec: Int)] = [
            (day(2026, 1, 9), 300),
            (day(2026, 1, 11), 300),   // tomorrow, relative to `now`
        ]
        let stats = PracticeStats.compute(from: sessions, now: now, calendar: cal)
        XCTAssertEqual(stats.sessions7d, 1)
        XCTAssertEqual(stats.totalSessions, 2)
    }

    /// The streak is exactly `StreakCalculator`'s own answer over the same
    /// dates — the headline and a friend's page can never disagree.
    func test_currentStreakMatchesStreakCalculator() {
        let now = day(2026, 1, 10)
        let dates = [day(2026, 1, 8), day(2026, 1, 9), day(2026, 1, 10)]
        let sessions = dates.map { ($0, 300) }
        let stats = PracticeStats.compute(from: sessions, now: now, calendar: cal)
        let expected = StreakCalculator.streak(from: dates, today: now, calendar: cal).current
        XCTAssertEqual(stats.currentStreak, expected)
        XCTAssertEqual(stats.currentStreak, 3)
    }

    /// A broken streak (a gap of two days or more, with no rest day to
    /// bridge it) reads zero, the same rule Home's streak follows.
    func test_brokenStreakReadsZero() {
        let now = day(2026, 1, 10)
        let dates = [day(2026, 1, 1), day(2026, 1, 2)]
        let sessions = dates.map { ($0, 300) }
        let stats = PracticeStats.compute(from: sessions, now: now, calendar: cal)
        XCTAssertEqual(stats.currentStreak, 0)
    }

    /// `lastSessionAt` is the most recent start, whatever order the sessions
    /// arrive in.
    func test_lastSessionAtIsTheMostRecentStart() {
        let sessions: [(startedAt: Date, durationSec: Int)] = [
            (day(2026, 1, 3), 300),
            (day(2026, 1, 9), 300),
            (day(2026, 1, 5), 300),
        ]
        let stats = PracticeStats.compute(from: sessions, now: day(2026, 1, 10), calendar: cal)
        XCTAssertEqual(stats.lastSessionAt, day(2026, 1, 9))
    }

    /// Two sessions in one day both count towards the week and the total —
    /// unlike the streak, which counts days, this counts sessions.
    func test_sameDaySessionsBothCount() {
        let now = day(2026, 1, 10, 23)
        let sessions: [(startedAt: Date, durationSec: Int)] = [
            (day(2026, 1, 10, 8), 300),
            (day(2026, 1, 10, 20), 300),
        ]
        let stats = PracticeStats.compute(from: sessions, now: now, calendar: cal)
        XCTAssertEqual(stats.sessions7d, 2)
        XCTAssertEqual(stats.totalSessions, 2)
    }
}
