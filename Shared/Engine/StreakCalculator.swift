import Foundation

/// Derives meditation streaks from raw Session start dates.
///
/// Streak is **not** stored — it is computed at read time from the user's
/// Session `startedAt` values. This keeps a single source of truth (Sessions)
/// and removes the write-time streak bookkeeping the pipeline used to carry.
///
/// Pure Foundation only — no SwiftData, HealthKit, or UI. Deterministic:
/// pass an explicit `today`/`calendar` in tests.
enum StreakCalculator {

    /// Returns the current and longest consecutive-day streaks.
    ///
    /// - `current`: length of the run of consecutive calendar days ending at
    ///   the anchor. The anchor is `today` if the user meditated today, else
    ///   yesterday if they meditated yesterday, else there is no live streak
    ///   (returns 0). Walks backward from the anchor counting present days.
    /// - `longest`: the longest run of consecutive calendar days anywhere in
    ///   the history.
    ///
    /// Dates are collapsed to local day-starts, so multiple sessions on one
    /// day count once. Empty input returns (0, 0).
    static func streak(
        from sessionDates: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> (current: Int, longest: Int) {
        guard !sessionDates.isEmpty else { return (0, 0) }

        // Collapse to the set of distinct local day-starts.
        var days = Set<Date>()
        days.reserveCapacity(sessionDates.count)
        for date in sessionDates {
            days.insert(calendar.startOfDay(for: date))
        }

        let todayStart = calendar.startOfDay(for: today)

        // Current streak: pick an anchor, then walk backward one day at a time.
        var current = 0
        var anchor: Date?
        if days.contains(todayStart) {
            anchor = todayStart
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart),
                  days.contains(yesterday) {
            anchor = yesterday
        }
        if var day = anchor {
            while days.contains(day) {
                current += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = prev
            }
        }

        // Longest streak: sort the unique days, count the longest consecutive run.
        let sorted = days.sorted()
        var longest = 1
        var run = 1
        for i in 1..<sorted.count {
            if let next = calendar.date(byAdding: .day, value: 1, to: sorted[i - 1]),
               next == sorted[i] {
                run += 1
            } else {
                run = 1
            }
            if run > longest { longest = run }
        }

        return (current, longest)
    }
}
