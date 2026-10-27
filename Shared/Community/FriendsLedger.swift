import Foundation

/// What this phone remembers about Friends, so the friend awards and the
/// weeks finished together last (Melvin, 2026-10-27: "We need more awards...
/// added your first friend, 5 friends, 10 friends... nothing happened when
/// aziz and i just finished a full week together. no notification no points
/// no awards no nothing").
///
/// Every other award is derived from the sessions on this phone. These come
/// from the public Friends database instead, which changes under us: a friend
/// can be removed, a goal ended and its records deleted. Awards ask "did this
/// ever happen" (`AwardEngine`), so a fact is written down here the first
/// time it is seen and kept. Points for a finished week are derived from the
/// weeks kept here, the way the rest of the points are derived from sessions.
///
/// UserDefaults, this phone only, like `AwardsInbox`. Nothing here is a health
/// value, and none of it leaves the phone. A new phone builds it again from
/// what the goals still show; a week from a goal ended before then is not
/// recovered, which costs its points there and nothing else.
struct FriendsLedger: Codable, Equatable {
    /// The Friends identity this is about (`CommunityStore.me()`). Someone
    /// else's iCloud account on this phone starts a ledger of its own.
    var owner: String?
    /// When the number of friends first reached 1, 2, 3...: element k is
    /// when it first reached k + 1. Only ever grows.
    var friendCountReached: [Date] = []
    /// When a shared goal was first seen running.
    var firstGoalAt: Date?
    /// Every week finished together, oldest first.
    var weeks: [TogetherWeek] = []
    /// The first look backfills without celebrating, one flag per fact,
    /// because friends and goals are loaded at different moments.
    var friendsSeeded = false
    var goalsSeeded = false

    /// Points for one week finished together, on top of a point a minute.
    static let pointsPerWeek = 50

    var bonusPoints: Int { weeks.count * Self.pointsPerWeek }

    /// What the awards read.
    var facts: AwardEngine.SocialFacts {
        AwardEngine.SocialFacts(friendCountReached: friendCountReached,
                                goalStartedAt: firstGoalAt,
                                weeksTogether: weeks.map(\.seenAt).sorted())
    }

    /// Starts over for a different person, keeps everything for the same one.
    mutating func claim(for owner: String) {
        guard self.owner != owner else { return }
        self = FriendsLedger()
        self.owner = owner
    }

    /// The friends list as just loaded. Returns whether this was the first
    /// look (the caller announces nothing then).
    @discardableResult
    mutating func observe(friendCount: Int, now: Date = Date()) -> Bool {
        let first = !friendsSeeded
        friendsSeeded = true
        while friendCountReached.count < friendCount { friendCountReached.append(now) }
        return first
    }

    /// The goals as just loaded: whether one is running, and every week
    /// either of us can see was finished. Returns the weeks seen for the
    /// first time, split in two: on the first look, a week finished before
    /// `celebrateFrom` (yesterday's day key, from the caller) is filed
    /// quietly, so a week that just happened is still celebrated and months
    /// of old ones are not. Day keys compare as strings (`yyyy-MM-dd`).
    mutating func observe(goalRunning: Bool, finished: [TogetherWeek], celebrateFrom: String,
                          now: Date = Date()) -> (new: [TogetherWeek], quiet: [TogetherWeek]) {
        let first = !goalsSeeded
        goalsSeeded = true
        if goalRunning, firstGoalAt == nil { firstGoalAt = now }
        let known = Set(weeks.map(\.id))
        var fresh: [TogetherWeek] = [], quiet: [TogetherWeek] = []
        for var week in finished where !known.contains(week.id) {
            week.seenAt = now
            weeks.append(week)
            if first && week.completedDay < celebrateFrom { quiet.append(week) } else { fresh.append(week) }
        }
        return (fresh, quiet)
    }
}

/// One week two friends both finished.
struct TogetherWeek: Codable, Equatable, Identifiable {
    var goalID: String
    /// The friend's Friends record name, and their first name as it was.
    var partner: String
    var partnerName: String
    /// From the goal's start: 0 is week one.
    var index: Int
    /// The week's first and last day, day keys.
    var first: String
    var last: String
    var target: Int
    /// The day the second of us did our share, a day key.
    var completedDay: String
    /// When this phone first saw it finished.
    var seenAt: Date

    var id: String { goalID + "#" + String(index) }
}

/// Where the ledger lives.
enum FriendsMemory {
    static let key = "friends.ledger.v1"

    static func load(_ defaults: UserDefaults = .standard) -> FriendsLedger {
        guard let data = defaults.data(forKey: key),
              let ledger = try? JSONDecoder().decode(FriendsLedger.self, from: data) else { return FriendsLedger() }
        return ledger
    }

    static func save(_ ledger: FriendsLedger, _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: key)
    }

    /// The account was deleted: the next person here starts from nothing.
    static func forget(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// Points from weeks finished together, for every balance in the app.
    static func bonusPoints(_ defaults: UserDefaults = .standard) -> Int { load(defaults).bonusPoints }
}
