import XCTest
import CloudKit
@testable import Coherence

/// Meditating together, through the store: two people over one fake public
/// database, the way `CommunityStoreTests` sets them up.
final class GoalStoreTests: XCTestCase {

    private var db: MemoryCommunityDatabase!
    private var aziz: CommunityStore!
    private var melvin: CommunityStore!
    private let azizID = CommunityNames.profile(user: "_aziz")
    private let melvinID = CommunityNames.profile(user: "_melvin")

    override func setUp() async throws {
        db = MemoryCommunityDatabase(user: "_aziz")
        aziz = CommunityStore(database: db.acting(as: "_aziz"))
        melvin = CommunityStore(database: db.acting(as: "_melvin"))
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)
    }

    private func goals(_ store: CommunityStore, friend: String) async throws -> [GoalPair] {
        try await store.goals(friends: [friend])
    }

    func test_inviteWaitsThenAcceptStartsTheWeekOnTheAcceptersDay() async throws {
        try await aziz.inviteGoal(to: melvinID, target: 4, myName: "Aziz")

        let mine = try await goals(aziz, friend: melvinID)
        XCTAssertEqual(mine.map(\.state), [.waitingForThem])
        let theirs = try await goals(melvin, friend: azizID)
        XCTAssertEqual(theirs.map(\.state), [.waitingForMe])
        XCTAssertEqual(theirs.first?.target, 4)

        try await melvin.acceptGoal(theirs[0], today: "2026-10-15", myName: "Melvin")
        let active = try await goals(aziz, friend: melvinID)
        XCTAssertEqual(active.first?.state, .active)
        XCTAssertEqual(active.first?.startDay, "2026-10-15")
        XCTAssertTrue(active.first?.invitedByMe == true)
    }

    func test_daysPublishedByOneSideReachTheOther() async throws {
        try await aziz.inviteGoal(to: melvinID, target: 3, myName: "Aziz")
        let invite = try await goals(melvin, friend: azizID)[0]
        try await melvin.acceptGoal(invite, today: "2026-10-15", myName: "Melvin")
        try await melvin.publishGoalDays(goal: invite.id, days: [GoalDay(day: "2026-10-15", minutes: 12)])
        try await aziz.publishGoalDays(goal: invite.id, days: [GoalDay(day: "2026-10-16", minutes: 20)])

        let seenByAziz = try await goals(aziz, friend: melvinID)[0]
        XCTAssertEqual(seenByAziz.myDays, [GoalDay(day: "2026-10-16", minutes: 20)])
        XCTAssertEqual(seenByAziz.theirDays, [GoalDay(day: "2026-10-15", minutes: 12)])
        let week = seenByAziz.thisWeek(today: "2026-10-16")!
        XCTAssertEqual(week.together, 2)
    }

    func test_notNowEndsItForBoth() async throws {
        try await aziz.inviteGoal(to: melvinID, target: 4, myName: "Aziz")
        let invite = try await goals(melvin, friend: azizID)[0]
        try await melvin.declineGoal(invite, myName: "Melvin")
        let a = try await goals(aziz, friend: melvinID)
        let m = try await goals(melvin, friend: azizID)
        XCTAssertEqual(a.map(\.state), [.over])
        XCTAssertEqual(m.map(\.state), [.over])
    }

    func test_endingARunningGoalEndsItForBoth_andWithdrawingAnInviteDeletesIt() async throws {
        try await aziz.inviteGoal(to: melvinID, target: 4, myName: "Aziz")
        let invite = try await goals(melvin, friend: azizID)[0]
        try await melvin.acceptGoal(invite, today: "2026-10-15", myName: "Melvin")
        let running = try await goals(aziz, friend: melvinID)[0]
        try await aziz.endGoal(running, myName: "Aziz")
        let after = try await goals(melvin, friend: azizID)
        XCTAssertEqual(after.map(\.state), [.over])

        try await aziz.inviteGoal(to: melvinID, target: 2, myName: "Aziz")
        let pending = try await goals(aziz, friend: melvinID).first { $0.state == .waitingForThem }!
        try await aziz.endGoal(pending, myName: "Aziz")
        XCTAssertNil(db.records[CommunityNames.goalMember(goal: pending.id, member: azizID)])
    }

    /// Aziz withdraws his invite in the same moment Melvin says yes: the
    /// answer on its own must not bring back a running goal for either of
    /// them (found in review, 2026-10-18).
    func test_aWithdrawnInviteStaysOverEvenIfItWasAcceptedInTheSameMoment() async throws {
        try await aziz.inviteGoal(to: melvinID, target: 4, myName: "Aziz")
        let invite = try await goals(melvin, friend: azizID)[0]
        let pending = try await goals(aziz, friend: melvinID)[0]
        try await aziz.endGoal(pending, myName: "Aziz")
        try await melvin.acceptGoal(invite, today: "2026-10-15", myName: "Melvin")
        let a = try await goals(aziz, friend: melvinID)
        let m = try await goals(melvin, friend: azizID)
        XCTAssertEqual(a.map(\.state), [.over])
        XCTAssertEqual(m.map(\.state), [.over])
    }

    func test_goalsWithSomeoneWhoIsNotAFriendAreHidden() async throws {
        try await aziz.inviteGoal(to: melvinID, target: 4, myName: "Aziz")
        let none = try await melvin.goals(friends: [])
        XCTAssertEqual(none, [])
    }

    func test_oneNudgeADay() async throws {
        let first = try await aziz.nudge(melvinID, kind: .nudge, today: "2026-10-15", myName: "Aziz")
        let second = try await aziz.nudge(melvinID, kind: .nudge, today: "2026-10-15", myName: "Aziz")
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let nudged = try await aziz.nudged(melvinID, today: "2026-10-15")
        XCTAssertTrue(nudged)
        let inbox = try await melvin.nudgesToMe()
        XCTAssertEqual(inbox.map(\.from), [azizID])
        XCTAssertEqual(inbox.first?.fromName, "Aziz")
    }

    /// A week finished together reaches the friend as one `week` record
    /// (their push), never as a nudge on screen, and telling it twice sends
    /// nothing new (2026-10-27).
    func test_aWeekFinishedIsToldOnceAndNeverShownAsANudge() async throws {
        try await melvin.announceWeek(to: azizID, first: "2026-10-15", myName: "Melvin")
        try await melvin.announceWeek(to: azizID, first: "2026-10-15", myName: "Melvin")
        let records = try await db.query(CommunityQuery(type: CommunityType.nudge,
                                                        filters: [.equals("to", .reference(azizID))],
                                                        sortField: "createdAt", ascending: false, limit: 30))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?["kind"] as? String, "week")
        XCTAssertEqual(records.first?["day"] as? String, Nudge.weekRecordDay,
                       "a day no older build shows as a nudge")
        let shown = try await aziz.nudgesToMe()
        XCTAssertTrue(shown.isEmpty)
    }

    func test_aBlockedPersonsNudgesNeverArrive() async throws {
        try await aziz.nudge(melvinID, kind: .nudge, today: "2026-10-15", myName: "Aziz")
        try await melvin.block(azizID)
        let inbox = try await melvin.nudgesToMe()
        XCTAssertEqual(inbox, [])
    }

    func test_deletingAnAccountTakesItsGoalHalvesAndNudges() async throws {
        let goal = try await aziz.inviteGoal(to: melvinID, target: 4, myName: "Aziz")
        try await aziz.nudge(melvinID, kind: .nudge, today: "2026-10-15", myName: "Aziz")
        try await aziz.deleteEverythingOfMine()
        XCTAssertNil(db.records[CommunityNames.goalMember(goal: goal, member: azizID)])
        XCTAssertNil(db.records[CommunityNames.nudge(from: azizID, to: melvinID, day: "2026-10-15")])
    }

    /// A goal record carries days and minutes only: never a score or
    /// anything measured off the body (the rule in CommunityRecords.swift).
    func test_goalRecordsCarryOnlyDaysAndMinutes() async throws {
        let goal = try await aziz.inviteGoal(to: melvinID, target: 4, myName: "Aziz")
        let record = try XCTUnwrap(db.records[CommunityNames.goalMember(goal: goal, member: azizID)])
        XCTAssertEqual(Set(record.allKeys()), ["goal", "member", "partner", "kind", "target",
                                                 "createdAt", "fromName", "days"])
    }
}
