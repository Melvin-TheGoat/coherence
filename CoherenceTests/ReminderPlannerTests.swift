import XCTest
@testable import Coherence

/// Locks the reminder rules (2026-10-12): only on days the person hasn't
/// meditated, up to three a day while they're around, fewer the longer they
/// are away, one farewell, then silence; and every line true on its day.
final class ReminderPlannerTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-10-12 at `hour`:`minute`, plus `day` days.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let base = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        return cal.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: base)!
    }

    private func input(now: Date, sessions: [Date], opened: Date? = nil,
                       hour: Int = 8, cadence: ReminderCadence = .smart,
                       profile: ReminderProfile = ReminderProfile()) -> ReminderInput {
        ReminderInput(now: now, calendar: cal, sessionStarts: sessions,
                      sits: sessions.map { OttoAura.Sit(date: $0, seconds: 600) },
                      lastOpened: opened, hour: hour, minute: 0, cadence: cadence, profile: profile)
    }

    private func plan(_ i: ReminderInput, seed: UInt64 = 7) -> [PlannedReminder] {
        var rng = SeededGenerator(seed: seed)
        return ReminderPlanner.plan(i, using: &rng)
    }

    private func count(on day: Int, in plan: [PlannedReminder]) -> Int {
        plan.filter { cal.isDate($0.fireDate, inSameDayAs: at(day, 12)) }.count
    }

    // MARK: When

    func test_noRemindersOnADayAlreadyMeditated() {
        let p = plan(input(now: at(0, 7), sessions: [at(-1, 9), at(0, 6, 30)]))
        XCTAssertEqual(count(on: 0, in: p), 0)
        XCTAssertEqual(count(on: 1, in: p), 3, "tomorrow is a fresh day")
    }

    func test_someoneAroundGetsThreeAtTheirTimeAFollowUpAndTheEvening() {
        let p = plan(input(now: at(0, 7), sessions: [at(-1, 9)]))
        let today = p.filter { cal.isDate($0.fireDate, inSameDayAs: at(0, 12)) }
        XCTAssertEqual(today.map(\.slot), [.first, .followUp, .lastCall])
        XCTAssertEqual(today.map { cal.component(.hour, from: $0.fireDate) }, [8, 12, 20])
    }

    func test_slotsThatHavePassedAreSkipped() {
        let p = plan(input(now: at(0, 13), sessions: [at(-1, 9)]))
        XCTAssertEqual(p.filter { cal.isDate($0.fireDate, inSameDayAs: at(0, 12)) }.map(\.slot), [.lastCall])
    }

    func test_fewerTheLongerSomeoneIsAwayThenOneFarewellThenSilence() {
        // Meditated yesterday, nothing after: today is day 1 away.
        let p = plan(input(now: at(0, 6), sessions: [at(-1, 9)]))
        let perDay = (0..<ReminderPlanner.horizonDays).map { count(on: $0, in: p) }
        // days away:  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
        // One a day through the first two weeks, the farewell on day 14
        // (Aziz, 2026-10-18), then silence.
        XCTAssertEqual(perDay, [3, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0])
        XCTAssertEqual(p.last?.topic, .farewell)
        XCTAssertEqual(p.filter { $0.topic == .farewell }.count, 1)
    }

    func test_openingTheAppCountsAsBeingAround() {
        let gone = plan(input(now: at(0, 6), sessions: [at(-30, 9)]))
        XCTAssertTrue(gone.isEmpty, "a month away and the farewell long sent: silence")
        let back = plan(input(now: at(0, 6), sessions: [at(-30, 9)], opened: at(0, 5)))
        XCTAssertEqual(count(on: 0, in: back), 2,
                       "opened today: reminders resume, but no three-a-day after a week without a session")
    }

    func test_onceADayMeansOnce() {
        let p = plan(input(now: at(0, 6), sessions: [at(-1, 9)], cadence: .once))
        XCTAssertEqual((0..<8).map { count(on: $0, in: p) }, [1, 1, 1, 1, 1, 1, 1, 1])
    }

    func test_slotTimesKeepTheirDistance() {
        XCTAssertEqual(ReminderPlanner.times(anchor: 8 * 60), [.first: 480, .followUp: 720, .lastCall: 1230])
        // Too close to the evening one: the follow-up is left out.
        XCTAssertEqual(ReminderPlanner.times(anchor: 15 * 60), [.first: 900, .lastCall: 1230])
        XCTAssertEqual(ReminderPlanner.times(anchor: 19 * 60 + 30), [.first: 1170, .lastCall: 1260])
        // Before bed: nothing after it.
        XCTAssertEqual(ReminderPlanner.times(anchor: 22 * 60), [.first: 1320])
        for anchor in stride(from: 6 * 60, through: 23 * 60, by: 15) {
            let t = ReminderPlanner.times(anchor: anchor).values.sorted()
            for (a, b) in zip(t, t.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 90, "anchor \(anchor)") }
            for minute in t where minute != anchor {
                XCTAssertLessThanOrEqual(minute, ReminderPlanner.latest, "anchor \(anchor)")
            }
        }
    }

    func test_neverMoreThanTheCap() {
        XCTAssertLessThanOrEqual(plan(input(now: at(0, 0, 1), sessions: [at(-1, 9)])).count,
                                 ReminderPlanner.maxPending)
    }

    // MARK: What

    func test_theEveningOneSavesTheStreak() {
        let streak = (1...5).map { at(-$0, 9) }
        let p = plan(input(now: at(0, 7), sessions: streak))
        let evening = p.first { $0.slot == .lastCall }!
        XCTAssertEqual(evening.topic, .streak)
        XCTAssertTrue(evening.body.contains("5-day streak"), evening.body)
    }

    // MARK: The streak saver (Melvin, 2026-10-27)

    private func saver(on day: Int, in plan: [PlannedReminder]) -> PlannedReminder? {
        plan.first { $0.slot == .streakSaver && cal.isDate($0.fireDate, inSameDayAs: at(day, 12)) }
    }

    /// A rest day was taken four days ago, so none can carry tonight: the
    /// streak ends at midnight, and 11:30 pm says so.
    func test_theSaverComesHalfAnHourBeforeAStreakEnds() {
        // The last seven days but one, four days ago, carried as a rest day.
        let sessions = [1, 2, 3, 5, 6, 7].map { at(-$0, 9) }
        XCTAssertTrue(StreakCalculator.endsTonight(from: sessions, today: at(0, 7), calendar: cal))
        let p = plan(input(now: at(0, 7), sessions: sessions))
        let s = saver(on: 0, in: p)
        XCTAssertNotNil(s)
        XCTAssertEqual(cal.component(.hour, from: s!.fireDate), 23)
        XCTAssertEqual(cal.component(.minute, from: s!.fireDate), 30)
        XCTAssertEqual(s?.topic, .streak)
        XCTAssertTrue((s!.title + s!.body).contains("6-day streak"), s!.body)
        // Still three at most: the saver takes the follow-up's place.
        let today = p.filter { cal.isDate($0.fireDate, inSameDayAs: at(0, 12)) }
        XCTAssertEqual(today.map(\.slot), [.first, .lastCall, .streakSaver])
    }

    /// Yesterday missed and carried as a rest day: tonight is the deadline.
    func test_theSaverComesWhenTodayIsTheLastDayARestDayCovers() {
        let sessions = [2, 3, 4].map { at(-$0, 9) }
        XCTAssertTrue(StreakCalculator.endsTonight(from: sessions, today: at(0, 7), calendar: cal))
        XCTAssertNotNil(saver(on: 0, in: plan(input(now: at(0, 7), sessions: sessions))))
    }

    /// A rest day is still free tonight, so missing today ends nothing yet:
    /// no saver tonight, and the saver comes tomorrow night instead.
    func test_noSaverWhileARestDayCanStillCarryTheStreak() {
        let sessions = (1...5).map { at(-$0, 9) }
        XCTAssertFalse(StreakCalculator.endsTonight(from: sessions, today: at(0, 7), calendar: cal))
        let p = plan(input(now: at(0, 7), sessions: sessions))
        XCTAssertNil(saver(on: 0, in: p))
        XCTAssertNotNil(saver(on: 1, in: p), "tomorrow, with the rest day spent")
    }

    func test_noSaverOnceTodayIsDoneOrForOnceADayOrAOneDayStreak() {
        let sessions = [1, 2, 3, 5, 6, 7].map { at(-$0, 9) }
        XCTAssertFalse(StreakCalculator.endsTonight(from: sessions + [at(0, 6)], today: at(0, 7), calendar: cal))
        XCTAssertNil(saver(on: 0, in: plan(input(now: at(0, 7), sessions: sessions, cadence: .once))))
        // A one-day streak carried by a rest day ends tonight, but gets no
        // saver, as it gets no streak talk.
        XCTAssertTrue(StreakCalculator.endsTonight(from: [at(-2, 9)], today: at(0, 7), calendar: cal))
        XCTAssertNil(saver(on: 0, in: plan(input(now: at(0, 7), sessions: [at(-2, 9)]))))
    }

    func test_theSaverKeepsItsDistanceFromALateOwnTime() {
        XCTAssertEqual(ReminderPlanner.saverMinutes(anchor: 8 * 60), 23 * 60 + 30)
        XCTAssertNil(ReminderPlanner.saverMinutes(anchor: 22 * 60 + 30), "own time at 10:30 pm")
        XCTAssertNil(ReminderPlanner.saverMinutes(anchor: 21 * 60), "evening one pushed to 10:30 pm")
    }

    func test_noStreakTalkOnceTheStreakIsGone() {
        // Five days ending three days ago: broken, no rest day can carry it.
        let p = plan(input(now: at(0, 7), sessions: (3...7).map { at(-$0, 9) }))
        XCTAssertFalse(p.contains { $0.topic == .streak })
    }

    func test_heldAppsOnlyWhenBlockHoldsThem() {
        var i = input(now: at(0, 7), sessions: [at(-1, 9)])
        XCTAssertFalse(plan(i).contains { $0.topic == .apps })
        i.appsHeld = { _ in true }
        i.profile.obstacles = [.phonePulls]
        let p = (0..<20).flatMap { plan(i, seed: UInt64($0)) }
        XCTAssertTrue(p.contains { $0.topic == .apps })
    }

    func test_aTopicThatWorksIsChosenMore() {
        var i = input(now: at(0, 7), sessions: [at(-1, 9)])
        i.stats = [.glow: ReminderTopicStats(sends: 40, wins: 30),
                   .gentle: ReminderTopicStats(sends: 40, wins: 1)]
        let firsts = (0..<200).compactMap { plan(i, seed: UInt64($0)).first?.topic }
        let glow = firsts.filter { $0 == .glow }.count
        let gentle = firsts.filter { $0 == .gentle }.count
        XCTAssertGreaterThan(glow, gentle * 5, "glow \(glow), gentle \(gentle)")
    }

    func test_theSameTopicIsNotUsedEveryTime() {
        let p = plan(input(now: at(0, 6), sessions: [at(-1, 9)]))
        let topics = p.filter { $0.slot != .lastCall }.map(\.topic)
        XCTAssertGreaterThan(Set(topics).count, 1, "\(topics)")
    }

    func test_recoveryHoldsBackARecentTopic() {
        XCTAssertEqual(ReminderPlanner.recovery(daysSince: 0), 0.4, accuracy: 0.001)
        XCTAssertLessThan(ReminderPlanner.recovery(daysSince: 1), ReminderPlanner.recovery(daysSince: 3))
        XCTAssertGreaterThan(ReminderPlanner.recovery(daysSince: 7), 0.99)
    }

    func test_onboardingAnswersLeanThePriors() {
        let none = ReminderProfile()
        let quitter = ReminderProfile(obstacles: [.loseMotivation])
        XCTAssertGreaterThan(ReminderPlanner.prior(.streak, profile: quitter).a,
                             ReminderPlanner.prior(.streak, profile: none).a)
        XCTAssertEqual(ReminderPlanner.prior(.apps, profile: quitter).a,
                       ReminderPlanner.prior(.apps, profile: none).a,
                       "losing motivation says nothing about apps")
    }

    /// Every line, in every state: the house copy rules hold.
    func test_everyLineKeepsTheCopyRules() {
        let profile = ReminderProfile(motivations: Motivation.allCases, obstacles: Obstacle.allCases)
        let states = [
            ReminderPlanner.DayState(streak: 6, glow: 72, profile: profile),
            ReminderPlanner.DayState(streak: 3, restDayUsed: true, glow: 40, profile: profile),
            ReminderPlanner.DayState(streak: 0, glow: 18, daysAway: 5, appsHeld: true,
                                     nextHat: ("Bucket Hat", 23), profile: profile, rotation: 3),
        ]
        for state in states {
            for topic in ReminderTopic.allCases {
                for slot in [ReminderSlot.first, .followUp, .lastCall, .streakSaver] {
                    for line in ReminderCopy.lines(topic, slot: slot, state: state) {
                        let text = line.title + " " + line.body
                        XCTAssertFalse(text.contains("\u{2014}"), "em dash: \(text)")
                        XCTAssertFalse(text.lowercased().contains("five minute"), text)
                        XCTAssertFalse(text.contains("5 min"), text)
                        XCTAssertFalse(text.isEmpty)
                        XCTAssertLessThanOrEqual(line.title.count, 40, "title too long: \(line.title)")
                        XCTAssertLessThanOrEqual(line.body.count, 110, "body too long: \(line.body)")
                    }
                }
            }
        }
    }

    func test_aLowGlowIsNeverPrintedAsANumber() {
        let low = ReminderPlanner.DayState(glow: 12)
        for slot in [ReminderSlot.first, .followUp, .lastCall] {
            for topic in ReminderTopic.allCases {
                for line in ReminderCopy.lines(topic, slot: slot, state: low) {
                    XCTAssertFalse((line.title + line.body).contains("12%"), line.title)
                }
            }
        }
        XCTAssertTrue(ReminderCopy.lines(.glow, slot: .first, state: ReminderPlanner.DayState(glow: 64))
            .contains { $0.title.contains("64%") })
    }

    // MARK: The ledger

    func test_aReminderFollowedByASessionIsAWin() {
        var ledger = ReminderLedger()
        let r = PlannedReminder(id: "reminder.a", fireDate: at(0, 8), slot: .first, topic: .glow,
                                variant: 0, title: "", body: "")
        ledger.record([r])
        ledger.settle(now: at(0, 11), sessionStarts: [at(0, 9)], delivering: true)
        XCTAssertEqual(ledger.stats[.glow], ReminderTopicStats(sends: 1, wins: 1))
        XCTAssertEqual(ledger.lastUsed[.glow], at(0, 8))
    }

    func test_anIgnoredReminderIsALossOnceItsWindowCloses() {
        var ledger = ReminderLedger()
        ledger.record([PlannedReminder(id: "reminder.a", fireDate: at(0, 8), slot: .first, topic: .streak,
                                       variant: 0, title: "", body: "")])
        ledger.settle(now: at(0, 9), sessionStarts: [], delivering: true)
        XCTAssertNil(ledger.stats[.streak], "still inside its window")
        ledger.settle(now: at(0, 11), sessionStarts: [], delivering: true)
        XCTAssertEqual(ledger.stats[.streak], ReminderTopicStats(sends: 1, wins: 0))
    }

    func test_aTapIsAWin() {
        var ledger = ReminderLedger()
        ledger.record([PlannedReminder(id: "reminder.a", fireDate: at(0, 8), slot: .first, topic: .goal,
                                       variant: 0, title: "", body: "")])
        ledger.tapped.insert("reminder.a")
        ledger.settle(now: at(0, 8, 5), sessionStarts: [], delivering: true)
        XCTAssertEqual(ledger.stats[.goal], ReminderTopicStats(sends: 1, wins: 1))
        XCTAssertTrue(ledger.tapped.isEmpty)
    }

    func test_nothingCountsWhenNotificationsWereOff() {
        var ledger = ReminderLedger()
        ledger.record([PlannedReminder(id: "reminder.a", fireDate: at(0, 8), slot: .first, topic: .glow,
                                       variant: 0, title: "", body: "")])
        ledger.settle(now: at(1, 8), sessionStarts: [], delivering: false)
        XCTAssertTrue(ledger.stats.isEmpty)
        XCTAssertTrue(ledger.pending.isEmpty)
    }

    func test_aWithdrawnReminderNeverCounts() {
        var ledger = ReminderLedger()
        ledger.record([PlannedReminder(id: "reminder.a", fireDate: at(0, 8), slot: .first, topic: .glow,
                                       variant: 0, title: "", body: "")])
        ledger.withdraw(ids: ["reminder.a"])
        ledger.settle(now: at(1, 8), sessionStarts: [], delivering: true)
        XCTAssertTrue(ledger.stats.isEmpty)
    }
}
