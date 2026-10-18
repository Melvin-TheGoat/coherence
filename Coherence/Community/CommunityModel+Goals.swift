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
            goals = Self.onePerFriend(gs.filter { $0.state != .over })
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

    /// One goal per friend on screen. Two can exist when both friends asked
    /// each other before either saw the other's invite, or one of them asked
    /// twice from two phones: a running goal wins, then an invite to me (so
    /// it can be answered), then the oldest. Found in review, 2026-10-18.
    static func onePerFriend(_ goals: [GoalPair]) -> [GoalPair] {
        func rank(_ g: GoalPair) -> Int {
            switch g.state {
            case .active: return 0
            case .waitingForMe: return 1
            case .waitingForThem: return 2
            case .over: return 3
            }
        }
        var best: [String: GoalPair] = [:]
        for g in goals {
            if let kept = best[g.partner],
               (rank(kept), kept.createdAt) <= (rank(g), g.createdAt) { continue }
            best[g.partner] = g
        }
        return goals.filter { best[$0.partner]?.id == $0.id }
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
        // Never a second goal with the same friend: if they already asked
        // me, saying yes to theirs is what this person meant.
        if let existing = goal(with: friend) {
            if existing.state == .waitingForMe { await acceptGoal(existing) }
            return true
        }
        do {
            try await store.inviteGoal(to: friend, target: target, myName: myAlertName)
            await refreshGoals(store)
            return true
        } catch { errorText = Self.plain(error); return false }
    }

    /// True when the answer reached iCloud.
    @discardableResult
    func acceptGoal(_ goal: GoalPair) async -> Bool {
        guard let store else { return false }
        do {
            try await store.acceptGoal(goal, today: todayKey, myName: myAlertName)
            markSeen("invite-" + goal.id)
            await refreshGoals(store)
            return true
        } catch { errorText = Self.plain(error); return false }
    }

    @discardableResult
    func declineGoal(_ goal: GoalPair) async -> Bool {
        guard let store else { return false }
        do {
            try await store.declineGoal(goal, myName: myAlertName)
            markSeen("invite-" + goal.id)
            await refreshGoals(store)
            return true
        } catch { errorText = Self.plain(error); return false }
    }

    func endGoal(_ goal: GoalPair) async {
        guard let store else { return }
        do {
            try await store.endGoal(goal, myName: myAlertName)
            await refreshGoals(store)
        } catch { errorText = Self.plain(error) }
    }

    /// Nudge, or high-five once the week is done. Once a day per friend.
    /// True when it went out (or today's had already gone).
    @discardableResult
    func nudge(_ goal: GoalPair, kind: Nudge.Kind) async -> Bool {
        guard let store else { return false }
        do {
            _ = try await store.nudge(goal.partner, kind: kind, today: todayKey, myName: myAlertName)
            nudgedToday.insert(goal.partner)
            return true
        } catch { errorText = Self.plain(error); return false }
    }

    // MARK: The reward screen

    /// The friends a session just counted for: everyone I have a running
    /// goal with, when the session qualifies (5 minutes or more, measured).
    /// Only goals that had started by the session's own day: a friend a
    /// time zone ahead can accept on a day that is still tomorrow here, and
    /// a late Watch payload can predate the goal (2026-10-18 review).
    func countedFor(seconds: Int, logged: Bool, startedAt: Date) -> [String] {
        guard !logged, seconds >= SharedGoal.minimumSeconds else { return [] }
        let day = DayKey.key(startedAt)
        return activeGoals.filter { ($0.startDay ?? day) <= day }.map { shortName($0.partner) }
    }

    // MARK: The badge on Home

    static let seenKey = "community.seen.v1"

    /// Kept in the order things were seen, so trimming drops the OLDEST.
    /// It was trimmed from an unordered set, which could drop any id once
    /// past 400, and a running goal's "said yes" would come back as news.
    private var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []) }
        set {
            let old = UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []
            let kept = old.filter(newValue.contains)
            let added = newValue.subtracting(old).sorted()
            UserDefaults.standard.set(Array((kept + added).suffix(400)), forKey: Self.seenKey)
        }
    }

    /// Everything that counts as news, as stable ids.
    private var newsIDs: [String] {
        incoming.map { "request-" + $0 }
            + goalInvites.map { "invite-" + $0.id }
            + activeGoals.filter(\.invitedByMe).map { "accepted-" + $0.id }
            + nudgesToMe.filter { $0.day >= DayKey.adding(-2, to: todayKey) }.map { "nudge-" + $0.id }
            // Someone joined with my invite code (2026-10-18).
            + joinedWithCode.sorted().map { "joined-" + $0 }
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
