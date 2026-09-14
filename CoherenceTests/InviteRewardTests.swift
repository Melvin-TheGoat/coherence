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
        XCTAssertEqual(InviteReward.granted(after: 0), 10)
        XCTAssertEqual(InviteReward.granted(after: 10), 20)
        XCTAssertEqual(InviteReward.granted(after: 45), 50, "capped at fifty outstanding")
        XCTAssertEqual(InviteReward.granted(after: 50), 50)
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
        XCTAssertEqual(ledger.grant(forFriend: "profile-x"), 10)
        XCTAssertNil(ledger.grant(forFriend: "profile-x"), "the same friend never pays twice")
        XCTAssertEqual(ledger.grant(forFriend: "profile-y"), 20)
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
                       "a session from before the grant is not one of the NEXT ten")
        XCTAssertTrue(ledger.cover(sessionID: new, startedAt: Date().addingTimeInterval(60)))
        XCTAssertEqual(ledger.remaining, 9)
        XCTAssertTrue(ledger.cover(sessionID: new, startedAt: Date().addingTimeInterval(60)))
        XCTAssertEqual(ledger.remaining, 9, "asking again for a covered session costs nothing")
    }

    @MainActor
    func test_coveredSessionOutlivesTheGrant() {
        let (ledger, _) = ledger()
        ledger.grant(forFriend: "profile-x", at: Date(timeIntervalSince1970: 0))
        var ids: [UUID] = []
        for _ in 0..<10 {
            let id = UUID(); ids.append(id)
            XCTAssertTrue(ledger.cover(sessionID: id, startedAt: Date()))
        }
        XCTAssertEqual(ledger.remaining, 0)
        XCTAssertFalse(ledger.cover(sessionID: UUID(), startedAt: Date()), "the eleventh is locked")
        XCTAssertTrue(ledger.cover(sessionID: ids[3], startedAt: Date()), "the fourth still shows its evidence")
    }

    @MainActor
    func test_ledgerSurvivesReload() {
        let (ledger, context) = ledger()
        ledger.grant(forFriend: "profile-x")
        let again = RewardLedger(context: context)
        XCTAssertEqual(again.remaining, 10)
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
