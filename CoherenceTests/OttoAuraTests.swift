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

    func test_aNewPersonMeetsStirringOttoNotAWitheredOne() {
        XCTAssertEqual(OttoAura.level(from: [], today: day(10), calendar: cal), 40)
        XCTAssertEqual(OttoAura.stage(from: [], today: day(10), calendar: cal), .stirring)
    }

    /// The first session is the one that brings his colour back.
    func test_theFirstSessionLiftsHimToSteady() {
        XCTAssertEqual(level([10], today: 10), 50)
        XCTAssertEqual(OttoAura.Stage(level: 50), .steady)
    }

    func test_fiveDaysInARowReachNirvana() {
        XCTAssertEqual(level([6, 7, 8, 9, 10], today: 10), 90)
        XCTAssertEqual(OttoAura.Stage(level: 90), .nirvana)
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

    func test_aWeekAwayFromNirvanaBringsHimToWithered() {
        // Nirvana by the 5th, then seven days missed (one rest, six at 20).
        let away = level([1, 2, 3, 4, 5], today: 13)
        XCTAssertEqual(away, 0)
        XCTAssertEqual(OttoAura.Stage(level: away), .withered)
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

    // MARK: - "Not now" (Melvin, 2026-09-22)

    /// A window Otto held apps in, opening at `h` o'clock on day `d`.
    private func window(_ d: Int, from h: Int, hours: Double) -> DateInterval {
        DateInterval(start: day(d, h), duration: hours * 3600)
    }

    /// "Not now", then a session ten minutes later: nothing lost.
    func test_notNowThenMeditatingInsideTheWindowCostsNothing() {
        let dates = [day(8), day(9), day(10, 8)]
        let morning = [window(10, from: 6, hours: 4)]
        XCTAssertEqual(OttoAura.level(from: dates, notNow: morning, today: day(10), calendar: cal), 70)
    }

    /// Melvin's formula: glow lost = 20 × hours held / 24.
    func test_aSkippedWindowCostsInProportionToHowLongTheAppsWereHeld() {
        XCTAssertEqual(OttoAura.skipCost(for: window(9, from: 0, hours: 24)), 20, accuracy: 0.0001)
        XCTAssertEqual(OttoAura.skipCost(for: window(9, from: 0, hours: 12)), 10, accuracy: 0.0001)
        XCTAssertEqual(OttoAura.skipCost(for: window(9, from: 0, hours: 3)), 2.5, accuracy: 0.0001)
        XCTAssertEqual(OttoAura.skipCost(for: window(9, from: 0, hours: 1)), 20.0 / 24, accuracy: 0.0001)

        // Sessions every evening, so each held window closes empty and only
        // the window moves the number: 70 without one.
        let evenings = [day(8, 20), day(9, 20), day(10, 20)]
        func held(_ hours: Double) -> Int {
            OttoAura.level(from: evenings, notNow: [window(9, from: 0, hours: hours)],
                           today: day(10, 21), calendar: cal)
        }
        XCTAssertEqual(held(12), 60)
        XCTAssertEqual(held(6), 65)
        XCTAssertEqual(held(1), 69)
    }

    /// The whole day held and skipped costs a missed day's 20, and the rest
    /// day does not cover it: it forgives the missed day, never the "Not now".
    func test_aSkippedMindfulDayCostsWhatAMissedDayDoesEvenOnARestDay() {
        XCTAssertEqual(level([7, 8, 10], today: 10), 70)
        let mindfulDay = [window(9, from: 0, hours: 24)]
        XCTAssertEqual(OttoAura.level(from: [day(7), day(8), day(10)], notNow: mindfulDay,
                                      today: day(10), calendar: cal), 50)
    }

    /// Two blockers skipped on one day still cost no more than a missed day.
    func test_noDayCostsMoreThanAMissedDay() {
        let both = [window(9, from: 0, hours: 24), window(9, from: 21, hours: 3)]
        // Day 8 is the rest, so day 9 is a plain missed day: 20 either way.
        XCTAssertEqual(OttoAura.level(from: [day(7), day(10)], notNow: both, today: day(10), calendar: cal), 40)
        // On a rest day the two windows are capped at 20 together.
        XCTAssertEqual(OttoAura.level(from: [day(7), day(8), day(10)], notNow: both, today: day(10), calendar: cal), 50)
    }

    func test_aWindowCostsOnlyOnceItHasClosed() {
        let morning = [window(10, from: 6, hours: 4)]
        let before = [day(8), day(9)]
        // 8 o'clock: still open, nothing lost yet.
        XCTAssertEqual(OttoAura.level(from: before, notNow: morning, today: day(10, 8), calendar: cal), 60)
        // Noon: closed with no session, 20 × 4 / 24 = 3.3 gone.
        XCTAssertEqual(OttoAura.level(from: before, notNow: morning, today: day(10, 12), calendar: cal), 57)
        // Meditating that evening still lifts him; the morning still cost.
        XCTAssertEqual(OttoAura.level(from: before + [day(10, 18)], notNow: morning,
                                      today: day(10, 19), calendar: cal), 67)
    }

    /// Someone who set Otto to hold their apps has started, meditated or not.
    func test_aSkippedWindowCountsBeforeTheFirstSession() {
        let level = OttoAura.level(from: [], notNow: [window(9, from: 0, hours: 24)],
                                   today: day(10), calendar: cal)
        XCTAssertEqual(level, 20)
        XCTAssertEqual(OttoAura.Stage(level: level), .faded)
    }

    func test_stageBoundaries() {
        let cases: [(Int, OttoAura.Stage)] = [
            (0, .withered), (14, .withered), (15, .faded), (29, .faded),
            (30, .stirring), (44, .stirring), (45, .steady), (59, .steady),
            (60, .bright), (74, .bright), (75, .radiant), (89, .radiant),
            (90, .nirvana), (100, .nirvana),
        ]
        for (value, stage) in cases {
            XCTAssertEqual(OttoAura.Stage(level: value), stage, "level \(value)")
        }
    }

    /// Seven drawings, numbered in order, and he floats only at the top two.
    func test_sevenStagesInOrder() {
        XCTAssertEqual(OttoAura.Stage.allCases.map(\.rawValue), Array(1...7))
        XCTAssertEqual(OttoAura.Stage.allCases.filter(\.floats), [.radiant, .nirvana])
    }

    // MARK: - What he says when you tap him (Melvin, 2026-09-22)

    func test_sayings_areTwentyFiveAndNeverRepeat() {
        XCTAssertGreaterThanOrEqual(OttoSayings.all.count, 25)
        XCTAssertEqual(Set(OttoSayings.all).count, OttoSayings.all.count)
    }

    /// The score and the Watch-only mechanism are on their way out, and the
    /// doorway prescribed one technique out of endless ones.
    func test_sayings_neverMentionAScoreADoorwayOrAWatch() {
        for line in OttoSayings.all {
            let lower = line.lowercased()
            for banned in ["score", "doorway", "watch", "heart rate", "measure"] {
                XCTAssertFalse(lower.contains(banned), "\"\(line)\" mentions \(banned)")
            }
        }
    }

    func test_sayings_carryNoEmDashesAndFitTwoLinesOfHisBubble() {
        for line in OttoSayings.all {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"), line)
            // Two lines in his bubble on a 375pt phone; a third runs into
            // the Guide circle on Home.
            XCTAssertLessThanOrEqual(line.count, 74, line)
        }
    }

    /// Each day starts him on a different line, the same one all day, and
    /// every line still comes round.
    func test_sayings_startSomewhereNewEachDayAndKeepEveryLine() {
        let day = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 9))!
        let later = cal.date(byAdding: .hour, value: 10, to: day)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: day)!
        let today = OttoSayings.forDay(day, calendar: cal)
        XCTAssertEqual(today, OttoSayings.forDay(later, calendar: cal))
        XCTAssertNotEqual(today.first, OttoSayings.forDay(tomorrow, calendar: cal).first)
        XCTAssertEqual(today.sorted(), OttoSayings.all.sorted())
    }
}

