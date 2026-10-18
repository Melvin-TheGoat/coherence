import Foundation

/// Meditating together (2026-10-14, Aziz; mockups `mockups/friend-goal-buttons.html`
/// and `mockups/friend-goals/`). Two friends agree on a number of days a week
/// they will EACH meditate; every week they both hit it, a shared streak grows.
///
/// This file is the arithmetic, pure Foundation, so it is tested without
/// CloudKit or SwiftData. The records live in `CommunityRecords.swift`; the
/// store and the screens read everything through here.
///
/// **The rules, all decided with Aziz, so nobody re-derives them:**
/// - One kind of goal: days each per week, 1 to 7.
/// - A week starts on the weekday the goal started (the day it was accepted),
///   not on Monday: say yes on a Thursday and every week runs Thursday to
///   Wednesday.
/// - A missed day breaks nothing. Only a week one of you fell short in ends
///   the streak, and the week still running never does.
/// - One session counts everywhere: every shared goal, the personal streak,
///   Otto's glow. Two sessions on one day are one day.
/// - A day counts for a shared goal only through a session of 5 minutes or
///   more (`minimumSeconds`, the same bar that opens Block's apps) that was
///   measured, not logged by hand: a typed-in session could fake one half of
///   a promise made to somebody else. Logged sessions still count for the
///   personal streak, as they always have.
/// - You can nudge only once you have meditated today, or once you have
///   already done your share of this week: a nudge from somebody who hasn't
///   meditated reads as nagging.
/// - Each person's days are THEIR local days, published as `yyyy-MM-dd` keys,
///   so a friend in another time zone is never judged by your clock.
enum SharedGoal {
    /// The shortest session that counts for a shared goal, in seconds.
    /// Kept equal to `Blocker.sessionMinutes` (Block's bar) on purpose.
    static let minimumSeconds = 5 * 60
    static let targets = 1...7
    static let defaultTarget = 4
}

/// One local day someone meditated on, and for how long. Published on that
/// person's own goal record as `"yyyy-MM-dd:minutes"`.
struct GoalDay: Equatable, Hashable {
    let day: String
    let minutes: Int

    var encoded: String { "\(day):\(minutes)" }

    init(day: String, minutes: Int) { self.day = day; self.minutes = minutes }

    init?(encoded: String) {
        let parts = encoded.split(separator: ":")
        guard parts.count == 2, DayKey.date(String(parts[0])) != nil, let m = Int(parts[1]) else { return nil }
        self.init(day: String(parts[0]), minutes: max(0, m))
    }

    /// The qualifying days from a person's sessions, from `since` (a day
    /// key, inclusive) through today: one entry per local day with at least
    /// one session of `SharedGoal.minimumSeconds` that was not logged by
    /// hand, its minutes summed over those sessions. Oldest first.
    static func qualifying(from sessions: [(startedAt: Date, durationSec: Int, logged: Bool)],
                           since: String, now: Date = Date(), calendar: Calendar = .current) -> [GoalDay] {
        let today = DayKey.key(now, calendar: calendar)
        var minutes: [String: Int] = [:]
        for s in sessions where !s.logged && s.durationSec >= SharedGoal.minimumSeconds {
            let key = DayKey.key(s.startedAt, calendar: calendar)
            guard key >= since, key <= today else { continue }
            minutes[key, default: 0] += s.durationSec / 60
        }
        return minutes.keys.sorted().map { GoalDay(day: $0, minutes: minutes[$0] ?? 0) }
    }
}

/// `yyyy-MM-dd` day keys and arithmetic on them. A key is a local calendar
/// day with no time zone attached, so two people's keys compare as days, and
/// adding days to one never crosses a daylight-saving hour.
enum DayKey {
    /// A fixed Gregorian calendar in UTC, for arithmetic on keys only.
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Always the GREGORIAN date in the calendar's time zone: a phone set to
    /// the Japanese or Buddhist calendar would otherwise write "0008-10-18"
    /// or "2569-10-18", which no friend's key and no arithmetic here agrees
    /// with (found in review, 2026-10-18).
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Midnight UTC of the key's day, for arithmetic. nil for a malformed key.
    static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func adding(_ days: Int, to key: String) -> String {
        guard let d = date(key), let moved = utc.date(byAdding: .day, value: days, to: d) else { return key }
        return Self.key(moved, calendar: utc)
    }

    /// Whole days from `a` to `b` (negative when `b` is earlier).
    static func distance(from a: String, to b: String) -> Int {
        guard let da = date(a), let db = date(b) else { return 0 }
        return utc.dateComponents([.day], from: da, to: db).day ?? 0
    }

    /// The weekday of a key, 1 = Sunday ... 7 = Saturday (Calendar's numbering).
    static func weekday(_ key: String) -> Int {
        guard let d = date(key) else { return 1 }
        return utc.component(.weekday, from: d)
    }

    /// "Mon", "Tue"... for a key, in the user's language.
    static func shortWeekday(_ key: String, calendar: Calendar = .current) -> String {
        let symbols = calendar.shortWeekdaySymbols
        let i = weekday(key) - 1
        return symbols.indices.contains(i) ? symbols[i] : ""
    }

    /// "Monday", "Thursday"... for a key.
    static func weekdayName(_ key: String, calendar: Calendar = .current) -> String {
        let symbols = calendar.weekdaySymbols
        let i = weekday(key) - 1
        return symbols.indices.contains(i) ? symbols[i] : ""
    }
}

