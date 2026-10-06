import XCTest

/// Block's rules (`Shared/Block/BlockModel.swift`), pinned to Melvin's
/// decisions of 2026-09-22. A fixed UTC calendar; 10 March 2026 is a Tuesday.
final class BlockRulesTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h, minute: m))!
    }

    private func on(_ kind: BlockerKind) -> Blocker {
        var b = Blocker.preset(kind)
        b.isOn = true
        b.hasApps = true
        return b
    }

    private func state(_ blockers: Blocker...) -> BlockState {
        BlockState(blockers: blockers)
    }

    // MARK: - Holding and releasing

    func test_mindfulDayHoldsAllDayUntilASession() {
        let day = on(.mindfulDay)
        var s = state(day)
        XCTAssertTrue(BlockRules.holds(day, in: s, at: at(10, 9), calendar: cal))
        BlockRules.recordSession(endingAt: at(10, 10), durationSec: 300, in: &s, calendar: cal)
        XCTAssertFalse(BlockRules.holds(day, in: s, at: at(10, 10, 1), calendar: cal))
        XCTAssertFalse(BlockRules.holds(day, in: s, at: at(10, 23), calendar: cal))
        // A new day is a new window.
        XCTAssertTrue(BlockRules.holds(day, in: s, at: at(11, 1), calendar: cal))
    }

    /// Aziz, 2026-10-01: a session just after midnight opened Mindful day,
    /// then deleting the account erased the session, and the apps stayed
    /// open all day with "Open, you meditated" and no session anywhere.
    func test_aDeletedSessionTakesItsOpeningBack() {
        let day = on(.mindfulDay)
        var s = state(day)
        let kept = at(9, 20), deleted = at(10, 0, 13)
        BlockRules.recordSession(endingAt: kept, durationSec: 600, in: &s, calendar: cal)
        BlockRules.recordSession(endingAt: deleted, durationSec: 300, in: &s, calendar: cal)
        XCTAssertFalse(BlockRules.holds(day, in: s, at: at(10, 16), calendar: cal))

        let since = at(10, 16).addingTimeInterval(-36 * 3600)
        let forgot = BlockRules.forgetReleases(withoutSessionsEnding: [kept], since: since, in: &s)
        XCTAssertTrue(forgot)
        XCTAssertTrue(BlockRules.holds(day, in: s, at: at(10, 16), calendar: cal), "held again today")
        XCTAssertFalse(BlockRules.holds(day, in: s, at: at(9, 21), calendar: cal),
                       "the session still stored keeps its own day open")

        let again = BlockRules.forgetReleases(withoutSessionsEnding: [kept], since: since, in: &s)
        XCTAssertFalse(again, "nothing left to take back")
    }

    /// Aziz, 2026-09-22: five minutes opens the apps, for every blocker.
    func test_fiveMinutesOpensTheAppsAndLessDoesNot() {
        let day = on(.mindfulDay)
        var s = state(day)
        BlockRules.recordSession(endingAt: at(10, 10), durationSec: 299, in: &s, calendar: cal)
        XCTAssertTrue(BlockRules.holds(day, in: s, at: at(10, 11), calendar: cal))
        BlockRules.recordSession(endingAt: at(10, 12), durationSec: 300, in: &s, calendar: cal)
        XCTAssertFalse(BlockRules.holds(day, in: s, at: at(10, 13), calendar: cal))
    }

    /// Melvin: the rest of the window, not the day, "in case they want to
    /// meditate twice a day".
    func test_aSessionReleasesItsWindowNotTheDay() {
        let morning = on(.mindfulMorning), night = on(.windDown)
        var s = state(morning, night)
        BlockRules.recordSession(endingAt: at(10, 7), durationSec: 300, in: &s, calendar: cal)
        XCTAssertFalse(BlockRules.holds(morning, in: s, at: at(10, 8), calendar: cal))
        XCTAssertTrue(BlockRules.holds(night, in: s, at: at(10, 22), calendar: cal))
    }

    func test_recordingTheSameSessionTwiceReleasesOnce() {
        var s = state(on(.mindfulDay))
        BlockRules.recordSession(endingAt: at(10, 10), durationSec: 300, in: &s, calendar: cal)
        BlockRules.recordSession(endingAt: at(10, 10), durationSec: 300, in: &s, calendar: cal)
        XCTAssertEqual(s.releases.count, 1)
    }

    func test_nothingHoldsWhenOffOrWithoutApps() {
        var off = on(.mindfulDay); off.isOn = false
        var empty = on(.mindfulDay); empty.hasApps = false
        let s = state(off, empty)
        XCTAssertFalse(BlockRules.holds(off, in: s, at: at(10, 9), calendar: cal))
        XCTAssertFalse(BlockRules.holds(empty, in: s, at: at(10, 9), calendar: cal))
    }

    func test_aWindowAcrossMidnightIsStillYesterdays() {
        var late = on(.custom)
        late.window = .hours(start: 22 * 60, end: 2 * 60)
        let s = state(late)
        let window = late.openWindow(at: at(11, 1), calendar: cal)
        XCTAssertEqual(window?.start, at(10, 22))
        XCTAssertEqual(window?.end, at(11, 2))
        XCTAssertTrue(BlockRules.holds(late, in: s, at: at(11, 1), calendar: cal))
        XCTAssertFalse(BlockRules.holds(late, in: s, at: at(11, 3), calendar: cal))
    }

    /// Night owl (`BlockWhen.nightOwlWindow`): 6 pm until 6 am. A session in
    /// the evening opens the apps until the morning, and the next evening
    /// holds them again.
    func test_nightOwlHoldsOvernightAndASessionOpensTheNight() {
        var owl = on(.custom)
        owl.window = .hours(start: 18 * 60, end: 6 * 60)
        var s = state(owl)
        XCTAssertNil(owl.windowProblem)
        XCTAssertFalse(BlockRules.holds(owl, in: s, at: at(10, 12), calendar: cal))
        XCTAssertTrue(BlockRules.holds(owl, in: s, at: at(10, 23), calendar: cal))
        XCTAssertTrue(BlockRules.holds(owl, in: s, at: at(11, 3), calendar: cal))
        BlockRules.recordSession(endingAt: at(10, 20), durationSec: 300, in: &s, calendar: cal)
        XCTAssertFalse(BlockRules.holds(owl, in: s, at: at(11, 3), calendar: cal))
        XCTAssertTrue(BlockRules.holds(owl, in: s, at: at(11, 19), calendar: cal))
    }

    func test_focusHoursRestAtTheWeekend() {
        let focus = on(.focusHours)
        let s = state(focus)
        XCTAssertTrue(BlockRules.holds(focus, in: s, at: at(10, 10), calendar: cal))   // Tuesday
        XCTAssertFalse(BlockRules.holds(focus, in: s, at: at(14, 10), calendar: cal))  // Saturday
        XCTAssertFalse(BlockRules.holds(focus, in: s, at: at(10, 18), calendar: cal))  // after five
    }

    func test_aDailyLimitHoldsOnlyOnceItRunsOut() {
        let limit = on(.dailyLimit)
        var s = state(limit)
        XCTAssertFalse(BlockRules.holds(limit, in: s, at: at(10, 9), calendar: cal))
        BlockRules.recordLimitHit(limit.id, at: at(10, 9), in: &s, calendar: cal)
        XCTAssertTrue(BlockRules.holds(limit, in: s, at: at(10, 9, 1), calendar: cal))
        XCTAssertFalse(BlockRules.holds(limit, in: s, at: at(11, 9), calendar: cal))
    }

    // MARK: - Not now

    func test_notNowOpensTheAppsForThatLong() {
        let day = on(.mindfulDay)
        var s = state(day)
        XCTAssertEqual(BlockRules.takePass(minutes: 10, in: &s, at: at(10, 9), calendar: cal), [day.id])
        XCTAssertFalse(BlockRules.holds(day, in: s, at: at(10, 9, 5), calendar: cal))
        XCTAssertTrue(BlockRules.holds(day, in: s, at: at(10, 9, 11), calendar: cal))
    }

    /// No daily pass limit and no strict mode (Aziz, 2026-09-22): "Not now"
    /// works every time it is asked.
    func test_notNowHasNoDailyLimit() {
        let day = on(.mindfulDay)
        var s = state(day)
        for hour in 8...20 {
            XCTAssertEqual(BlockRules.takePass(minutes: 5, in: &s, at: at(10, hour), calendar: cal), [day.id])
        }
    }

    func test_aPassNeverOutlastsItsWindow() {
        let morning = on(.mindfulMorning)
        var s = state(morning)
        BlockRules.takePass(minutes: 30, in: &s, at: at(10, 9, 55), calendar: cal)
        XCTAssertEqual(s.passes.first?.end, at(10, 10))
    }

    // MARK: - The glow

    func test_aNotNowWindowWithNoSessionReachesTheGlow() {
        let morning = on(.mindfulMorning)
        var s = state(morning)
        BlockRules.takePass(minutes: 10, in: &s, at: at(10, 7), calendar: cal)
        BlockRules.takePass(minutes: 10, in: &s, at: at(10, 8), calendar: cal)
        XCTAssertEqual(BlockRules.notNowWindows(s), [DateInterval(start: at(10, 6), end: at(10, 10))],
                       "one window, however many passes")
        // Coming back to meditate inside the window costs nothing.
        BlockRules.recordSession(endingAt: at(10, 9), durationSec: 300, in: &s, calendar: cal)
        XCTAssertTrue(BlockRules.notNowWindows(s).isEmpty)
    }

    /// The windows go straight into Otto's glow: a skipped Mindful day costs
    /// what a missed day does.
    func test_notNowWindowsPriceThroughOttoAura() {
        let day = on(.mindfulDay)
        var s = state(day)
        BlockRules.takePass(minutes: 5, in: &s, at: at(9, 9), calendar: cal)
        // Twenty minutes a day (+10, the old flat gain), so this test is
        // about the "Not now" pricing rule, not the length curve.
        let sits = [at(7, 12), at(8, 12), at(10, 12)].map { OttoAura.Sit(date: $0, seconds: 20 * 60) }
        let without = OttoAura.level(from: sits, today: at(10, 13), calendar: cal)
        let with = OttoAura.level(from: sits, notNow: BlockRules.notNowWindows(s),
                                  today: at(10, 13), calendar: cal)
        XCTAssertEqual(without - with, 20)
    }

    // MARK: - Asking Otto

    func test_anAskIsUnansweredUntilOttoIsShown() {
        var s = BlockState()
        XCTAssertFalse(BlockRules.unansweredAsk(s, at: at(10, 9)))
        s.asks = [at(10, 9)]
        XCTAssertTrue(BlockRules.unansweredAsk(s, at: at(10, 9, 1)))
        s.lastInterventionAt = at(10, 9, 1)
        XCTAssertFalse(BlockRules.unansweredAsk(s, at: at(10, 9, 2)))
        s.asks.append(at(10, 12))
        XCTAssertFalse(BlockRules.unansweredAsk(s, at: at(10, 12, 10)), "too long ago to still be waiting")
    }

    // MARK: - Words

    func test_scheduleLines() {
        XCTAssertEqual(Blocker.preset(.mindfulDay).scheduleLine(calendar: cal), "All day, every day")
        XCTAssertEqual(Blocker.preset(.mindfulMorning).scheduleLine(calendar: cal), "6 am to 10 am, every day")
        XCTAssertEqual(Blocker.preset(.windDown).scheduleLine(calendar: cal), "9 pm to midnight, every day")
        XCTAssertEqual(Blocker.preset(.focusHours).scheduleLine(calendar: cal), "9 am to 5 pm, weekdays")
        XCTAssertEqual(Blocker.preset(.dailyLimit).scheduleLine(calendar: cal), "After 30 minutes a day, every day")
        var odd = Blocker.preset(.custom)
        odd.weekdays = [1, 2, 4]
        odd.window = .hours(start: 7 * 60 + 30, end: 12 * 60)
        XCTAssertEqual(odd.scheduleLine(calendar: cal), "7:30 am to noon, Mon, Wed, Sun")
    }

    /// "From 8 pm until I meditate" (Aziz, 2026-09-28): held from the start
    /// time to midnight, released by a session like every window, read back
    /// as what was chosen, and a blocker saved before the field loads as a
    /// plain window.
    func test_customUntilIMeditate() throws {
        var b = on(.custom)
        b.window = .hours(start: 20 * 60, end: 24 * 60)
        b.untilSession = true
        XCTAssertNil(b.windowProblem)
        XCTAssertEqual(b.scheduleLine(calendar: cal), "From 8 pm until you meditate, every day")

        // Held from 8 pm until midnight at the latest.
        let s = state(b)
        XCTAssertFalse(BlockRules.holds(b, in: s, at: at(10, 19), calendar: cal))
        XCTAssertTrue(BlockRules.holds(b, in: s, at: at(10, 21), calendar: cal))
        XCTAssertFalse(BlockRules.holds(b, in: s, at: at(11, 0, 30), calendar: cal))

        let saved = try JSONDecoder().decode(Blocker.self, from: JSONEncoder().encode(b))
        XCTAssertEqual(saved.untilSession, true, "survives a save")

        // Wind down is 9 pm to midnight and says so; only a chosen "until I
        // meditate" reads that way.
        XCTAssertEqual(Blocker.preset(.windDown).scheduleLine(calendar: cal), "9 pm to midnight, every day")
    }

    /// "From midnight until I meditate" is saved as midnight to midnight,
    /// the whole day. It was refused as an empty window (start and end the
    /// same clock time), so it could not be saved at all.
    func test_fromMidnightUntilIMeditateCanBeSaved() {
        var b = on(.custom)
        b.window = .hours(start: 0, end: 24 * 60)
        b.untilSession = true
        XCTAssertNil(b.windowProblem)
        XCTAssertEqual(b.scheduleLine(calendar: cal), "From midnight until you meditate, every day")
        let s = state(b)
        XCTAssertTrue(BlockRules.holds(b, in: s, at: at(10, 0, 30), calendar: cal))
        XCTAssertTrue(BlockRules.holds(b, in: s, at: at(10, 23, 50), calendar: cal))
        // A window that really is empty is still refused.
        b.window = .hours(start: 8 * 60, end: 8 * 60)
        XCTAssertNotNil(b.windowProblem)
    }

    /// A daily limit cleared in the editor stays cleared through a save.
    /// The synthesized encoder left a nil limit out, and the decoder then
    /// filled it from the Daily limit preset's 30 minutes.
    func test_aClearedDailyLimitStaysClearedThroughASave() throws {
        var b = on(.dailyLimit)
        b.dailyLimitMinutes = nil
        let back = try JSONDecoder().decode(Blocker.self, from: JSONEncoder().encode(b))
        XCTAssertNil(back.dailyLimitMinutes)
        // Saved by the old encoder, with the key simply missing.
        let old = try JSONDecoder().decode(BlockState.self,
                                           from: Data(#"{"blockers":[{"kind":"dailyLimit","name":"Limit"}]}"#.utf8))
        XCTAssertNil(old.blockers[0].dailyLimitMinutes)
        // A limit that is set survives.
        b.dailyLimitMinutes = 45
        XCTAssertEqual(try JSONDecoder().decode(Blocker.self, from: JSONEncoder().encode(b)).dailyLimitMinutes, 45)
    }

    /// A pass ends on a whole second, the precision Screen Time is told its
    /// end in, so the monitor's wake at that second finds it over.
    func test_aPassEndsOnAWholeSecond() {
        var s = state(on(.mindfulDay))
        let now = at(10, 9).addingTimeInterval(0.7)
        BlockRules.takePass(minutes: 5, in: &s, at: now, calendar: cal)
        let end = s.passes[0].end
        XCTAssertEqual(end.timeIntervalSinceReferenceDate, end.timeIntervalSinceReferenceDate.rounded())
        XCTAssertGreaterThanOrEqual(end, now.addingTimeInterval(300))
        XCTAssertNil(BlockRules.activePass(s.blockers[0].id, in: s, at: end))
    }

    func test_theDefaults() {
        let day = Blocker.preset(.mindfulDay)
        XCTAssertEqual(Blocker.sessionMinutes, 5)
        XCTAssertEqual(day.window, .allDay)
        XCTAssertFalse(day.isOn, "on only once apps are picked")
    }

    // MARK: - From the 2026-09-22 review

    /// A window keeps its clock hours on a daylight saving day. Adding
    /// minutes to midnight put a 6:00 start at 7:00 on 8 March 2026 in New
    /// York, while Screen Time wakes the monitor at 6:00 on the clock.
    func test_windowsKeepTheirClockHoursAcrossDaylightSaving() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        func local(_ month: Int, _ day: Int, _ hour: Int) -> Date {
            ny.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        let morning = Blocker.preset(.mindfulMorning)
        for day in [(3, 8), (11, 1)] {   // spring forward, fall back
            let w = morning.window(openingOnDayOf: local(day.0, day.1, 12), calendar: ny)!
            XCTAssertEqual(ny.component(.hour, from: w.start), 6, "\(day)")
            XCTAssertEqual(ny.component(.hour, from: w.end), 10, "\(day)")
        }
        let windDown = Blocker.preset(.windDown)
        let night = windDown.window(openingOnDayOf: local(11, 1, 12), calendar: ny)!
        XCTAssertEqual(ny.component(.hour, from: night.start), 21)
        XCTAssertEqual(night.end, ny.startOfDay(for: local(11, 2, 12)), "ends at the next midnight")
    }

    /// A window worked out again (a time zone change mid-window moves its
    /// start) still knows the session that opened it.
    func test_aReleaseSurvivesTheWindowBeingWorkedOutAgain() {
        let day = on(.mindfulDay)
        var s = state(day)
        BlockRules.recordSession(endingAt: at(10, 10), durationSec: 300, in: &s, calendar: cal)
        s.releases[0].windowStart = at(10, 1)   // as if the window's start had moved
        XCTAssertFalse(BlockRules.holds(day, in: s, at: at(10, 11), calendar: cal))
    }

    /// A blocker saved with the settings that left the editor on 2026-09-22
    /// (strictness, passes a day, its own shortest session) still loads, and
    /// takes "Not now" like any other.
    func test_blockersSavedWithStrictnessStillLoadAndTakeNotNow() throws {
        let json = """
        {"blockers":[{"kind":"mindfulDay","name":"Mindful day","isOn":true,"hasApps":true,
                      "strictness":"strict","passesPerDay":0,"minimumMinutes":10}]}
        """
        var s = try JSONDecoder().decode(BlockState.self, from: Data(json.utf8))
        XCTAssertEqual(s.blockers.count, 1)
        XCTAssertEqual(BlockRules.takePass(minutes: 5, in: &s, at: at(10, 9), calendar: cal).count, 1)
    }

    /// The next release adds a field, or drops one: the blockers survive.
    func test_blockersSurviveMissingAndUnknownFields() throws {
        let json = """
        {"blockers":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"mindfulMorning",
                      "name":"Mornings","isOn":true,"hasApps":true,"somethingNew":42},
                     {"kind":"aKindFromTheFuture","name":"Later"}],
         "fieldFromTheFuture":{"x":1}}
        """
        let s = try JSONDecoder().decode(BlockState.self, from: Data(json.utf8))
        XCTAssertEqual(s.blockers.count, 2)
        XCTAssertEqual(s.blockers[0].name, "Mornings")
        XCTAssertEqual(s.blockers[0].window, .hours(start: 6 * 60, end: 10 * 60), "the preset fills the gap")
        XCTAssertTrue(s.blockers[0].isOn)
        XCTAssertEqual(s.blockers[1].kind, .custom, "an unknown kind reads as custom")
        XCTAssertTrue(s.seededDefault, "blockers present means the default was seeded")
    }

    /// The symbol under the editor's pencil arrived on 2026-09-22. Every
    /// blocker saved before it has no such key and must draw its kind's own,
    /// and a picked one must survive a save.
    func test_symbolDefaultsToTheKindsAndSurvivesASave() throws {
        let json = """
        {"blockers":[{"kind":"windDown","name":"Evenings"}]}
        """
        let old = try JSONDecoder().decode(BlockState.self, from: Data(json.utf8)).blockers[0]
        XCTAssertNil(old.symbol, "a blocker from before the pencil has no symbol of its own")
        XCTAssertEqual(old.displaySymbol, "moon.stars.fill", "and draws its kind's")

        var s = state(on(.focusHours))
        s.blockers[0].symbol = "book.fill"
        let back = try JSONDecoder().decode(BlockState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.blockers[0].displaySymbol, "book.fill")
    }

    /// Every kind names a symbol, so no blocker ever draws an empty circle.
    func test_everyKindHasASymbol() {
        for kind in BlockerKind.allCases {
            XCTAssertFalse(kind.defaultSymbol.isEmpty, "\(kind) has no symbol")
        }
    }

    func test_windowsScreenTimeWouldRefuseAreCaught() {
        var b = Blocker.preset(.custom)
        b.window = .hours(start: 600, end: 610)
        XCTAssertNotNil(b.windowProblem)
        b.window = .hours(start: 600, end: 600)
        XCTAssertNotNil(b.windowProblem)
        b.window = .hours(start: 23 * 60 + 50, end: 10)   // 20 minutes, past midnight
        XCTAssertNil(b.windowProblem)
        XCTAssertNil(Blocker.preset(.mindfulDay).windowProblem)
    }

    /// Otto's glow replays the whole history, so pruning must not forget a
    /// "Not now" it still reads.
    func test_pruningKeepsWhatTheGlowReads() {
        var s = state(on(.mindfulDay))
        BlockRules.takePass(minutes: 5, in: &s, at: at(10, 9), calendar: cal)
        BlockRules.prune(&s, now: at(10, 9).addingTimeInterval(200 * 86_400))
        XCTAssertEqual(s.passes.count, 1)
        BlockRules.prune(&s, now: at(10, 9).addingTimeInterval(800 * 86_400))
        XCTAssertTrue(s.passes.isEmpty)
    }

    func test_stateRoundTripsThroughJSON() throws {
        var s = state(on(.mindfulMorning), on(.focusHours))
        BlockRules.takePass(minutes: 10, in: &s, at: at(10, 7), calendar: cal)
        let back = try JSONDecoder().decode(BlockState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }
}

/// Otto's twenty screens: only the true ones; a video call, a text and any
/// other screen a third of the time each (2026-10-06); and the other screens
/// never twice running.
final class InterventionPickerTests: XCTestCase {

    private func context(hour: Int = 14, streak: Int = 0, aura: OttoAura.Stage = .stirring,
                         friend: String? = nil) -> InterventionContext {
        InterventionContext(hour: hour, streak: streak, aura: aura, friendWhoSat: friend)
    }

    /// SplitMix64, so every draw in these tests is the same on every run.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        init(_ seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Picks as the app does: each shown screen is remembered, and the list
    /// is kept to its last twelve (`BlockRules.prune`).
    private func run(_ ctx: InterventionContext, draws: Int, seed: UInt64,
                     check: (InterventionKind, [InterventionKind]) -> Void = { _, _ in }) -> [InterventionKind] {
        var rng = Seeded(seed)
        var recent: [InterventionKind] = []
        var picks: [InterventionKind] = []
        for _ in 0..<draws {
            let next = InterventionPicker.pick(ctx, recent: recent, using: &rng)
            check(next, recent)
            picks.append(next)
            recent.append(next)
            if recent.count > 12 { recent.removeFirst(recent.count - 12) }
        }
        return picks
    }

    func test_morningScreensOnlyInTheMorning() {
        XCTAssertTrue(InterventionPicker.eligible(context(hour: 7)).contains(.wakingOtto))
        XCTAssertFalse(InterventionPicker.eligible(context(hour: 14)).contains(.wakingOtto))
        XCTAssertFalse(InterventionPicker.eligible(context(hour: 22)).contains(.affirmation))
    }

    func test_bedtimeOnlyAtNight() {
        XCTAssertTrue(InterventionPicker.eligible(context(hour: 22)).contains(.bedtime))
        XCTAssertTrue(InterventionPicker.eligible(context(hour: 1)).contains(.bedtime))
        XCTAssertFalse(InterventionPicker.eligible(context(hour: 12)).contains(.bedtime))
    }

    func test_theStreakScreenNeedsAStreak() {
        XCTAssertFalse(InterventionPicker.eligible(context(streak: 1)).contains(.streak))
        XCTAssertTrue(InterventionPicker.eligible(context(streak: 6)).contains(.streak))
    }

    func test_aFriendScreenNeedsAFriend() {
        XCTAssertFalse(InterventionPicker.eligible(context()).contains(.friend))
        XCTAssertTrue(InterventionPicker.eligible(context(friend: "Maya")).contains(.friend))
    }

    func test_noGlowAskWhenHeIsAlreadyEnlightened() {
        XCTAssertFalse(InterventionPicker.eligible(context(aura: .nirvana)).contains(.glow))
    }

    /// The texts are the two screens drawn as a chat with Otto. The written
    /// note (`voiceNote`) is a letter on paper, so it is one of the others.
    func test_theTextsAreTheTwoChatScreens() {
        XCTAssertEqual(InterventionPicker.texts, [.textThread, .sticker])
        XCTAssertEqual(InterventionPicker.bucket(of: .faceTime), .videoCall)
        XCTAssertEqual(InterventionPicker.bucket(of: .textThread), .texts)
        XCTAssertEqual(InterventionPicker.bucket(of: .sticker), .texts)
        XCTAssertEqual(InterventionPicker.bucket(of: .voiceNote), .others)
        XCTAssertEqual(InterventionPicker.bucket(of: .standing), .others)
        let others = InterventionKind.inUse.filter { InterventionPicker.bucket(of: $0) == .others }
        XCTAssertEqual(others.count, InterventionKind.inUse.count - 3)
    }

    /// Melvin, 2026-10-06: a third a video call, a third a text, a third any
    /// other screen, at every hour and whatever is true right now.
    func test_aThirdEachCallTextAndTheRest() {
        let contexts = [context(), context(hour: 7, streak: 5, friend: "Maya"),
                        context(hour: 22, aura: .nirvana), context(hour: 2, streak: 3)]
        for (i, ctx) in contexts.enumerated() {
            let picks = run(ctx, draws: 6_000, seed: UInt64(41 + i))
            func share(_ b: InterventionPicker.Bucket) -> Double {
                Double(picks.filter { InterventionPicker.bucket(of: $0) == b }.count) / Double(picks.count)
            }
            for b in InterventionPicker.Bucket.allCases {
                XCTAssertEqual(share(b), 1.0 / 3, accuracy: 0.03, "\(b) at hour \(ctx.hour)")
            }
            // The two texts evenly.
            let thread = picks.filter { $0 == .textThread }.count
            let sticker = picks.filter { $0 == .sticker }.count
            XCTAssertEqual(Double(thread) / Double(thread + sticker), 0.5, accuracy: 0.05)
        }
    }

    /// Every pick is a screen that is true right now: no morning screen in
    /// the afternoon, no bedtime by day, no streak without one, no friend
    /// without one, no glow ask once he is enlightened.
    func test_gatedScreensStayInsideTheirGates() {
        let contexts = [context(), context(hour: 7), context(hour: 22, aura: .nirvana),
                        context(hour: 12, streak: 1), context(hour: 9, streak: 4, friend: "Sam")]
        for (i, ctx) in contexts.enumerated() {
            let allowed = Set(InterventionPicker.eligible(ctx))
            for kind in run(ctx, draws: 1_500, seed: UInt64(7 + i)) {
                XCTAssertTrue(allowed.contains(kind), "\(kind) at hour \(ctx.hour)")
            }
        }
        let afternoon = Set(run(context(), draws: 1_500, seed: 3))
        XCTAssertTrue(afternoon.isDisjoint(with: [.wakingOtto, .affirmation, .bedtime, .streak, .friend]))
        XCTAssertFalse(Set(run(context(aura: .nirvana), draws: 1_500, seed: 4)).contains(.glow))
    }

    /// The other screens keep the old rotation: never the last of them
    /// shown, and none seen among their last five while a fresh one is left.
    /// A call or a text may come twice running; that is the point.
    func test_onlyTheOtherScreensAvoidRepeats() {
        var callTwice = false, textTwice = false
        let picks = run(context(), draws: 1_200, seed: 11) { next, recent in
            guard InterventionPicker.bucket(of: next) == .others else { return }
            let shown = recent.filter { InterventionPicker.bucket(of: $0) == .others }
            XCTAssertFalse(shown.suffix(5).contains(next), "\(next) was among the last five others")
        }
        for (a, b) in zip(picks, picks.dropFirst()) where a == b {
            XCTAssertNotEqual(InterventionPicker.bucket(of: a), .others, "\(a) twice running")
            if a == .faceTime { callTwice = true }
            if InterventionPicker.texts.contains(a) { textTwice = true }
        }
        XCTAssertTrue(callTwice, "a video call can come twice running")
        XCTAssertTrue(textTwice, "a text can come twice running")
    }

    /// A third with nothing true in it is skipped, and the draw is even
    /// across what is left. No context empties one today, so this feeds
    /// pools straight to the draw.
    func test_anEmptyThirdFallsThrough() {
        var rng = Seeded(5)
        let noCall = InterventionKind.inUse.filter { $0 != .faceTime }
        var texts = 0
        for _ in 0..<3_000 {
            let kind = InterventionPicker.pick(from: noCall, recent: [], using: &rng)
            XCTAssertNotEqual(kind, .faceTime)
            if InterventionPicker.texts.contains(kind) { texts += 1 }
        }
        XCTAssertEqual(Double(texts) / 3_000, 0.5, accuracy: 0.04)

        let othersOnly = InterventionKind.inUse.filter { InterventionPicker.bucket(of: $0) == .others }
        for _ in 0..<500 {
            XCTAssertEqual(InterventionPicker.bucket(of: InterventionPicker.pick(from: othersOnly, recent: [],
                                                                             using: &rng)), .others)
        }
        for _ in 0..<50 {
            XCTAssertEqual(InterventionPicker.pick(from: [.faceTime], recent: [.faceTime], using: &rng), .faceTime)
            XCTAssertEqual(InterventionPicker.pick(from: [.glow], recent: [.glow], using: &rng), .glow)
        }
        XCTAssertEqual(InterventionPicker.pick(from: [], recent: [], using: &rng), .standing)
    }

    func test_everyScreenCanBeReached() {
        var seen = Set<InterventionKind>()
        for (i, hour) in [7, 14, 22].enumerated() {
            seen.formUnion(run(context(hour: hour, streak: 5, friend: "Maya"), draws: 1_200, seed: UInt64(20 + i)))
        }
        XCTAssertEqual(seen, Set(InterventionKind.inUse))
    }

    /// Every screen's reply to "Not now" (2026-10-04): no em dash, short
    /// enough for his bubble, and true to the moment (the streak's number,
    /// the friend's name).
    func test_everyNotNowReplyFitsAndStaysTrue() {
        let ctx = InterventionContext(hour: 9, streak: 6, aura: .steady, friendWhoSat: "Sam")
        for kind in InterventionKind.inUse {
            let line = kind.notNowReply(ctx)
            XCTAssertFalse(line.contains("\u{2014}"), "\(kind): no em dash")
            XCTAssertLessThanOrEqual(line.count, 90, "\(kind): fits his bubble")
        }
        XCTAssertTrue(InterventionKind.streak.notNowReply(ctx).contains("6-day"))
        XCTAssertTrue(InterventionKind.friend.notNowReply(ctx).contains("Sam"))
        var nobody = ctx
        nobody.friendWhoSat = nil
        XCTAssertFalse(InterventionKind.friend.notNowReply(nobody).contains("join"))
    }

    /// A retired screen is never picked, at any hour.
    func test_aRetiredScreenIsNeverPicked() {
        var rng = Seeded(99)
        for hour in [7, 14, 22] {
            let ctx = context(hour: hour, streak: 5, friend: "Maya")
            XCTAssertTrue(Set(InterventionPicker.eligible(ctx)).isDisjoint(with: InterventionKind.retired))
            for _ in 0..<200 {
                XCTAssertFalse(InterventionKind.retired.contains(
                    InterventionPicker.pick(ctx, recent: [], using: &rng)))
            }
        }
        XCTAssertTrue(InterventionKind.retired.contains(.stillThere))
    }
}

extension BlockRulesTests {
    /// Settings > Block (debug) "Hold every app now" (2026-10-06): every
    /// blocker with apps holds, off or outside its window or released by a
    /// session, and a "Not now" pass still opens it.
    func test_holdAllHoldsEveryBlockerWithAppsButHonoursNotNow() {
        let now = Date()
        var off = Blocker.preset(.custom); off.isOn = false; off.hasApps = true
        var noApps = Blocker.preset(.custom); noApps.isOn = true; noApps.hasApps = false
        var state = BlockState(); state.blockers = [off, noApps]
        XCTAssertTrue(BlockRules.holding(state, at: now).isEmpty)
        state.holdAll = true
        XCTAssertEqual(BlockRules.holding(state, at: now).map(\.id), [off.id])
        state.passes = [BlockPass(blockerID: off.id, start: now.addingTimeInterval(-60), end: now.addingTimeInterval(600), window: DateInterval(start: now.addingTimeInterval(-3600), duration: 7200))]
        XCTAssertTrue(BlockRules.holding(state, at: now).isEmpty)
    }

    func test_holdAllSurvivesASaveAndOldStatesLoadWithItOff() throws {
        var state = BlockState(); state.holdAll = true
        let back = try JSONDecoder().decode(BlockState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(back.holdAll)
        let old = try JSONDecoder().decode(BlockState.self, from: Data("{\"blockers\":[]}".utf8))
        XCTAssertFalse(old.holdAll)
    }
}
