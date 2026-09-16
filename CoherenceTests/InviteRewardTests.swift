import XCTest
import SwiftData
@testable import Coherence

/// Bring a friend, see the evidence. The rule, the ledger, and the
/// entitlement it unlocks, each pinned separately.
final class InviteRewardTests: XCTestCase {

    // MARK: The rule

    func test_onlyFriendsIAskedWhoHaveSatAreRewarded() {
        let facts: [InviteReward.FriendFact] = [
            .init(id: "a", iAskedFirst: true,  hasFirstSession: true),   // yes
            .init(id: "b", iAskedFirst: false, hasFirstSession: true),   // they invited me
            .init(id: "c", iAskedFirst: true,  hasFirstSession: false),  // accepted, never sat
            .init(id: "d", iAskedFirst: true,  hasFirstSession: true),   // already paid
        ]
        XCTAssertEqual(InviteReward.newlyRewardable(facts, alreadyRewarded: ["d"]), ["a"])
    }

    func test_grantStacksAndCaps() {
        XCTAssertEqual(InviteReward.granted(after: 0), 3)
        XCTAssertEqual(InviteReward.granted(after: 3), 6)
        XCTAssertEqual(InviteReward.granted(after: 13), 15, "capped at fifteen outstanding")
        XCTAssertEqual(InviteReward.granted(after: 15), 15)
    }

    // MARK: The ledger

    /// Held for the test's lifetime: a ModelContext does not keep its
    /// container alive, and a released container crashes the next fetch
    /// ("Failed to cast model").
    private var container: ModelContainer?

    @MainActor
    private func ledger() -> (RewardLedger, ModelContext) {
        let container = Persistence.inMemory()
        self.container = container
        let context = ModelContext(container)
        _ = SessionStore.currentUser(in: context)   // creates the Preferences row
        return (RewardLedger(context: context), context)
    }

    @MainActor
    func test_grantPaysOncePerFriend() {
        let (ledger, _) = ledger()
        XCTAssertEqual(ledger.remaining, 0)
        XCTAssertEqual(ledger.grant(forFriend: "profile-x"), 3)
        XCTAssertNil(ledger.grant(forFriend: "profile-x"), "the same friend never pays twice")
        XCTAssertEqual(ledger.grant(forFriend: "profile-y"), 6, "a second friend stacks")
        XCTAssertEqual(ledger.rewardedFriends, ["profile-x", "profile-y"])
        XCTAssertNotNil(ledger.since)
    }

    @MainActor
    func test_coverConsumesOnlyNewSessionsAndStaysCovered() {
        let (ledger, _) = ledger()
        let old = UUID(), new = UUID()
        XCTAssertFalse(ledger.cover(sessionID: new, startedAt: Date()), "nothing granted yet")

        ledger.grant(forFriend: "profile-x", at: Date())
        XCTAssertFalse(ledger.cover(sessionID: old, startedAt: Date().addingTimeInterval(-3_600)),
                       "a session from before the grant is not one of the NEXT three")
        XCTAssertTrue(ledger.cover(sessionID: new, startedAt: Date().addingTimeInterval(60)))
        XCTAssertEqual(ledger.remaining, 2)
        XCTAssertTrue(ledger.cover(sessionID: new, startedAt: Date().addingTimeInterval(60)))
        XCTAssertEqual(ledger.remaining, 2, "asking again for a covered session costs nothing")
    }

    @MainActor
    func test_coveredSessionOutlivesTheGrant() {
        let (ledger, _) = ledger()
        ledger.grant(forFriend: "profile-x", at: Date(timeIntervalSince1970: 0))
        var ids: [UUID] = []
        for _ in 0..<InviteReward.sessionsPerFriend {
            let id = UUID(); ids.append(id)
            XCTAssertTrue(ledger.cover(sessionID: id, startedAt: Date()))
        }
        XCTAssertEqual(ledger.remaining, 0)
        XCTAssertFalse(ledger.cover(sessionID: UUID(), startedAt: Date()), "the one after the grant is locked")
        XCTAssertTrue(ledger.cover(sessionID: ids[1], startedAt: Date()), "an earlier covered one still shows its evidence")
    }

    @MainActor
    func test_ledgerSurvivesReload() {
        let (ledger, context) = ledger()
        ledger.grant(forFriend: "profile-x")
        let again = RewardLedger(context: context)
        XCTAssertEqual(again.remaining, InviteReward.sessionsPerFriend)
        XCTAssertEqual(again.rewardedFriends, ["profile-x"])
    }

    // MARK: What it unlocks

    func test_grantUnlocksEvidenceAndNothingElse() {
        let free = Entitlements(paid: false).granting(true)
        XCTAssertTrue(free.curves)
        XCTAssertTrue(free.metrics)
        XCTAssertTrue(free.shareCurves)
        XCTAssertFalse(free.guidedTrack, "the reward is the evidence, not the guided track")
        XCTAssertFalse(free.canUse(.goldLeaf), "and not the skins")
        XCTAssertFalse(Entitlements(paid: false).granting(false).curves)
    }

    // MARK: The award

    func test_broughtAFriendIsAnAwardEarnedOnce() {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let earned = AwardEngine.evaluate(sessions: [], accountCreatedAt: Date(), friendBroughtAt: when)
        let award = earned.first { $0.award.id == "friendBrought" }
        XCTAssertEqual(award?.earnedAt, when)
        let none = AwardEngine.evaluate(sessions: [], accountCreatedAt: Date())
        XCTAssertFalse(none.first { $0.award.id == "friendBrought" }?.isEarned ?? true)
    }
}

final class RewardLedgerRowTests: XCTestCase {
    private var container: ModelContainer?

    /// With two Preferences rows, the ledger always writes and reads the
    /// oldest, so a grant can never land on one row and be read from another.
    @MainActor
    func test_ledgerUsesTheOldestPreferencesRow() {
        let c = Persistence.inMemory(); container = c
        let ctx = ModelContext(c)
        let old = Preferences(createdAt: Date(timeIntervalSince1970: 1_000))
        let new = Preferences(createdAt: Date())
        ctx.insert(new); ctx.insert(old); try? ctx.save()
        for _ in 0..<5 {
            let ledger = RewardLedger(context: ctx)
            ledger.grant(forFriend: "profile-x")
            XCTAssertEqual(ledger.remaining, InviteReward.sessionsPerFriend)
        }
        XCTAssertEqual(old.evidenceGrantRemaining, InviteReward.sessionsPerFriend)
        XCTAssertEqual(new.evidenceGrantRemaining, 0)
    }
}

@MainActor
final class FirstSessionStampTests: XCTestCase {
    /// A person who sat before creating a profile still counts as having sat,
    /// so whoever invited them is rewarded.
    func test_claimingStampsAnEarlierLocalSession() async throws {
        let db = MemoryCommunityDatabase(user: "_new")
        let model = CommunityModel(store: CommunityStore(database: db))
        let sat = Date(timeIntervalSince1970: 5_000)
        model.firstLocalSession = { sat }
        await model.load()
        XCTAssertEqual(model.phase, .needsUsername)
        let ok = await model.claim("newbie", displayName: "N")
        XCTAssertTrue(ok)
        let stamped = db.records[CommunityNames.profile(user: "_new")]?["firstSessionAt"] as? Date
        XCTAssertEqual(stamped, sat)
    }
}