/// A shared goal as both halves describe it, and everything the screens show
/// about it. Built from the two `GoalHalf` records by `CommunityStore`.
struct GoalPair: Identifiable, Equatable {
    enum State: Equatable {
        /// I asked; they have not answered.
        case waitingForThem
        /// They asked me; I have not answered.
        case waitingForMe
        /// Both in. The weeks are counting.
        case active
        /// They said "Not now", or either of us ended it.
        case over
    }

    let id: String
    let partner: String
    let target: Int
    /// The first day of week one, a day key. nil until the goal is accepted.
    let startDay: String?
    let state: State
    let myDays: [GoalDay]
    let theirDays: [GoalDay]
    /// Who asked, for "Maya wants to meditate with you".
    let invitedByMe: Bool
    let createdAt: Date

    /// The week containing `today` (a key), as its index from the start and
    /// its first and last day. Week 0 before the start (a goal accepted
    /// "today" has today as its first day).
    func week(containing today: String) -> (index: Int, first: String, last: String)? {
        guard let start = startDay else { return nil }
        let offset = max(0, DayKey.distance(from: start, to: today))
        let index = offset / 7
        let first = DayKey.adding(index * 7, to: start)
        return (index, first, DayKey.adding(6, to: first))
    }

    /// Days done in a week: how many distinct days between `first` and `last`.
    static func count(_ days: [GoalDay], from first: String, to last: String) -> Int {
        Set(days.map(\.day).filter { $0 >= first && $0 <= last }).count
    }

    static func minutes(_ days: [GoalDay], from first: String, to last: String) -> Int {
        days.filter { $0.day >= first && $0.day <= last }.reduce(0) { $0 + $1.minutes }
    }

    /// Where the week stands for both of us, at `today`.
    struct Week: Equatable {
        let index: Int
        let first: String
        let last: String
        let mine: Int
        let theirs: Int
        let target: Int
        let minutesMine: Int
        let minutesTheirs: Int
        /// Days left including today.
        let daysLeft: Int
        var bothDone: Bool { mine >= target && theirs >= target }
        /// Combined, for the card: "5 of 8".
        var together: Int { min(mine, target) + min(theirs, target) }
        var togetherTarget: Int { target * 2 }
        /// The seven days of this week, oldest first.
        var dayKeys: [String] { (0..<7).map { DayKey.adding($0, to: first) } }
    }

    func thisWeek(today: String) -> Week? {
        guard let w = week(containing: today) else { return nil }
        return Week(index: w.index, first: w.first, last: w.last,
                    mine: Self.count(myDays, from: w.first, to: w.last),
                    theirs: Self.count(theirDays, from: w.first, to: w.last),
                    target: target,
                    minutesMine: Self.minutes(myDays, from: w.first, to: w.last),
                    minutesTheirs: Self.minutes(theirDays, from: w.first, to: w.last),
                    // At most 7: a friend whose day is behind the
                    // accepter's can be "before" week one for a few hours.
                    daysLeft: min(7, max(0, DayKey.distance(from: today, to: w.last) + 1)))
    }

    /// The shared streak, in weeks.
    struct Streak: Equatable {
        /// Weeks in a row you both hit, counting this week once it is done.
        let current: Int
        let best: Int
        /// Still in the first week: the screens say "First week", never "0".
        let isFirstWeek: Bool
        /// The last up-to-8 weeks, oldest first: true when both hit it. The
        /// week still running is last and only true once both hit it.
        let history: [Bool]
        /// Whether the last entry of `history` is the week still running.
        let lastIsCurrent: Bool
    }

    func streak(today: String) -> Streak? {
        guard let w = week(containing: today) else { return nil }
        func done(_ k: Int) -> Bool {
            guard let start = startDay else { return false }
            let first = DayKey.adding(k * 7, to: start), last = DayKey.adding(6, to: first)
            return Self.count(myDays, from: first, to: last) >= target
                && Self.count(theirDays, from: first, to: last) >= target
        }
        let results = (0...w.index).map(done)
        // The week still running only ever adds; it never breaks the streak.
        var current = 0
        var k = results.count - 1
        if !results[k] { k -= 1 }
        while k >= 0, results[k] { current += 1; k -= 1 }
        var best = 0, run = 0
        for r in results { run = r ? run + 1 : 0; best = max(best, run) }
        return Streak(current: current, best: best, isFirstWeek: w.index == 0 && !results[0],
                      history: Array(results.suffix(8)), lastIsCurrent: true)
    }

    /// Whether I may nudge them today. Never when it is not running, never
    /// when they have already meditated today, never twice a day
    /// (`alreadyNudged`), and only once I have meditated today or already
    /// done my share of the week.
    func canNudge(today: String, theirToday: String? = nil, alreadyNudged: Bool) -> NudgeState {
        guard state == .active, let week = thisWeek(today: today) else { return .unavailable }
        let theirs = theirToday ?? today
        if theirDays.contains(where: { $0.day == theirs }) { return .theyMeditated }
        if alreadyNudged { return .alreadyNudged }
        let meditatedToday = myDays.contains { $0.day == today }
        return meditatedToday || week.mine >= target ? .ready : .meditateFirst
    }

    enum NudgeState: Equatable {
        case ready, meditateFirst, alreadyNudged, theyMeditated, unavailable
    }
}

/// The reward screen's line, "Counted for Ana and Daniel".
enum CountedFor {
    static func line(_ names: [String]) -> String? {
        let names = names.filter { !$0.isEmpty }
        switch names.count {
        case 0: return nil
        case 1: return "Counted for \(names[0])"
        case 2: return "Counted for \(names[0]) and \(names[1])"
        default: return "Counted for \(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }
}
