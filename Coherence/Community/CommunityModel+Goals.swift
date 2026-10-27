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
            goalsLoaded = true
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
        // A week finished is noticed here, after every load and every
        // session landing, whether or not anything new needed publishing.
        defer { noteFinishedWeeks() }
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
            Analytics.track(.goalInvited(target: target))
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
            Analytics.track(.goalInviteAnswered(accepted: true))
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
            Analytics.track(.goalInviteAnswered(accepted: false))
            markSeen("invite-" + goal.id)
            await refreshGoals(store)
            return true
        } catch { errorText = Self.plain(error); return false }
    }

    func endGoal(_ goal: GoalPair) async {
        guard let store else { return }
        do {
            try await store.endGoal(goal, myName: myAlertName)
            Analytics.track(.goalEnded(wasRunning: goal.state == .active))
            await refreshGoals(store)
        } catch { errorText = Self.plain(error) }
    }

    /// Nudge, or high-five once the week is done. Once a day per friend.
    /// True when it went out (or today's had already gone).
    @discardableResult
    func nudge(_ goal: GoalPair, kind: Nudge.Kind) async -> Bool {
        guard let store else { return false }
        do {
            let sent = try await store.nudge(goal.partner, kind: kind, today: todayKey, myName: myAlertName)
            // Today's had already gone from another device: not a new one.
            if sent { Analytics.track(.nudgeSent(kind: kind == .cheer ? "high_five" : "nudge")) }
            nudgedToday.insert(goal.partner)
            return true
        } catch { errorText = Self.plain(error); return false }
    }

    // MARK: Friends awards and weeks finished together (2026-10-27)
    //
    // Melvin: "nothing happened when aziz and i just finished a full week
    // together. no notification no points no awards no nothing." What this
    // phone sees of Friends goes into `FriendsLedger` (UserDefaults, this
    // phone only) the first time it is seen, so the awards, the points and
    // the history last even when a friend or a goal is gone.
    //
    // Who hears about a finished week, and how:
    // - Whoever did their share second (`iFinishedLast`) finished it, so
    //   their phone tells the other one: a `week` record, which the other's
    //   subscription turns into a push. The same day breaks the tie by
    //   record name, so exactly one phone sends it.
    // - The one who finished it is in the app at that moment, or a Watch
    //   session landed with 808 in the background: the reward screen says it
    //   ("Week done with Aziz"), or, in the background, a local notification.
    // - The other gets the push; when they next open 808 the week is filed
    //   with no second notification, and any award it earned announces.
    // - The first look after updating files old weeks quietly (no unlock
    //   screens for things done months ago), but a week finished today or
    //   yesterday is still celebrated.

    /// The friends list as just loaded: the friend-count awards.
    func noteFriendCount(_ count: Int) {
        guard let me = myID else { return }
        var ledger = FriendsMemory.load()
        ledger.claim(for: me)
        // Friends made before this build are history, not news.
        if ledger.observe(friendCount: count) { silence(ledger) { $0.hasPrefix("friends") } }
        save(ledger)
    }

    /// No profile yet, so no goals: any goal from here on is news.
    func notePastGoalsQuietly() {
        guard let me = myID else { return }
        var ledger = FriendsMemory.load()
        ledger.claim(for: me)
        guard !ledger.goalsSeeded else { return }
        _ = ledger.observe(goalRunning: false, finished: [], celebrateFrom: todayKey)
        save(ledger)
    }

    /// Files every week finished together that this phone has not seen,
    /// tells the friend when I finished it, and returns the new ones. My
    /// days come from the sessions on this phone, which are fresher than
    /// the copy on my goal record until it is published.
    @discardableResult
    func noteFinishedWeeks() -> [TogetherWeek] {
        guard goalsLoaded, let me = myID else { return [] }
        var ledger = FriendsMemory.load()
        ledger.claim(for: me)
        let today = todayKey
        let sessions = goalSessions?() ?? []
        var finished: [TogetherWeek] = []
        var finishedByMe = Set<String>()
        for goal in activeGoals {
            let mine = GoalDay.qualifying(from: sessions, since: goal.startDay ?? DayKey.key(goal.createdAt))
            for w in goal.weekRecords(today: today, myDays: mine) {
                guard let day = w.finishedDay else { continue }
                let week = TogetherWeek(goalID: goal.id, partner: goal.partner,
                                        partnerName: shortName(goal.partner), index: w.index,
                                        first: w.first, last: w.last, target: goal.target,
                                        completedDay: day, seenAt: Date())
                finished.append(week)
                if w.iFinishedLast(me: me, partner: goal.partner) { finishedByMe.insert(week.id) }
            }
        }
        let firstLook = !ledger.goalsSeeded
        let yesterday = DayKey.adding(-1, to: today)
        let (fresh, _) = ledger.observe(goalRunning: !activeGoals.isEmpty, finished: finished,
                                        celebrateFrom: yesterday)
        if firstLook {
            // Silence what the quietly filed weeks earned, and a goal that
            // was already running; a week from today or yesterday still
            // announces.
            var quietOnly = ledger
            quietOnly.weeks.removeAll { w in fresh.contains { $0.id == w.id } }
            silence(quietOnly) { $0 == "goalStarted" || $0.hasPrefix("together") }
        }
        save(ledger)
        let paused = UserDefaults.standard.bool(forKey: Self.publishingPausedKey)
        for week in fresh where finishedByMe.contains(week.id) && week.completedDay >= yesterday && !paused {
            tell(week)
        }
        return fresh
    }

    /// The friends whose week this session finished, for the reward
    /// screen: weeks finished on the session's own day, seen since a little
    /// before it ended.
    func weeksFinished(bySessionStartedAt start: Date, endedAt end: Date) -> [TogetherWeek] {
        let day = DayKey.key(start)
        return FriendsMemory.load().weeks.filter {
            $0.completedDay == day && $0.seenAt >= end.addingTimeInterval(-600) && !rewardAnnounced.contains($0.id)
        }
    }

    /// My phone finished the week: their push, and mine. With 808 on
    /// screen the reward screen usually says it; a banner follows a few
    /// seconds later only if no reward did (the friend's days arrived after
    /// the reward was built, or the week was seen on opening the app).
    private func tell(_ week: TogetherWeek) {
        if let store {
            let name = myAlertName
            Task { try? await store.announceWeek(to: week.partner, first: week.first, myName: name) }
        }
        guard UIApplication.shared.applicationState == .active else { FriendsWeekNotice.post(week); return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            // A cancelled sleep throws and `try?` swallows it (CLAUDE.md).
            guard !Task.isCancelled, !rewardAnnounced.contains(week.id) else { return }
            FriendsWeekNotice.post(week)
        }
    }

    /// Marks the Friends awards `ledger` already earns as announced, so a
    /// first look backfills without a run of unlock screens.
    private func silence(_ ledger: FriendsLedger, _ wanted: (String) -> Bool) {
        for earned in AwardEngine.evaluate(sessions: [], accountCreatedAt: nil, social: ledger.facts)
        where earned.isEarned && wanted(earned.award.id) {
            AwardsInbox.markAnnounced(earned.award.id)
        }
    }

    private func save(_ ledger: FriendsLedger) {
        FriendsMemory.save(ledger)
        let facts = ledger.facts
        if friendFacts != facts { friendFacts = facts }
        if togetherBonus != ledger.bonusPoints { togetherBonus = ledger.bonusPoints }
    }

    /// The weeks finished with one friend, newest first, for their goal's page.
    func weeksTogether(with friend: String) -> [TogetherWeek] {
        FriendsMemory.load().weeks.filter { $0.partner == friend }.sorted { $0.first > $1.first }
    }

    // MARK: The reward screen

    /// The friends a session just counted for: everyone I have a running
    /// goal with, when the session qualifies (a minute or more, measured).
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
