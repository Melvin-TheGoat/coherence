import XCTest
@testable import Coherence

/// Awards are derived, so these tests are the whole feature. Anything that
/// passes here is true on a device, because nothing else decides.
final class AwardEngineTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func day(_ offsetFromToday: Int, score: Double? = nil, minutes: Int = 10,
                     hour: Int = 9, isLogged: Bool = false, mode: String = "silence",
                     soundID: String? = nil, technique: String? = nil, rating: Int? = nil,
                     hasNote: Bool = false, hasPhoto: Bool = false)
        -> AwardEngine.SessionFact {
        let d = cal.date(byAdding: .day, value: offsetFromToday,
                         to: cal.startOfDay(for: Date()))!
        return .init(startedAt: d.addingTimeInterval(TimeInterval(hour) * 3600),
                     durationSec: minutes * 60, overallScore: score,
                     isLogged: isLogged, mode: mode, soundID: soundID,
                     technique: technique, rating: rating, hasNote: hasNote, hasPhoto: hasPhoto)
    }

    private func earned(_ facts: [AwardEngine.SessionFact],
                        created: Date? = Date(),
                        friendBroughtAt: Date? = nil) -> [String: AwardEngine.Earned] {
        Dictionary(uniqueKeysWithValues: AwardEngine
            .evaluate(sessions: facts, accountCreatedAt: created,
                      friendBroughtAt: friendBroughtAt, calendar: cal)
            .map { ($0.award.id, $0) })
    }

    /// A calendar pinned to an explicit time zone, for the time-of-day rules,
    /// which must read a session's LOCAL hour rather than whatever zone the
    /// test happens to run in.
    private func tzCalendar(_ identifier: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: identifier)!
        return c
    }

    private func moment(hour: Int, calendar: Calendar,
                        year: Int = 2026, month: Int = 6, day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: The rule that matters most

    /// THE load-bearing behaviour. Melvin's call: you keep the award. Taking it
    /// back punishes exactly the person we are trying to bring back.
    func test_brokenStreakKeepsTheAward() {
        // Ten straight days, then a two week gap, then one session today.
        var facts = (1...10).map { day(-40 + $0) }
        facts.append(day(0))

        let a = earned(facts)
        XCTAssertTrue(a["streak10"]!.isEarned, "a broken streak took the award back")
        XCTAssertTrue(a["streak5"]!.isEarned)
        XCTAssertFalse(a["streak25"]!.isEarned)
    }

    /// The date shown is when it was earned, not when it was noticed. Someone
    /// who ran forty days straight earned the ten-day award on day ten.
    func test_earnedDateIsTheSessionThatEarnedIt() {
        let facts = (0..<40).map { day(-39 + $0) }
        let a = earned(facts)

        let tenth = cal.startOfDay(for: facts[9].startedAt)
        XCTAssertEqual(a["streak10"].flatMap { $0.earnedAt.map(cal.startOfDay(for:)) },
                       tenth, "streak award dated to the end of the run, not day ten")
    }

    // MARK: Backfill

    /// Backfill is not a feature, it is a consequence: derived rules read the
    /// history that already exists.
    func test_existingHistoryEarnsItsAwardsWithNoMigration() {
        let facts = (0..<30).map { day(-29 + $0, score: 0.8, minutes: 25) }
        let a = earned(facts)

        for id in ["firstStep", "firstSession", "streak3", "streak5", "streak10",
                   "streak25", "score50", "score75", "min20"] {
            XCTAssertTrue(a[id]!.isEarned, "\(id) was not backfilled from history")
        }
        XCTAssertFalse(a["score90"]!.isEarned)
        XCTAssertFalse(a["min30"]!.isEarned)
        XCTAssertFalse(a["streak50"]!.isEarned)
    }

    // MARK: Thresholds

    func test_scoreAwardsNeedASessionThatReachedThem() {
        XCTAssertFalse(earned([day(0, score: 0.49)])["score50"]!.isEarned)
        XCTAssertTrue(earned([day(0, score: 0.50)])["score50"]!.isEarned)
        // One good session is enough; it does not have to be the latest.
        let mixed = earned([day(-2, score: 0.91), day(-1, score: 0.2), day(0, score: 0.3)])
        XCTAssertTrue(mixed["score90"]!.isEarned)
    }

    func test_durationAwardsAreOneSitNotATotal() {
        // Four ten-minute sits are forty minutes and earn nothing.
        let short = earned((0..<4).map { day(-$0, minutes: 10) })
        XCTAssertFalse(short["min20"]!.isEarned, "summed minutes earned a single-sit award")
        XCTAssertTrue(earned([day(0, minutes: 20)])["min20"]!.isEarned)
    }

    // MARK: Days, not sessions

    func test_severalSessionsInOneDayAreOneDay() {
        let facts = (0..<6).map { _ in day(0) }
        XCTAssertFalse(earned(facts)["streak3"]!.isEarned,
                       "six sessions in one day counted as a streak")
    }

    // MARK: Empty and progress

    func test_freshAccountHasOnlyTheSignupAward() {
        let a = earned([], created: Date())
        XCTAssertTrue(a["firstStep"]!.isEarned)
        XCTAssertFalse(a["firstSession"]!.isEarned)
        XCTAssertEqual(a.values.filter(\.isEarned).count, 1)
    }

    func test_noAccountEarnsNothing() {
        let a = earned([], created: nil)
        XCTAssertTrue(a.values.allSatisfy { !$0.isEarned })
    }

    /// Progress must describe the live streak, not the best one ever, or the
    /// "next up" bar tells someone they are 40/50 when they sat once yesterday.
    func test_progressTracksTheCurrentStreakNotTheBestOne() {
        var facts = (1...20).map { day(-60 + $0) }
        facts.append(day(0))

        let a = earned(facts)
        XCTAssertEqual(a["streak25"]!.progressText, "1/25")
        XCTAssertEqual(a["streak25"]!.progress, 1.0 / 25, accuracy: 0.0001)
        XCTAssertTrue(a["streak10"]!.isEarned, "but the earned one is still earned")
    }

    /// An earned award reports no progress text: a finished thing showing
    /// "10/10" invites reading it as unfinished.
    func test_earnedAwardsCarryNoProgressText() {
        let a = earned((0..<5).map { day(-$0, score: 0.9, minutes: 40) })
        for item in a.values where item.isEarned {
            XCTAssertNil(item.progressText, "\(item.award.id) still showed progress")
            XCTAssertEqual(item.progress, 1)
        }
    }

    // MARK: The 18 original awards, untouched

    /// A characterization test: every id that existed before the catalog
    /// grew must still exist, unchanged. If this fails, something about the
    /// OLD awards moved, which the task never asked for.
    func test_theOriginalAwardsAreAllStillThere() {
        let originalIDs = ["firstStep", "firstSession", "friendBrought",
                           "streak3", "streak5", "streak10", "streak25", "streak50",
                           "streak100", "streak200", "streak300", "streak365",
                           "score50", "score75", "score90",
                           "min20", "min30", "min60"]
        XCTAssertEqual(originalIDs.count, 18)
        for id in originalIDs {
            XCTAssertNotNil(Award.award(id: id), "\(id) is missing from the catalog")
        }
    }

    /// `min20`/`min30`/`min60` predate the "hand-logged sessions don't earn a
    /// length award" rule and must keep their OLD, unfiltered behaviour: a
    /// logged session still counts toward them, exactly as it always could.
    func test_originalMinuteAwardsStillCountHandLoggedSessions() {
        let logged = earned([day(0, minutes: 60, isLogged: true)])
        XCTAssertTrue(logged["min60"]!.isEarned,
                      "min60's original behaviour changed: it must still count a logged session")
    }

    // MARK: New: a single session's real length excludes hand-logged sits

    /// `length15`/`45`/`90` are NEW and must exclude a hand-logged session:
    /// nothing timed a typed-in sit in real time, so its "length" is a guess
    /// wearing a badge that means something else earned it.
    func test_newLengthAwardsExcludeHandLoggedSessions() {
        let logged = earned([day(0, minutes: 90, isLogged: true)])
        XCTAssertFalse(logged["length90"]!.isEarned,
                       "a hand-logged session earned a real single-session length award")

        let real = earned([day(0, minutes: 90)])
        XCTAssertTrue(real["length90"]!.isEarned)
    }

    // MARK: New: totals and streaks still count hand-logged sessions

    func test_handLoggedSessionsStillCountTowardTotalsAndStreaks() {
        let facts = (1...5).map { day(-5 + $0, isLogged: true) }
        let a = earned(facts)
        XCTAssertTrue(a["streak5"]!.isEarned, "a logged run of 5 days did not earn the streak")
        XCTAssertTrue(a["sessions5"]!.isEarned, "logged sessions were not counted toward a total")
        XCTAssertTrue(a["totalHours1"]!.isEarned == (5 * 10 >= 60),
                     "sanity: 5 logged 10-minute sessions is 50 minutes, under an hour")
    }

    // MARK: New: session counts, total hours, days practiced

    func test_sessionCountAwardsCountEverySessionRegardlessOfLength() {
        let facts = (0..<10).map { day(-$0) }
        let a = earned(facts)
        XCTAssertTrue(a["sessions5"]!.isEarned)
        XCTAssertTrue(a["sessions10"]!.isEarned)
        XCTAssertFalse(a["sessions25"]!.isEarned)
        XCTAssertEqual(a["sessions25"]!.progressText, "10/25")
    }

    func test_totalHoursSumsDurationAcrossEverySession() {
        let facts = (0..<6).map { day(-$0, minutes: 10) }   // 60 minutes total
        let a = earned(facts)
        XCTAssertTrue(a["totalHours1"]!.isEarned)
        XCTAssertFalse(a["totalHours10"]!.isEarned)
    }

    func test_practicedDaysCountsDistinctDaysNotSessions() {
        var facts = (0..<5).map { day(-$0) }
        facts.append(day(0))   // a second session on an already-counted day
        let a = earned(facts)
        XCTAssertEqual(a["practicedDays365"]!.progressText, "5/365")
    }

    // MARK: New: perfect week, twice in a day, the return, weekends, rest days

    func test_perfectWeekNeedsSevenConsecutiveDaysWithNoGap() {
        XCTAssertFalse(earned((0..<6).map { day(-$0) })["perfectWeek"]!.isEarned)
        XCTAssertTrue(earned((0..<7).map { day(-$0) })["perfectWeek"]!.isEarned)
    }

    func test_multipleInADayNeedsTwoSessionsSameCalendarDay() {
        XCTAssertFalse(earned([day(0)])["multipleInADay"]!.isEarned)
        XCTAssertTrue(earned([day(0), day(0)])["multipleInADay"]!.isEarned)
    }

    func test_cameBackNeedsAWeekOrMoreAwayThenAnotherSession() {
        XCTAssertFalse(earned([day(-10), day(-5)])["cameBack"]!.isEarned,
                       "a five day gap is not a comeback")
        XCTAssertTrue(earned([day(-20), day(-10)])["cameBack"]!.isEarned)
    }

    func test_weekendWarriorNeedsSaturdayAndSunday() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var saturday = utc.startOfDay(for: Date())
        while utc.component(.weekday, from: saturday) != 7 {
            saturday = utc.date(byAdding: .day, value: 1, to: saturday)!
        }
        let sunday = utc.date(byAdding: .day, value: 1, to: saturday)!

        func fact(_ d: Date) -> AwardEngine.SessionFact {
            .init(startedAt: d.addingTimeInterval(9 * 3600), durationSec: 600, overallScore: nil)
        }

        let a = Dictionary(uniqueKeysWithValues: AwardEngine.evaluate(
            sessions: [fact(saturday)], accountCreatedAt: Date(), calendar: utc)
            .map { ($0.award.id, $0) })
        XCTAssertFalse(a["weekendWarrior"]!.isEarned, "Saturday alone should not be enough")

        let b = Dictionary(uniqueKeysWithValues: AwardEngine.evaluate(
            sessions: [fact(saturday), fact(sunday)], accountCreatedAt: Date(), calendar: utc)
            .map { ($0.award.id, $0) })
        XCTAssertTrue(b["weekendWarrior"]!.isEarned)
    }

    func test_restDayContinuedNeedsAForgivenGapInsideARun() {
        // Ten days, one forgiven day off, ten more days.
        var bridged = (1...10).map { day(-40 + $0) }
        bridged += (12...21).map { day(-40 + $0) }
        XCTAssertTrue(earned(bridged)["restDayContinued"]!.isEarned)

        // Two days missed in a row breaks the run outright: nothing here was
        // "continued", it was restarted.
        var broken = (1...10).map { day(-40 + $0) }
        broken += (13...21).map { day(-40 + $0) }
        XCTAssertFalse(earned(broken)["restDayContinued"]!.isEarned)
    }

    // MARK: New: sound and technique variety, the guided journey, silence

    func test_soundExplorerNeedsThreeDistinctSounds() {
        let two = earned([day(-2, soundID: "rain"), day(-1, soundID: "ocean")])
        XCTAssertFalse(two["soundExplorer"]!.isEarned)

        let three = earned([day(-2, soundID: "rain"), day(-1, soundID: "ocean"),
                            day(0, soundID: "forest")])
        XCTAssertTrue(three["soundExplorer"]!.isEarned)
    }

    func test_techniqueVarietyNeedsThreeDistinctTechniques() {
        let repeated = earned([day(-1, technique: "breathwork"), day(0, technique: "breathwork")])
        XCTAssertFalse(repeated["techniqueVariety"]!.isEarned)

        let three = earned([day(-2, technique: "breathwork"), day(-1, technique: "silence"),
                            day(0, technique: "own")])
        XCTAssertTrue(three["techniqueVariety"]!.isEarned)
    }

    func test_guidedCompleteNeedsTheFullTrackNotAFewMinutes() {
        XCTAssertFalse(earned([day(0, minutes: 10, mode: "guided")])["guidedComplete"]!.isEarned)
        XCTAssertTrue(earned([day(0, minutes: 26, mode: "guided")])["guidedComplete"]!.isEarned)
    }

    /// A hand-logged session defaults to "silence" only because the logging
    /// flow never asks about sound. That is not the same as choosing no
    /// sound over a sound, so it must not trivially earn this.
    func test_sessionInSilenceExcludesHandLoggedSessions() {
        XCTAssertFalse(earned([day(0, isLogged: true, mode: "silence")])["sessionInSilence"]!.isEarned)
        XCTAssertTrue(earned([day(0, mode: "silence")])["sessionInSilence"]!.isEarned)
    }

    // MARK: New: reflection awards

    func test_reflectionAwardsReadTheAttachedFacts() {
        XCTAssertFalse(earned([day(0)])["sessionRated"]!.isEarned)
        XCTAssertTrue(earned([day(0, rating: 7)])["sessionRated"]!.isEarned)
        XCTAssertTrue(earned([day(0, hasNote: true)])["wroteANote"]!.isEarned)
        XCTAssertTrue(earned([day(0, hasPhoto: true)])["addedPhoto"]!.isEarned)
    }

    // MARK: New: time of day, with an explicit calendar and time zone

    func test_timeOfDayAwardsReadTheLocalHourInTheGivenTimeZone() {
        let ny = tzCalendar("America/New_York")

        func fact(hour: Int) -> AwardEngine.SessionFact {
            .init(startedAt: moment(hour: hour, calendar: ny), durationSec: 600, overallScore: nil)
        }

        let a = Dictionary(uniqueKeysWithValues: AwardEngine.evaluate(
            sessions: [fact(hour: 6), fact(hour: 13), fact(hour: 19), fact(hour: 23)],
            accountCreatedAt: Date(), calendar: ny).map { ($0.award.id, $0) })

        XCTAssertTrue(a["earlyBird"]!.isEarned)
        XCTAssertTrue(a["lunchBreak"]!.isEarned)
        XCTAssertTrue(a["eveningWindDown"]!.isEarned)
        XCTAssertTrue(a["nightOwl"]!.isEarned)
        XCTAssertTrue(a["allPartsOfDay"]!.isEarned)
    }

    /// The SAME instant, read through a different explicit time zone, lands
    /// in a different hour band. Proof the rule reads the calendar's own
    /// zone rather than always using whatever machine runs the test.
    func test_timeOfDayReadsTheCalendarsOwnZoneNotAHardcodedOne() {
        let ny = tzCalendar("America/New_York")
        let utc = tzCalendar("UTC")

        // 6am in New York in June (EDT, UTC-4) is 10am UTC: none of the four
        // named bands.
        let sixAmEasternInstant = moment(hour: 6, calendar: ny)
        let a = Dictionary(uniqueKeysWithValues: AwardEngine.evaluate(
            sessions: [.init(startedAt: sixAmEasternInstant, durationSec: 600, overallScore: nil)],
            accountCreatedAt: Date(), calendar: utc).map { ($0.award.id, $0) })

        XCTAssertFalse(a["earlyBird"]!.isEarned)
        XCTAssertFalse(a["lunchBreak"]!.isEarned)
        XCTAssertFalse(a["eveningWindDown"]!.isEarned)
        XCTAssertFalse(a["nightOwl"]!.isEarned)
    }

    /// Time-of-day awards are the OTHER new family that excludes hand-logged
    /// sessions: nothing recorded what time a typed-in sit actually happened.
    func test_timeOfDayAwardsExcludeHandLoggedSessions() {
        let ny = tzCalendar("America/New_York")
        let logged = AwardEngine.SessionFact(startedAt: moment(hour: 6, calendar: ny),
                                             durationSec: 600, overallScore: nil, isLogged: true)
        let a = Dictionary(uniqueKeysWithValues: AwardEngine.evaluate(
            sessions: [logged], accountCreatedAt: Date(), calendar: ny).map { ($0.award.id, $0) })
        XCTAssertFalse(a["earlyBird"]!.isEarned, "a hand-logged session earned a time-of-day award")
    }

    // MARK: New: Otto's aura

    func test_ottoAwardsFollowTheAuraHistory() {
        // Five twenty-minute days in a row reaches Nirvana (see
        // OttoAuraTests: gain(minutes: 20) == 10, the old flat daily gain),
        // so all four Otto awards land together by day five.
        let facts = (1...5).map { day(-10 + $0, minutes: 20) }
        let a = earned(facts)
        for id in ["ottoSteady", "ottoBright", "ottoRadiant", "ottoNirvana"] {
            XCTAssertTrue(a[id]!.isEarned, "\(id) was not earned by a run that reaches Nirvana")
        }

        // One ten-minute session alone (+5) raises him to Steady (45) only.
        let one = earned([day(0)])
        XCTAssertTrue(one["ottoSteady"]!.isEarned)
        XCTAssertFalse(one["ottoBright"]!.isEarned)
    }

    // MARK: The inbox

    /// The bug this was caught by, on the simulator: sessions load
    /// asynchronously, so the first look can happen against an empty history
    /// and every real award then queues up as breaking news.
    func test_historyThatArrivesLateIsNotAnnouncedAsNew() {
        AwardsInbox.resetForPreview()

        // First look: the store has not finished loading, so nothing is earned
        // except the signup award.
        let empty = AwardEngine.evaluate(sessions: [], accountCreatedAt: Date(), calendar: cal)
        AwardsInbox.seedIfNeeded(with: empty)
        XCTAssertTrue(AwardsInbox.pending(from: empty).isEmpty)

        // A moment later thirty days of history land.
        let full = AwardEngine.evaluate(
            sessions: (0..<30).map { day(-29 + $0, score: 0.8, minutes: 25) },
            accountCreatedAt: Date(), calendar: cal)
        XCTAssertTrue(AwardsInbox.pending(from: full).isEmpty,
                      "backfilled history announced itself as new awards")
        AwardsInbox.resetForPreview()
    }

    /// But something genuinely earned after the watermark must still announce,
    /// or the fix above silences the feature.
    func test_anAwardEarnedNowIsStillAnnounced() {
        AwardsInbox.resetForPreview()
        let before = AwardEngine.evaluate(sessions: [], accountCreatedAt: Date(), calendar: cal)
        AwardsInbox.seedIfNeeded(with: before)

        // A session that starts now, after the watermark.
        let fresh = AwardEngine.evaluate(
            sessions: [.init(startedAt: Date().addingTimeInterval(1),
                             durationSec: 1500, overallScore: 0.8)],
            accountCreatedAt: Date(), calendar: cal)
        let pending = AwardsInbox.pending(from: fresh)
        XCTAssertTrue(pending.contains { $0.award.id == "firstSession" },
                      "a genuinely new award was swallowed")

        // And only once.
        pending.forEach { AwardsInbox.markAnnounced($0.award.id) }
        XCTAssertTrue(AwardsInbox.pending(from: fresh).isEmpty)
        AwardsInbox.resetForPreview()
    }

    /// **THE FLOOD FIX.** An existing device already has an old `lastCheck`
    /// watermark from before the catalog grew. Without the catch-up, every
    /// brand new award that its OLD history already satisfies (sessions
    /// dated after that old watermark, which for a longtime user is most of
    /// them) would queue up as "just earned" the instant this bigger catalog
    /// first evaluates on that phone.
    func test_catalogGrowthDoesNotFloodAnExistingUser() {
        AwardsInbox.resetForPreview()

        // An existing install: it looked once, a while ago, and had already
        // announced streak10 under the smaller, old catalog.
        let history = (1...10).map { day(-40 + $0) }
        let before = AwardEngine.evaluate(sessions: history, accountCreatedAt: Date(), calendar: cal)
        AwardsInbox.seedIfNeeded(with: before)
        AwardsInbox.markAnnounced("streak10")

        // The app updates: the SAME old history now also earns brand new
        // awards that did not exist before (sessions10, practicedDays...).
        let grown = AwardEngine.evaluate(sessions: history, accountCreatedAt: Date(), calendar: cal)
        XCTAssertTrue(grown.contains { $0.award.id == "sessions10" && $0.isEarned },
                      "test setup: the grown catalog should have new awards to flood with")

        AwardsInbox.seedIfNeeded(with: grown)          // a no-op: lastCheck is already set
        AwardsInbox.catchUpCatalogIfNeeded(with: grown)
        XCTAssertTrue(AwardsInbox.pending(from: grown).isEmpty,
                      "the catalog's growth flooded an existing user with awards their old history already earned")

        // A genuinely new award, earned by a session dated after the
        // catch-up, still announces normally.
        var fresh = history
        fresh.append(.init(startedAt: Date().addingTimeInterval(1), durationSec: 600,
                           overallScore: nil, hasPhoto: true))
        let after = AwardEngine.evaluate(sessions: fresh, accountCreatedAt: Date(), calendar: cal)
        let pending = AwardsInbox.pending(from: after)
        XCTAssertTrue(pending.contains { $0.award.id == "addedPhoto" },
                      "a genuinely new award after the catch-up was swallowed too")

        AwardsInbox.resetForPreview()
    }

    /// The catch-up must run exactly once: a later launch re-running it must
    /// not resurrect anything it already silenced.
    func test_catalogCatchUpOnlyRunsOnce() {
        AwardsInbox.resetForPreview()
        let history = (1...10).map { day(-40 + $0) }
        let evaluated = AwardEngine.evaluate(sessions: history, accountCreatedAt: Date(), calendar: cal)
        AwardsInbox.seedIfNeeded(with: evaluated)
        AwardsInbox.catchUpCatalogIfNeeded(with: evaluated)
        XCTAssertTrue(AwardsInbox.pending(from: evaluated).isEmpty)

        var fresh = history
        fresh.append(.init(startedAt: Date().addingTimeInterval(1), durationSec: 600,
                           overallScore: nil, hasPhoto: true))
        let after = AwardEngine.evaluate(sessions: fresh, accountCreatedAt: Date(), calendar: cal)
        AwardsInbox.pending(from: after).forEach { AwardsInbox.markAnnounced($0.award.id) }

        // Every launch calls this; a second call must be a no-op.
        AwardsInbox.catchUpCatalogIfNeeded(with: after)
        XCTAssertTrue(AwardsInbox.pending(from: after).isEmpty)
        AwardsInbox.resetForPreview()
    }

    // MARK: Catalog

    func test_catalogIsWellFormed() {
        var seen = Set<String>()
        for award in Award.all {
            XCTAssertTrue(seen.insert(award.id).inserted, "duplicate \(award.id)")
            XCTAssertFalse(award.title.isEmpty)
            XCTAssertFalse(award.meaning.isEmpty)
        }

        // Every award must be reachable by SOME history, or it is decoration
        // that can never be earned. One long, varied history covers every
        // rule in the catalog at once: over a thousand sessions so every
        // count and hour threshold clears, one bridged rest day inside the
        // run (`restDayContinued`), a real gap followed by a return
        // (`cameBack`), sessions in every hour band, three distinct sounds
        // and techniques, a full guided session, a silent one, a rated one,
        // one with a note, one with a photo, and a second sit inside a
        // single day.
        var facts: [AwardEngine.SessionFact] = []
        for offset in stride(from: -1200, through: -80, by: 1) where offset != -280 {
            facts.append(day(offset, score: 0.95, minutes: 95))
        }
        facts.append(day(-40, score: 0.9, minutes: 20))          // the return, after the gap
        facts.append(day(-39, score: 0.9, minutes: 20))
        facts.append(day(-39, score: 0.9, minutes: 15))          // a second sit, same day

        facts.append(day(-30, score: 0.8, minutes: 6, hour: 6))    // early morning
        facts.append(day(-29, score: 0.8, minutes: 6, hour: 13))   // lunchtime
        facts.append(day(-28, score: 0.8, minutes: 6, hour: 19))   // evening
        facts.append(day(-27, score: 0.8, minutes: 6, hour: 23))   // late night

        facts.append(day(-20, score: 0.8, minutes: 10, soundID: "rain"))
        facts.append(day(-19, score: 0.8, minutes: 10, soundID: "ocean"))
        facts.append(day(-18, score: 0.8, minutes: 10, soundID: "forest"))
        facts.append(day(-17, score: 0.8, minutes: 26, mode: "guided", soundID: "guided.identity"))

        facts.append(day(-16, score: 0.8, minutes: 10, technique: "breathwork"))
        facts.append(day(-15, score: 0.8, minutes: 10, technique: "silence"))
        facts.append(day(-14, score: 0.8, minutes: 10, technique: "own"))

        facts.append(day(-13, score: 0.8, minutes: 10, rating: 8))
        facts.append(day(-12, score: 0.8, minutes: 10, hasNote: true))
        facts.append(day(-11, score: 0.8, minutes: 10, hasPhoto: true))

        let reachable = earned(facts, friendBroughtAt: Date())
        for award in Award.all {
            XCTAssertTrue(reachable[award.id]!.isEarned,
                          "\(award.id) cannot be earned by any history")
        }
    }

    /// No award may claim a health outcome or a brain state.
    func test_awardCopyRespectsTheScienceLine() {
        let banned = ["theta", "brainwave", "cure", "heals", "proven", "clinically",
                      "alpha state", "beta state"]
        for award in Award.all {
            let text = (award.meaning + " " + award.blurb + " " + award.title).lowercased()
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(award.id) says '\(word)'")
            }
        }
    }

    /// No em dashes, no en dashes, anywhere in user-facing award copy.
    func test_awardCopyHasNoEmOrEnDashes() {
        for award in Award.all {
            let text = award.title + " " + award.blurb + " " + award.meaning
            XCTAssertFalse(text.contains("\u{2014}"), "\(award.id) contains an em dash")
            XCTAssertFalse(text.contains("\u{2013}"), "\(award.id) contains an en dash")
        }
    }

    /// Never boast that an earned award is kept, and never tell the reader
    /// what they are missing (CLAUDE.md, both standing rules).
    func test_awardCopyNeverBoastsOrTellsYouWhatYouLack() {
        let bannedPhrases = ["forever", "never expires", "never lost", "never taken away",
                             "kept for good", "yours for good", "you haven't", "you have not",
                             "you're missing", "you are missing", "still don't", "still haven't"]
        for award in Award.all {
            let text = (award.meaning + " " + award.blurb).lowercased()
            for phrase in bannedPhrases {
                XCTAssertFalse(text.contains(phrase), "\(award.id) says '\(phrase)'")
            }
        }
    }
}
