import Foundation
import UIKit

/// Meditating together on the model (2026-10-14): loading goals and nudges,
/// answering invites, nudging, publishing my days after a session, the badge
/// on Home's Friends circle, and the names for the reward screen's line.
/// The arithmetic is `SharedGoal.swift`; the records, `CommunityRecords.swift`.
extension Notification.Name {
    /// A CloudKit push about a goal or a nudge arrived with 808 open.
    static let communityNewsArrived = Notification.Name("808.communityNewsArrived")
    /// A CloudKit push about a goal or a nudge was tapped: open Friends.
    static let openFriends = Notification.Name("808.openFriends")
}

extension CommunityModel {

    /// My local day, as a key.
    var todayKey: String { DayKey.key(Date()) }

    /// What I'm called in a push alert to a friend.
    var myAlertName: String {
        let name = profile?.displayName ?? ""
        return name.isEmpty ? "@" + (profile?.username ?? "A friend") : name
    }

    /// A person's first name or handle, for "Nudge Ana".
    func shortName(_ id: String) -> String {
        guard let p = person(id) else { return "your friend" }
        let first = p.displayName.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "@" + p.username : first
    }

    func goal(_ id: String) -> GoalPair? { goals.first { $0.id == id } }

    /// The running or pending goal with a friend, if any (one per friend).
    func goal(with friend: String) -> GoalPair? {
        goals.first { $0.partner == friend && $0.state != .over }
    }

    var activeGoals: [GoalPair] { goals.filter { $0.state == .active } }
    /// The cards in "Meditating together": running goals and invites I sent.
    var togetherGoals: [GoalPair] { goals.filter { $0.state == .active || $0.state == .waitingForThem } }
    /// Invites to me, waiting for an answer, for Requests.
    var goalInvites: [GoalPair] { goals.filter { $0.state == .waitingForMe } }

    // MARK: Loading

    func refreshGoals(_ store: CommunityStore) async {
        do {
            async let g = store.goals(friends: Set(friends))
            async let n = store.nudgesToMe()
            let (gs, ns) = try await (g, n)
            goals = gs.filter { $0.state != .over }
            nudgesToMe = ns
            var nudged = Set<String>()
            for goal in activeGoals where (try? await store.nudged(goal.partner, today: todayKey)) == true {
                nudged.insert(goal.partner)
            }
            nudgedToday = nudged
            try? await cache(names: Set(goals.map(\.partner) + ns.map(\.from)))
        } catch {
            // Leaves the last good goals on screen.
        }
        recountUnseen()
        await publishGoalDays()
    }

    /// Publishes my qualifying days on my half of every goal I'm in, from
    /// the goal's first day (or from my invite, while it waits).
    func publishGoalDays() async {
        guard let store, phase == .ready, let goalSessions else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.publishingPausedKey),
              !defaults.bool(forKey: Self.pendingDeletionKey) else { return }
        let sessions = goalSessions()
        for goal in goals where goal.state == .active || goal.state == .waitingForThem {
            let since = goal.startDay ?? DayKey.key(goal.createdAt)
            let days = GoalDay.qualifying(from: sessions, since: since)
            guard days != goal.myDays else { continue }
            try? await store.publishGoalDays(goal: goal.id, days: days)
            if let i = goals.firstIndex(where: { $0.id == goal.id }) {
                let g = goals[i]
                goals[i] = GoalPair(id: g.id, partner: g.partner, target: g.target, startDay: g.startDay,
                                    state: g.state, myDays: days, theirDays: g.theirDays,
                                    invitedByMe: g.invitedByMe, createdAt: g.createdAt)
            }
        }
    }

    /// Push alerts for invites, answers and nudges. Asked for once a profile
    /// exists; iOS shows them only with notification permission.
    func subscribeToGoalNews() async {
        guard let store, phase == .ready, hasProfile else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await store.subscribeToGoalNews()
    }

    // MARK: Acting

    /// Ask a friend. Returns true when the invite went out.
    func inviteGoal(_ friend: String, target: Int) async -> Bool {
        guard let store else { return false }
        do {
            try await store.inviteGoal(to: friend, target: target, myName: myAlertName)
            await refreshGoals(store)
            return true
        } catch { errorText = Self.plain(error); return false }
    }

    func acceptGoal(_ goal: GoalPair) async {
        guard let store else { return }
        do {
            try await store.acceptGoal(goal, today: todayKey, myName: myAlertName)
            markSeen("invite-" + goal.id)
            await refreshGoals(store)
        } catch { errorText = Self.plain(error) }
    }

    func declineGoal(_ goal: GoalPair) async {
        guard let store else { return }
        do {
            try await store.declineGoal(goal, myName: myAlertName)
            markSeen("invite-" + goal.id)
            await refreshGoals(store)
        } catch { errorText = Self.plain(error) }
    }

    func endGoal(_ goal: GoalPair) async {
        guard let store else { return }
        do {
            try await store.endGoal(goal, myName: myAlertName)
            await refreshGoals(store)
        } catch { errorText = Self.plain(error) }
    }

    /// Nudge, or high-five once the week is done. Once a day per friend.
    func nudge(_ goal: GoalPair, kind: Nudge.Kind) async {
        guard let store else { return }
        do {
            _ = try await store.nudge(goal.partner, kind: kind, today: todayKey, myName: myAlertName)
            nudgedToday.insert(goal.partner)
        } catch { errorText = Self.plain(error) }
    }

    // MARK: The reward screen

    /// The friends a session just counted for: everyone I have a running
    /// goal with, when the session qualifies (5 minutes or more, measured).
    func countedFor(seconds: Int, logged: Bool) -> [String] {
        guard !logged, seconds >= SharedGoal.minimumSeconds else { return [] }
        return activeGoals.map { shortName($0.partner) }
    }

    // MARK: The badge on Home

    private static let seenKey = "community.seen.v1"

    private var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(400)), forKey: Self.seenKey) }
    }

    /// Everything that counts as news, as stable ids.
    private var newsIDs: [String] {
        incoming.map { "request-" + $0 }
            + goalInvites.map { "invite-" + $0.id }
            + activeGoals.filter(\.invitedByMe).map { "accepted-" + $0.id }
            + nudgesToMe.filter { $0.day >= DayKey.adding(-2, to: todayKey) }.map { "nudge-" + $0.id }
    }

    func recountUnseen() {
        let s = seen
        unseenCount = newsIDs.filter { !s.contains($0) }.count
    }

    private func markSeen(_ id: String) {
        seen = seen.union([id])
        recountUnseen()
    }

    /// Friends opened: the badge clears. Answers I had not seen yet keep
    /// their "said yes" tag on the card for the rest of this launch.
    func markNewsSeen() {
        let s = seen
        freshlyAccepted.formUnion(activeGoals.filter { $0.invitedByMe && !s.contains("accepted-" + $0.id) }.map(\.id))
        seen = s.union(newsIDs)
        recountUnseen()
    }

    /// The latest nudge or high five from a friend today, for the goal page.
    func todaysNudge(from friend: String) -> Nudge? {
        nudgesToMe.first { $0.from == friend && $0.day >= DayKey.adding(-1, to: todayKey) }
    }
}
