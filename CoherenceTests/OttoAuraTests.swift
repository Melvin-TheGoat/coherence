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

    /// Twenty minutes a sit (+10, the old flat daily gain), for tests that
    /// are really about misses, rests or "Not now" and just need "a day
    /// meditated" rather than any particular length.
    private func asSits(_ dates: [Date], minutes: Double = 20) -> [OttoAura.Sit] {
        dates.map { OttoAura.Sit(date: $0, seconds: Int(minutes * 60)) }
    }

    private func level(_ days: [Int], today: Int) -> Int {
        OttoAura.level(from: asSits(days.map { day($0) }), today: day(today), calendar: cal)
    }

    /// Everyone starts at 50, in Steady, his colour already in (Melvin,
    /// 2026-09-29: "have otto start at 50% for everyone"; it was 40, in
    /// Stirring, before).
    func test_aNewPersonMeetsSteadyOttoNotAWitheredOne() {
        XCTAssertEqual(OttoAura.startLevel, 50)
        XCTAssertEqual(OttoAura.level(from: [], today: day(10), calendar: cal), 50)
        XCTAssertEqual(OttoAura.stage(from: [], today: day(10), calendar: cal), .steady)
    }

    /// A twenty-minute first session (+10) lifts him from Steady to Bright;
    /// a ten-minute one (+5) keeps him Steady, a little brighter.
    func test_aTwentyMinuteFirstSessionLiftsHimToBright() {
        XCTAssertEqual(level([10], today: 10), 60)
        XCTAssertEqual(OttoAura.Stage(level: 60), .bright)
        let ten = OttoAura.level(from: asSits([day(10)], minutes: 10), today: day(10), calendar: cal)
        XCTAssertEqual(ten, 55)
        XCTAssertEqual(OttoAura.Stage(level: ten), .steady)
    }

    /// 50 +10 a day: four twenty-minute days reach 90, Nirvana, and a fifth
    /// takes him to the cap.
    func test_fourDaysInARowReachNirvana() {
        XCTAssertEqual(level([7, 8, 9], today: 9), 80)
        XCTAssertEqual(OttoAura.Stage(level: 80), .radiant)
        XCTAssertEqual(level([7, 8, 9, 10], today: 10), 90)
        XCTAssertEqual(OttoAura.Stage(level: 90), .nirvana)
        XCTAssertEqual(level([6, 7, 8, 9, 10], today: 10), 100)
    }

    func test_itNeverPassesOneHundred() {
        XCTAssertEqual(level(Array(1...12), today: 12), 100)
    }

    /// Today is not over, so not having sat yet costs nothing.
    func test_anUnfinishedTodayIsNotAMissedDay() {
        // 50 +10 (8) +10 (9) = 70; today (10) not sat yet costs nothing.
        XCTAssertEqual(level([8, 9], today: 10), 70)
    }

    func test_oneMissedDayIsARestDayAndFree() {
        // 50 +10 (8) = 60; 9 is the rest day; +10 (10) = 70.
        XCTAssertEqual(level([8, 10], today: 10), 70)
    }

    /// Two days missed in a row: the streak forgives neither (it only
    /// forgives a LONE missed day), so the first costs 10 and the second 15.
    /// This pinned 45 before 2026-09-28, when the glow spent the rest day on
    /// the first day of any gap while the streak broke; the two disagreed.
    func test_theSecondMissedDayInARowCostsFifteen() {
        // 50 +10 (7) = 60; 8 -10; 9 -15 = 35; +10 (10) = 45.
        XCTAssertEqual(level([7, 10], today: 10), 45)
    }

    /// Melvin and Aziz, 2026-09-23: "first day missed -10, second day in a
    /// row missed -15, then -20 for third etc."
    func test_missedDaysCostMoreTheLongerTheRun() {
        XCTAssertEqual((1...5).map { OttoAura.missCost(run: $0) }, [10, 15, 20, 25, 30])
        // 100 by the 5th (50 +10 a day), still 100 on the 6th; 7 -10 (the
        // streak broke, so no rest day) = 90; 8 -15 = 75; 9 -20 = 55; 10 -25
        // = 30; today (11) unfinished.
        XCTAssertEqual(level([1, 2, 3, 4, 5, 6], today: 11), 30)
    }

    /// A day meditated ends the run: the next miss is a first miss again.
    func test_meditatingStartsTheRunOver() {
        // 1..5 = 100 (capped); 6 -10, 7 -15 = 75 (two in a row, no rest
        // day); 8 +10 = 85; 9 is a lone miss in a new run, forgiven as its
        // rest day; 10 +10 = 95.
        XCTAssertEqual(level([1, 2, 3, 4, 5, 8, 10], today: 10), 95)
    }

    func test_aWeekAwayFromNirvanaBringsHimToWithered() {
        // 100 by the 5th, then seven days missed (6 to 12): 10, 15, 20, 25
        // and 30 already take him to 0 by the 10th; 35 and 40 find nothing
        // left.
        let away = level([1, 2, 3, 4, 5], today: 13)
        XCTAssertEqual(away, 0)
        XCTAssertEqual(OttoAura.Stage(level: away), .withered)
    }

    func test_itNeverFallsBelowZero() {
        XCTAssertEqual(level([1], today: 28), 0)
    }

    /// Two ten-minute sits on one day sum to twenty minutes BEFORE the curve
    /// runs, so they earn what one twenty-minute sit does, not twice a
    /// ten-minute gain and not two separate days' worth.
    func test_twoSessionsOnOneDayCountOnce() {
        let sits = [OttoAura.Sit(date: day(10, 8), seconds: 10 * 60),
                    OttoAura.Sit(date: day(10, 20), seconds: 10 * 60)]
        XCTAssertEqual(OttoAura.level(from: sits, today: day(10), calendar: cal), 60)
    }

    /// One rest day a week, the streak's spacing: a second single miss inside
    /// seven days costs, one a week later is free again.
    func test_restDaysComeOncePerSevenDays() {
        // 1 +10=60; 2 rest; 3 +10=70; 4 missed within the week, a first miss:
        // -10=60; 5 +10=70.
        XCTAssertEqual(level([1, 3, 5], today: 5), 70)
        // 1 +10=60; 2 rest; 3..8 +60 capped=100; 9 rest again (7 days on); 10 +10.
        // At the cap this cannot tell a forgiven 9 from a charged one
        // (100 -10 +10 is 100 too), so the two-minute run below does.
        XCTAssertEqual(level([1, 3, 4, 5, 6, 7, 8, 10], today: 10), 100)
        // Two minutes a day (+1): 1 = 51; 2 rest; 3..8 = 57; 9 forgiven
        // seven days after 2 = 57; 10 = 58. Charged, 9 would leave 48.
        let small = asSits([1, 3, 4, 5, 6, 7, 8, 10].map { day($0) }, minutes: 2)
        XCTAssertEqual(OttoAura.level(from: small, today: day(10), calendar: cal), 58)
        // 1..5 = 90 with 2 as the rest; 6 and 7 missed inside the week: -10
        // then -15 = 65; 8 +10 = 75.
        XCTAssertEqual(level([1, 3, 4, 5, 8], today: 8), 75)
    }

    /// The glow forgives exactly the days the streak forgives (2026-09-28).
    /// Practice on 1, 4 and 6: the streak breaks over 2 and 3 and bridges 5
    /// as a rest day, its weekly allowance starting over with the new run.
    /// The glow used to spend its rest day on day 2 and then charge day 5.
    func test_theGlowForgivesTheDaysTheStreakForgives() {
        let dates = [1, 4, 6].map { day($0) }
        let runs = StreakCalculator.runs(from: dates, calendar: cal)
        XCTAssertEqual(runs.flatMap(\.restDays), [cal.startOfDay(for: day(5))])
        // 1 +10 = 60; 2 -10; 3 -15 = 35; 4 +10 = 45; 5 rest; 6 +10 = 55.
        XCTAssertEqual(level([1, 4, 6], today: 6), 55)
        // While yesterday is the streak's rest day, the glow does not charge it.
        XCTAssertTrue(StreakCalculator.streak(from: [day(8)], today: day(10), calendar: cal).restDayUsed)
        XCTAssertEqual(level([8], today: 10), 60)
    }

    // MARK: - Length-based gain (Melvin, 2026-09-28)

    /// Melvin's own examples, pinned exactly: "2 minutes or less is 1%, 4
    /// minutes or less is 2%. 10 minutes is 5%. 20 minutes is 10%. 40
    /// minutes is like 15%, 60+ minutes is 20%."
    func test_gain_pinnedAtMelvinsExamplesAndBoundaries() {
        XCTAssertEqual(OttoAura.gain(minutes: 1), 1)
        XCTAssertEqual(OttoAura.gain(minutes: 2), 1)
        XCTAssertEqual(OttoAura.gain(minutes: 3), 2)
        XCTAssertEqual(OttoAura.gain(minutes: 4), 2)
        XCTAssertEqual(OttoAura.gain(minutes: 10), 5)
        XCTAssertEqual(OttoAura.gain(minutes: 20), 10)
        XCTAssertEqual(OttoAura.gain(minutes: 21), 11)
        XCTAssertEqual(OttoAura.gain(minutes: 40), 15)
        XCTAssertEqual(OttoAura.gain(minutes: 59), 20)
        XCTAssertEqual(OttoAura.gain(minutes: 60), 20)
        XCTAssertEqual(OttoAura.gain(minutes: 120), 20)
    }

    func test_gain_nothingForZeroOrLessMinutes() {
        XCTAssertEqual(OttoAura.gain(minutes: 0), 0)
        XCTAssertEqual(OttoAura.gain(minutes: -5), 0)
    }

    /// A day's sessions are summed into one minute total before the curve
    /// runs: two ten-minute sits earn exactly what one twenty-minute sit
    /// does, never twice a ten-minute gain.
    func test_gain_perDaySumNotPerSession() {
        let twoTens = [OttoAura.Sit(date: day(10, 8), seconds: 10 * 60),
                       OttoAura.Sit(date: day(10, 20), seconds: 10 * 60)]
        let oneTwenty = [OttoAura.Sit(date: day(10, 8), seconds: 20 * 60)]
        let fromTwo = OttoAura.level(from: twoTens, today: day(10), calendar: cal)
        let fromOne = OttoAura.level(from: oneTwenty, today: day(10), calendar: cal)
        XCTAssertEqual(fromTwo, fromOne)
        XCTAssertEqual(fromTwo, 60)
    }

    /// Three thirty-minute sits in a day sum to ninety minutes, well past
    /// the hour cap, so the day is still worth only +20.
    func test_gain_perDaySumCapsAtTwenty() {
        let threeThirties = (0..<3).map { OttoAura.Sit(date: day(10, 8 + $0 * 4), seconds: 30 * 60) }
        XCTAssertEqual(OttoAura.level(from: threeThirties, today: day(10), calendar: cal), 70)
    }

    /// `ContentView.celebrate(_:)` computes before/after this exact way: the
    /// level WITHOUT the landed session against the level WITH it. A second
    /// session on an already-practised day must show only the marginal gain
    /// the extra minutes buy, not a fresh day's worth.
    func test_aSecondSessionOnTheSameDayShowsOnlyTheMarginalGain() {
        let first = OttoAura.Sit(date: day(10, 8), seconds: 10 * 60)
        let second = OttoAura.Sit(date: day(10, 20), seconds: 10 * 60)
        let before = OttoAura.level(from: [first], today: day(10), calendar: cal)
        let after = OttoAura.level(from: [first, second], today: day(10), calendar: cal)
        // 10 min alone is +5 (55); the two together sum to 20 min, +10 (60).
        XCTAssertEqual(before, 55)
        XCTAssertEqual(after, 60)
        XCTAssertEqual(after - before, 5, "the second ten minutes only buys the marginal five")
    }

    // MARK: - "Not now" (Melvin, 2026-09-22)

    /// A window Otto held apps in, opening at `h` o'clock on day `d`.
    private func window(_ d: Int, from h: Int, hours: Double) -> DateInterval {
        DateInterval(start: day(d, h), duration: hours * 3600)
    }

    /// "Not now", then a session ten minutes later: nothing lost.
    func test_notNowThenMeditatingInsideTheWindowCostsNothing() {
        let sits = asSits([day(8), day(9), day(10, 8)])
        let morning = [window(10, from: 6, hours: 4)]
        // 50 +10 (8) +10 (9) +10 (10), the 10th's session inside the window.
        XCTAssertEqual(OttoAura.level(from: sits, notNow: morning, today: day(10), calendar: cal), 80)
    }

    /// Melvin's formula: glow lost = 20 × hours held / 24.
    func test_aSkippedWindowCostsInProportionToHowLongTheAppsWereHeld() {
        XCTAssertEqual(OttoAura.skipCost(for: window(9, from: 0, hours: 24)), 20, accuracy: 0.0001)
        XCTAssertEqual(OttoAura.skipCost(for: window(9, from: 0, hours: 12)), 10, accuracy: 0.0001)
        XCTAssertEqual(OttoAura.skipCost(for: window(9, from: 0, hours: 3)), 2.5, accuracy: 0.0001)
        XCTAssertEqual(OttoAura.skipCost(for: window(9, from: 0, hours: 1)), 20.0 / 24, accuracy: 0.0001)

        // Sessions every evening, so each held window closes empty and only
        // the window moves the number: 80 without one (50 +10 +10 +10).
        let evenings = asSits([day(8, 20), day(9, 20), day(10, 20)])
        func held(_ hours: Double) -> Int {
            OttoAura.level(from: evenings, notNow: [window(9, from: 0, hours: hours)],
                           today: day(10, 21), calendar: cal)
        }
        XCTAssertEqual(held(12), 70)   // -10
        XCTAssertEqual(held(6), 75)    // -5
        XCTAssertEqual(held(1), 79)    // -0.83, 79.17 rounds to 79
    }

    /// The whole day held and skipped costs 20, and the rest day does not
    /// cover it: it forgives the missed day, never the "Not now".
    func test_aSkippedMindfulDayCostsTwentyEvenOnARestDay() {
        // 7 = 60, 8 = 70, 9 rest, 10 = 80.
        XCTAssertEqual(level([7, 8, 10], today: 10), 80)
        // The same days with the 9th held and skipped: 70 -20 = 50, 10 = 60.
        let mindfulDay = [window(9, from: 0, hours: 24)]
        XCTAssertEqual(OttoAura.level(from: asSits([day(7), day(8), day(10)]), notNow: mindfulDay,
                                      today: day(10), calendar: cal), 60)
    }

    /// A missed day and its skipped windows are never added together: the
    /// day costs whichever is larger, and its windows at most 20.
    func test_aMissedDayAndItsWindowsAreNeverAddedTogether() {
        let both = [window(9, from: 0, hours: 24), window(9, from: 21, hours: 3)]
        // 7 +10 = 60; 8 -10 (a first miss, no rest across two days) = 50;
        // day 9 is the second missed day (15) with 20 of windows: 20, not
        // 35, so 30; then 10 +10 = 40.
        XCTAssertEqual(OttoAura.level(from: asSits([day(7), day(10)]), notNow: both,
                                      today: day(10), calendar: cal), 40)
        // On a rest day the two windows are capped at 20 together: 7 = 60,
        // 8 = 70, 9 -20 = 50, 10 = 60.
        XCTAssertEqual(OttoAura.level(from: asSits([day(7), day(8), day(10)]), notNow: both,
                                      today: day(10), calendar: cal), 60)
    }

    func test_aWindowCostsOnlyOnceItHasClosed() {
        let morning = [window(10, from: 6, hours: 4)]
        let before = [day(8), day(9)]
        // 8 o'clock: still open, nothing lost yet (50 +10 +10).
        XCTAssertEqual(OttoAura.level(from: asSits(before), notNow: morning, today: day(10, 8), calendar: cal), 70)
        // Noon: closed with no session, 20 × 4 / 24 = 3.3 gone: 66.7.
        XCTAssertEqual(OttoAura.level(from: asSits(before), notNow: morning, today: day(10, 12), calendar: cal), 67)
        // Meditating that evening still lifts him; the morning still cost:
        // 70 +10 -3.3 = 76.7.
        XCTAssertEqual(OttoAura.level(from: asSits(before + [day(10, 18)]), notNow: morning,
                                      today: day(10, 19), calendar: cal), 77)
    }

    /// Someone who set Otto to hold their apps has started, meditated or not.
    func test_aSkippedWindowCountsBeforeTheFirstSession() {
        // The 9th, held all day and skipped, is a first missed day with 20 of
        // windows (no session anywhere, so no rest day): 50 -20 = 30.
        let level = OttoAura.level(from: [], notNow: [window(9, from: 0, hours: 24)],
                                   today: day(10), calendar: cal)
        XCTAssertEqual(level, 30)
        XCTAssertEqual(OttoAura.Stage(level: level), .stirring)
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

    // MARK: - The thirteen drawings (Melvin, 2026-09-23)

    /// The level moves in tens, so 0, 10 ... 100 are where it sits; each gets
    /// a drawing of its own.
    func test_everyLevelPeopleLandOnGetsItsOwnDrawing() {
        let grid = stride(from: 0, through: 100, by: 10).map { OttoAura.look(level: $0) }
        XCTAssertEqual(grid, [1, 2, 3, 4, 5, 7, 8, 9, 11, 12, 13])
    }

    func test_theDrawingKeepsTheStagesPromises() {
        XCTAssertEqual(OttoAura.look(level: 50), OttoAura.Stage.steady.look, "everyone starts on Steady's own drawing")
        XCTAssertGreaterThan(OttoAura.look(level: 60), OttoAura.look(level: 50),
                             "a twenty-minute first session changes the drawing")
        XCTAssertEqual(OttoAura.look(level: 0), OttoAura.Stage.withered.look)
        XCTAssertEqual(OttoAura.look(level: 100), OttoAura.Stage.nirvana.look)
    }

    func test_allThirteenDrawingsAreReachableInOrder() {
        let looks = (0...100).map { OttoAura.look(level: $0) }
        XCTAssertEqual(looks, looks.sorted())
        XCTAssertEqual(Set(looks), Set(1...13))
    }

    func test_theDrawingIsNeverMoreThanHalfAStepFromTheStage() {
        for level in 0...100 {
            let own = OttoAura.Stage(level: level).look
            XCTAssertLessThanOrEqual(abs(OttoAura.look(level: level) - own), 1, "level \(level)")
        }
    }

    // MARK: - dateStageFirstReached (2026-09-28, the aura awards)

    /// Matches `level`'s own history exactly: five twenty-minute days in a
    /// row reach Bright on day one and Nirvana on day four, the same numbers
    /// `test_aTwentyMinuteFirstSessionLiftsHimToBright` and
    /// `test_fourDaysInARowReachNirvana` already pin. He starts Steady, and
    /// the walk only checks after a day's gain, so Steady's date is simply
    /// the first session's.
    func test_dateStageFirstReachedMatchesTheLevelHistory() {
        // 50 start (Steady); day6 +10=60 (Bright); day7=70; day8=80
        // (Radiant); day9=90 (Nirvana); day10=100.
        let sits = asSits([6, 7, 8, 9, 10].map { day($0) })
        XCTAssertEqual(OttoAura.dateStageFirstReached(.steady, from: sits, calendar: cal),
                       day(6, 0))
        XCTAssertEqual(OttoAura.dateStageFirstReached(.bright, from: sits, calendar: cal),
                       day(6, 0))
        XCTAssertEqual(OttoAura.dateStageFirstReached(.radiant, from: sits, calendar: cal),
                       day(8, 0))
        XCTAssertEqual(OttoAura.dateStageFirstReached(.nirvana, from: sits, calendar: cal),
                       day(9, 0))
    }

    func test_dateStageFirstReachedIsNilWhenTheStageWasNeverReached() {
        XCTAssertNil(OttoAura.dateStageFirstReached(.nirvana, from: asSits([day(1)]), calendar: cal))
        XCTAssertNil(OttoAura.dateStageFirstReached(.steady, from: [], calendar: cal))
    }

    /// A later dip cannot take the date away: it stays whatever it was the
    /// moment it first happened, the same "did this ever happen" rule as
    /// every other award, and it needs no "today" to know that.
    func test_dateStageFirstReachedSurvivesALaterDip() {
        // Nirvana on day 9 (50 +40); a gap and a low restart afterward must
        // not move that earlier date.
        let sits = asSits([6, 7, 8, 9, 10].map { day($0) } + [day(30)])
        XCTAssertEqual(OttoAura.dateStageFirstReached(.nirvana, from: sits, calendar: cal),
                       day(9, 0))
    }

    // MARK: - 1.1 starts the glow fresh (Melvin, 2026-09-29)

    /// Sessions before `since` are not counted; one after it is.
    func test_sinceExcludesSessionsBeforeIt() {
        let since = day(8, 0)
        let sits = asSits([1, 2, 3, 4, 5, 10].map { day($0) })
        // Only the 10th counts: 50 +10.
        XCTAssertEqual(OttoAura.level(from: sits, since: since, today: day(10), calendar: cal), 60)
        // Without it, the old run (100 by the 5th) and the four days missed
        // after it (10 + 15 + 20 + 25) are all read: 30, then +10.
        XCTAssertEqual(OttoAura.level(from: sits, today: day(10), calendar: cal), 40)
    }

    /// A session at `since` itself counts, and so does one earlier the same
    /// day, because the stored start is that day's midnight.
    func test_sinceCountsTheWholeFirstDay() {
        let sits = asSits([day(8, 6)])
        XCTAssertEqual(OttoAura.level(from: sits, since: day(8, 0), today: day(8), calendar: cal), 60)
        XCTAssertEqual(OttoAura.level(from: asSits([day(8, 0)]), since: day(8, 0),
                                      today: day(8), calendar: cal), 60)
    }

    /// "Not now" windows that opened before `since` are not counted either,
    /// even one that closes after it (a window belongs to the day it opened);
    /// one that opens after it still costs.
    func test_sinceExcludesNotNowWindowsBeforeIt() {
        let since = day(8, 0)
        let sits = asSits([day(10)])
        let early = [window(3, from: 0, hours: 24)]
        // Only the 10th counts: 60.
        XCTAssertEqual(OttoAura.level(from: sits, notNow: early, since: since,
                                      today: day(10), calendar: cal), 60)
        // Without `since` the 3rd starts the history: -20 = 30, then 4 to 9
        // missed (15, 20, 25 ... hits 0), then +10.
        XCTAssertEqual(OttoAura.level(from: sits, notNow: early, today: day(10), calendar: cal), 10)
        // Opened at 22:00 on the 7th, closed at 02:00 on the 8th: before.
        let straddling = [window(7, from: 22, hours: 4)]
        XCTAssertEqual(OttoAura.level(from: sits, notNow: straddling, since: since,
                                      today: day(10), calendar: cal), 60)
        // The 9th, held all day and skipped, after `since`: a first missed
        // day with 20 of windows, 50 -20 = 30, then +10.
        let after = [window(9, from: 0, hours: 24)]
        XCTAssertEqual(OttoAura.level(from: sits, notNow: after, since: since,
                                      today: day(10), calendar: cal), 40)
    }

    /// Someone updating from 1.0 meets Otto at exactly 50, however their old
    /// history ended, as long as they have not sat since.
    func test_aLongHistoryBeforeSinceAndNothingAfterSitsAtFifty() {
        let since = day(25, 0)
        // A long, strong run: 100 at the time.
        let strong = asSits((1...20).map { day($0) })
        let fresh = OttoAura.level(from: strong, since: since, today: day(28), calendar: cal)
        XCTAssertEqual(fresh, 50)
        XCTAssertEqual(OttoAura.Stage(level: fresh), .steady)
        // A history that had left him withered: 0 without `since`, 50 with it.
        let lapsed = asSits([day(1)])
        XCTAssertEqual(OttoAura.level(from: lapsed, today: day(28), calendar: cal), 0)
        XCTAssertEqual(OttoAura.level(from: lapsed, since: since, today: day(28), calendar: cal), 50)
    }

    /// The glow's start is written once, at midnight of the first launch,
    /// and never moved by a later launch.
    func test_markGlowStartWritesMidnightOnceAndNeverOverwrites() {
        let suite = "OttoAuraTests.glowStart.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // The key is load-bearing: renaming it would start everyone over.
        XCTAssertEqual(OttoAura.glowStartKey, "otto.glowStartedOn.v1")
        XCTAssertNil(OttoAura.glowStart(defaults: defaults))

        OttoAura.markGlowStartIfNeeded(now: day(10, 15), calendar: cal, defaults: defaults)
        XCTAssertEqual(OttoAura.glowStart(defaults: defaults), day(10, 0))
        XCTAssertEqual(defaults.object(forKey: OttoAura.glowStartKey) as? Date, day(10, 0))

        OttoAura.markGlowStartIfNeeded(now: day(20, 9), calendar: cal, defaults: defaults)
        XCTAssertEqual(OttoAura.glowStart(defaults: defaults), day(10, 0), "a later launch moved the start")

        // A session earlier on the first-launch day still counts.
        let morning = asSits([day(10, 8)])
        XCTAssertEqual(OttoAura.level(from: morning, since: OttoAura.glowStart(defaults: defaults),
                                      today: day(10, 15), calendar: cal), 60)
    }
}
