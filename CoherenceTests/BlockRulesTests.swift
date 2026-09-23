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
        let sessions = [at(7, 12), at(8, 12), at(10, 12)]
        let without = OttoAura.level(from: sessions, today: at(10, 13), calendar: cal)
        let with = OttoAura.level(from: sessions, notNow: BlockRules.notNowWindows(s),
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

/// Otto's twenty screens: only the true ones, and never the same twice running.
final class InterventionPickerTests: XCTestCase {

    private func context(hour: Int = 14, streak: Int = 0, aura: OttoAura.Stage = .stirring,
                         friend: String? = nil) -> InterventionContext {
        InterventionContext(hour: hour, streak: streak, aura: aura, friendWhoSat: friend)
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

    func test_neverTheSameScreenTwiceRunning() {
        var rng = SystemRandomNumberGenerator()
        var last: InterventionKind?
        var recent: [InterventionKind] = []
        for _ in 0..<200 {
            let next = InterventionPicker.pick(context(), recent: recent, using: &rng)
            XCTAssertNotEqual(next, last)
            last = next
            recent.append(next)
        }
    }

    func test_everyScreenCanBeReached() {
        var seen = Set<InterventionKind>()
        var rng = SystemRandomNumberGenerator()
        for hour in [7, 14, 22] {
            for _ in 0..<400 {
                seen.insert(InterventionPicker.pick(context(hour: hour, streak: 5, friend: "Maya"),
                                                   recent: [], using: &rng))
            }
        }
        XCTAssertEqual(seen, Set(InterventionKind.allCases))
    }
}
