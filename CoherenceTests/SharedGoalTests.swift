import XCTest
@testable import Coherence

/// Meditating together: the week, the streak, nudges and the reward line.
final class SharedGoalTests: XCTestCase {

    private func days(_ keys: [String], minutes: Int = 10) -> [GoalDay] {
        keys.map { GoalDay(day: $0, minutes: minutes) }
    }

    private func pair(start: String? = "2026-10-15", target: Int = 4, state: GoalPair.State = .active,
                      mine: [String] = [], theirs: [String] = []) -> GoalPair {
        GoalPair(id: "g", partner: "ana", target: target, startDay: start, state: state,
                 myDays: days(mine), theirDays: days(theirs), invitedByMe: true, createdAt: Date())
    }

    // MARK: Day keys

    func test_dayKeysRoundTripAndCount() {
        XCTAssertEqual(DayKey.adding(7, to: "2026-10-15"), "2026-10-22")
        XCTAssertEqual(DayKey.adding(-1, to: "2026-11-01"), "2026-10-31")
        XCTAssertEqual(DayKey.distance(from: "2026-10-15", to: "2026-10-22"), 7)
        // 2026-10-15 is a Thursday (weekday 5).
        XCTAssertEqual(DayKey.weekday("2026-10-15"), 5)
        XCTAssertEqual(GoalDay(encoded: "2026-10-15:23"), GoalDay(day: "2026-10-15", minutes: 23))
        XCTAssertNil(GoalDay(encoded: "nonsense"))
    }

    // MARK: Which sessions count

    func test_onlyMeasuredSessionsOfFiveMinutesCount_andOneDayIsOneDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Detroit")!
        let base = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 8))!
        let sessions: [(startedAt: Date, durationSec: Int, logged: Bool)] = [
            (base, 600, false),                                  // counts
            (base.addingTimeInterval(3_600), 900, false),        // same day: one day, minutes add
            (base.addingTimeInterval(86_400), 240, false),       // under 5 minutes: no
            (base.addingTimeInterval(2 * 86_400), 1_200, true),  // logged by hand: no
            (base.addingTimeInterval(-86_400), 1_200, false),    // before the goal began: no
        ]
        let out = GoalDay.qualifying(from: sessions, since: "2026-10-15",
                                     now: base.addingTimeInterval(3 * 86_400), calendar: cal)
        XCTAssertEqual(out, [GoalDay(day: "2026-10-15", minutes: 25)])
    }

    // MARK: The week starts on the day the goal started

    func test_weekRunsFromTheStartWeekday() {
        let p = pair(start: "2026-10-15") // a Thursday
        let w = p.thisWeek(today: "2026-10-21")!
        XCTAssertEqual(w.first, "2026-10-15")
        XCTAssertEqual(w.last, "2026-10-21") // Wednesday
        XCTAssertEqual(w.daysLeft, 1)
        let next = p.thisWeek(today: "2026-10-22")!
        XCTAssertEqual(next.index, 1)
        XCTAssertEqual(next.first, "2026-10-22")
    }

    func test_countsAndTogether() {
        let p = pair(mine: ["2026-10-15", "2026-10-17"], theirs: ["2026-10-15", "2026-10-16", "2026-10-18"])
        let w = p.thisWeek(today: "2026-10-18")!
        XCTAssertEqual(w.mine, 2)
        XCTAssertEqual(w.theirs, 3)
        XCTAssertEqual(w.together, 5)
        XCTAssertEqual(w.togetherTarget, 8)
        XCTAssertFalse(w.bothDone)
    }

    // MARK: Streak

    func test_firstWeekIsNotZero() {
        let s = pair(mine: ["2026-10-15"]).streak(today: "2026-10-16")!
        XCTAssertTrue(s.isFirstWeek)
        XCTAssertEqual(s.current, 0)
    }

    func test_missedDayNeverBreaks_onlyAMissedWeekDoes() {
        // Weeks 0 and 1 both hit 4 (with days missed in between); week 2 running.
        let w0 = ["2026-10-15", "2026-10-17", "2026-10-19", "2026-10-21"]
        let w1 = ["2026-10-22", "2026-10-24", "2026-10-26", "2026-10-28"]
        let p = pair(mine: w0 + w1, theirs: w0 + w1)
        let running = p.streak(today: "2026-10-30")!
        XCTAssertEqual(running.current, 2)          // the week still running doesn't break it
        XCTAssertFalse(running.isFirstWeek)

        // Week 2 ends with one of us short: the streak is over.
        let after = p.streak(today: "2026-11-06")!
        XCTAssertEqual(after.current, 0)
        XCTAssertEqual(after.best, 2)
    }

    func test_weekDoneEarlyCountsAtOnce() {
        let w0 = ["2026-10-15", "2026-10-16", "2026-10-17", "2026-10-18"]
        let s = pair(mine: w0, theirs: w0).streak(today: "2026-10-18")!
        XCTAssertEqual(s.current, 1)
        XCTAssertFalse(s.isFirstWeek)
    }

    func test_oneSidedWeekDoesNotCount() {
        let w0 = ["2026-10-15", "2026-10-16", "2026-10-17", "2026-10-18"]
        let s = pair(mine: w0, theirs: ["2026-10-15"]).streak(today: "2026-10-23")!
        XCTAssertEqual(s.current, 0)
    }

    // MARK: Nudges

    func test_nudgeNeedsMeToHaveMeditated() {
        let p = pair(mine: ["2026-10-15"], theirs: [])
        XCTAssertEqual(p.canNudge(today: "2026-10-16", alreadyNudged: false), .meditateFirst)
        XCTAssertEqual(p.canNudge(today: "2026-10-15", alreadyNudged: false), .ready)
    }

    func test_nudgeAllowedOnceMyShareIsDone() {
        let mine = ["2026-10-15", "2026-10-16", "2026-10-17", "2026-10-18"]
        XCTAssertEqual(pair(mine: mine).canNudge(today: "2026-10-19", alreadyNudged: false), .ready)
    }

    func test_noNudgeWhenTheyMeditatedOrAlreadyNudgedOrNotRunning() {
        XCTAssertEqual(pair(mine: ["2026-10-16"], theirs: ["2026-10-16"])
            .canNudge(today: "2026-10-16", alreadyNudged: false), .theyMeditated)
        XCTAssertEqual(pair(mine: ["2026-10-16"]).canNudge(today: "2026-10-16", alreadyNudged: true), .alreadyNudged)
        XCTAssertEqual(pair(start: nil, state: .waitingForThem, mine: ["2026-10-16"])
            .canNudge(today: "2026-10-16", alreadyNudged: false), .unavailable)
    }

    // MARK: The reward line

    func test_countedForLine() {
        XCTAssertNil(CountedFor.line([]))
        XCTAssertEqual(CountedFor.line(["Ana"]), "Counted for Ana")
        XCTAssertEqual(CountedFor.line(["Ana", "Daniel"]), "Counted for Ana and Daniel")
        XCTAssertEqual(CountedFor.line(["Ana", "Daniel", "Jo", "Priya"]), "Counted for Ana, Daniel and 2 more")
    }

    func test_copyHasNoEmDashes() {
        for s in [CountedFor.line(["A", "B", "C"]) ?? ""] { XCTAssertFalse(s.contains("\u{2014}")) }
    }
}
