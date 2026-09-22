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
        BlockRules.recordSession(endingAt: at(10, 10), durationSec: 120, in: &s, calendar: cal)
        XCTAssertFalse(BlockRules.holds(day, in: s, at: at(10, 10, 1), calendar: cal))
        XCTAssertFalse(BlockRules.holds(day, in: s, at: at(10, 23), calendar: cal))
        // A new day is a new window.
        XCTAssertTrue(BlockRules.holds(day, in: s, at: at(11, 1), calendar: cal))
    }

    func test_aSessionShorterThanTheMinimumDoesNotCount() {
        let day = on(.mindfulDay)
        var s = state(day)
        BlockRules.recordSession(endingAt: at(10, 10), durationSec: 60, in: &s, calendar: cal)
        XCTAssertTrue(BlockRules.holds(day, in: s, at: at(10, 11), calendar: cal))
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
        BlockRules.recordSession(endingAt: at(10, 10), durationSec: 120, in: &s, calendar: cal)
        BlockRules.recordSession(endingAt: at(10, 10), durationSec: 120, in: &s, calendar: cal)
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

    func test_passesRunOutForTheDay() {
        let day = on(.mindfulDay)
        var s = state(day)
        for hour in [9, 11, 13] {
            BlockRules.takePass(minutes: 5, in: &s, at: at(10, hour), calendar: cal)
        }
        XCTAssertEqual(BlockRules.passesLeft(day, in: s, at: at(10, 15), calendar: cal), 0)
        XCTAssertTrue(BlockRules.takePass(minutes: 5, in: &s, at: at(10, 15), calendar: cal).isEmpty)
        XCTAssertTrue(BlockRules.holds(day, in: s, at: at(10, 15, 1), calendar: cal))
        XCTAssertEqual(BlockRules.passesLeft(day, in: s, at: at(11, 9), calendar: cal), 3)
    }

    func test_strictTakesNoPasses() {
        var strict = on(.mindfulDay)
        strict.strictness = .strict
        var s = state(strict)
        XCTAssertEqual(BlockRules.passesLeft(strict, in: s, at: at(10, 9), calendar: cal), 0)
        XCTAssertTrue(BlockRules.takePass(minutes: 10, in: &s, at: at(10, 9), calendar: cal).isEmpty)
        XCTAssertTrue(BlockRules.holds(strict, in: s, at: at(10, 9, 5), calendar: cal))
    }

    func test_noLimitMeansNoLimit() {
        var loose = on(.mindfulDay)
        loose.passesPerDay = nil
        var s = state(loose)
        for hour in 8...20 { BlockRules.takePass(minutes: 5, in: &s, at: at(10, hour), calendar: cal) }
        XCTAssertNil(BlockRules.passesLeft(loose, in: s, at: at(10, 21), calendar: cal))
        XCTAssertTrue(BlockRules.canTakePass(loose, in: s, at: at(10, 21), calendar: cal))
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
        BlockRules.recordSession(endingAt: at(10, 9), durationSec: 180, in: &s, calendar: cal)
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

    /// Melvin's defaults: Chill, three passes, two minutes.
    func test_theDefaultsAreChillThreePassesTwoMinutes() {
        let day = Blocker.preset(.mindfulDay)
        XCTAssertEqual(day.strictness, .chill)
        XCTAssertEqual(day.passesPerDay, 3)
        XCTAssertEqual(day.minimumMinutes, 2)
        XCTAssertEqual(day.window, .allDay)
        XCTAssertFalse(day.isOn, "on only once apps are picked")
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

    private func context(hour: Int = 14, streak: Int = 0, aura: OttoAura.Stage = .curious,
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
        XCTAssertFalse(InterventionPicker.eligible(context(aura: .enlightened)).contains(.glow))
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
