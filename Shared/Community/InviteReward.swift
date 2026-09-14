import Foundation
import SwiftData
import Combine

// Lives in Shared/ rather than Coherence/Community/ on purpose. The test
// target compiles Shared/ into itself, so a test's `Preferences` rows are the
// TEST bundle's class; a ledger in the app module fetches the APP's class and
// SwiftData traps casting one to the other ("Failed to cast model
// Coherence.Preferences"). Anything that fetches a Shared model and is tested
// against `Persistence.inMemory()` must live in Shared/ too.

/// The invite reward (COMMUNITY.md): bring a friend, see the evidence.
///
/// **Trigger:** a friend request I SENT was accepted AND that friend's public
/// profile shows a first session. Not on install, not on sign-up: Apple
/// rejects rewards for downloads, and a session is the thing we actually
/// want. Both facts are public records, so the phone verifies them itself.
///
/// **Reward:** ten sessions of the full results screen (curves, tiles,
/// readings, the locked share cards), per friend, stacking, capped at fifty
/// outstanding so a burst of invites cannot mint a year of premium. Everyone
/// earns it; a payer simply has nothing to unlock until a subscription
/// lapses. The "Brought a friend" award lands the same moment.
enum InviteReward {
    static let sessionsPerFriend = 10
    static let cap = 50

    struct FriendFact: Equatable {
        let id: String
        /// My edge is older than theirs: I asked, they accepted.
        let iAskedFirst: Bool
        let hasFirstSession: Bool
    }

    /// Pure rule: the friends who earn a grant now.
    static func newlyRewardable(_ friends: [FriendFact], alreadyRewarded: Set<String>) -> [String] {
        friends
            .filter { $0.iAskedFirst && $0.hasFirstSession && !alreadyRewarded.contains($0.id) }
            .map(\.id)
            .sorted()
    }

    /// Adds one friend's grant to a running total, under the cap.
    static func granted(after remaining: Int) -> Int {
        min(cap, remaining + sessionsPerFriend)
    }
}

/// The reward's storage, on the user's `Preferences` row (synced, so a new
/// phone keeps the balance). One instance, owned by `Store`, mirrored into
/// published values so `Entitlements` can be resolved without a fetch.
@MainActor
final class RewardLedger: ObservableObject {
    private let context: ModelContext
    @Published private(set) var remaining: Int = 0
    @Published private(set) var since: Date?
    @Published private(set) var granted: Set<UUID> = []
    @Published private(set) var rewardedFriends: Set<String> = []

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    func reload() {
        guard let prefs = prefs() else { return }
        remaining = prefs.evidenceGrantRemaining
        since = prefs.evidenceGrantSince
        granted = Set(prefs.grantedSessionIDs.compactMap(UUID.init(uuidString:)))
        rewardedFriends = Set(prefs.rewardedFriends)
    }

    private func prefs() -> Preferences? {
        (try? context.fetch(FetchDescriptor<Preferences>()))?.first
    }

    /// Pays out for one friend. Returns the new balance, or nil when this
    /// friend was already paid.
    @discardableResult
    func grant(forFriend id: String, at date: Date = Date()) -> Int? {
        guard let prefs = prefs(), !prefs.rewardedFriends.contains(id) else { return nil }
        prefs.rewardedFriends.append(id)
        prefs.evidenceGrantRemaining = InviteReward.granted(after: prefs.evidenceGrantRemaining)
        if prefs.evidenceGrantSince == nil { prefs.evidenceGrantSince = date }
        prefs.updatedAt = Date()
        try? context.save()
        reload()
        return remaining
    }

    /// Whether a session's evidence is covered by the grant, consuming one
    /// session of it the first time a NEW session (started after the grant)
    /// asks. Idempotent: a covered session stays covered for free.
    func cover(sessionID: UUID, startedAt: Date) -> Bool {
        if granted.contains(sessionID) { return true }
        guard let prefs = prefs(), prefs.evidenceGrantRemaining > 0,
              let since = prefs.evidenceGrantSince, startedAt >= since else { return false }
        prefs.grantedSessionIDs.append(sessionID.uuidString)
        prefs.evidenceGrantRemaining -= 1
        prefs.updatedAt = Date()
        try? context.save()
        reload()
        return true
    }
}
