import Foundation

/// What a person's PUBLIC profile says about how often they meditate
/// (Melvin, 2026-09-27: "you can... see how often someone meditates").
///
/// **Never a score, a heart rate, a breathing rate, or anything measured off
/// the body** — see CLAUDE.md, "NEVER track a biometric", and the field rule
/// at the top of `CommunityRecords.swift`. Sessions and their length are not
/// a biometric: they are the same facts the app already shows on Home and
/// Profile (the streak, the week, the total), just published to a friend.
///
/// Every LOCAL session counts towards it, Watch, phone, and hand-logged
/// alike — the same set `StreakCalculator` reads, so a no-Watch user's
/// practice still shows.
///
/// Pure Foundation only, over `(startedAt, durationSec)` pairs — no
/// SwiftData, no CloudKit — so it is testable without any store at all.
struct PracticeStats: Equatable, Codable {
    /// Sessions started in the last 7 days (today counts as one of them).
    var sessions7d: Int
    /// Minutes practiced in the same window.
    var minutes7d: Int
    /// The current streak, exactly as `StreakCalculator.streak(from:)` reads
    /// it (same rest-day forgiveness rule).
    var currentStreak: Int
    /// Every session ever, on this phone.
    var totalSessions: Int
    /// When the most recent session started, nil for nobody yet.
    var lastSessionAt: Date?

    static let empty = PracticeStats(sessions7d: 0, minutes7d: 0, currentStreak: 0,
                                     totalSessions: 0, lastSessionAt: nil)

    /// The pure computation. `sessions` is every local session's start time
    /// and length — Watch, phone and hand-logged all count, unfiltered,
    /// which is what makes a no-Watch user's practice still visible to a
    /// friend.
    static func compute(from sessions: [(startedAt: Date, durationSec: Int)],
                        now: Date = Date(), calendar: Calendar = .current) -> PracticeStats {
        guard !sessions.isEmpty else { return .empty }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)
            ?? now.addingTimeInterval(-7 * 24 * 3_600)
        let recent = sessions.filter { $0.startedAt >= weekAgo && $0.startedAt <= now }
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt), today: now,
                                             calendar: calendar).current
        return PracticeStats(sessions7d: recent.count,
                             minutes7d: recent.reduce(0) { $0 + $1.durationSec } / 60,
                             currentStreak: streak,
                             totalSessions: sessions.count,
                             lastSessionAt: sessions.map(\.startedAt).max())
    }

    /// These numbers as they stand at `now` for someone READING them: they
    /// were published when the person last opened 808, and nothing updates
    /// them while they stay away, so "5 sessions this week, 9 day streak"
    /// would otherwise read true forever. Judged from `lastSessionAt` alone,
    /// the only date on the record:
    /// - the streak is over once the last session is before the day before
    ///   yesterday (yesterday may be their rest day, the streak's own rule);
    /// - the week's counts are zero once the last session is over 7 days old.
    func asSeen(now: Date = Date(), calendar: Calendar = .current) -> PracticeStats {
        guard let last = lastSessionAt else { return self }
        var seen = self
        let today = calendar.startOfDay(for: now)
        if let dayBefore = calendar.date(byAdding: .day, value: -2, to: today), last < dayBefore {
            seen.currentStreak = 0
        }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)
            ?? now.addingTimeInterval(-7 * 24 * 3_600)
        if last < weekAgo {
            seen.sessions7d = 0
            seen.minutes7d = 0
        }
        return seen
    }
}
