import Foundation

/// Derives meditation streaks from raw Session start dates.
///
/// Streak is **not** stored — it is computed at read time from the user's
/// Session `startedAt` values. This keeps a single source of truth (Sessions)
/// and removes the write-time streak bookkeeping the pipeline used to carry.
///
/// **Rest days (Melvin, 2026-09-15: "streak forgiveness").** One missed day
/// is forgiven when the days either side of it were practised and no other
/// rest day was taken in the previous seven. Two missed days in a row break
/// the streak. A rest day bridges the run; it does not count as a practised
/// day, so the number on Home is still days you actually sat. The same runs
/// feed the awards (`AwardEngine.streakRuns`), so "ten straight days" and
/// the headline can never disagree.
///
/// Pure Foundation only — no SwiftData, HealthKit, or UI. Deterministic:
/// pass an explicit `today`/`calendar` in tests.
enum StreakCalculator {

    /// Days a rest day must be apart from the previous one to be forgiven.
    static let restDaySpacing = 7

    /// One run of practice: the practised days, ascending, and the missed
    /// days inside it that were forgiven.
    struct Run: Equatable {
        let days: [Date]
        let restDays: [Date]
        var length: Int { days.count }
        var lastDay: Date { days[days.count - 1] }
    }

    /// Whether a missed `day` could be forgiven given the rest days already
    /// taken in the run: none yet, or the last one at least `restDaySpacing`
    /// days earlier.
    static func restAvailable(on day: Date, after restDays: [Date], calendar: Calendar) -> Bool {
        guard let last = restDays.last else { return true }
        let gap = calendar.dateComponents([.day], from: last, to: day).day ?? 0
        return gap >= restDaySpacing
    }

    /// The practice runs in the history, oldest first. Two sessions on one
    /// day are one day.
    static func runs(from sessionDates: [Date], calendar: Calendar = .current) -> [Run] {
        let days = Set(sessionDates.map { calendar.startOfDay(for: $0) }).sorted()
        guard let first = days.first else { return [] }

        var runs: [Run] = []
        var current: [Date] = [first]
        var rests: [Date] = []
        for day in days.dropFirst() {
            let previous = current[current.count - 1]
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if gap == 1 {
                current.append(day)
            } else if gap == 2,
                      let missed = calendar.date(byAdding: .day, value: 1, to: previous),
                      restAvailable(on: missed, after: rests, calendar: calendar) {
                rests.append(missed)
                current.append(day)
            } else {
                runs.append(Run(days: current, restDays: rests))
                current = [day]
                rests = []
            }
        }
        runs.append(Run(days: current, restDays: rests))
        return runs
    }

    /// Returns the current and longest streaks.
    ///
    /// - `current`: practised days in the run that is still alive. Alive
    ///   means practised today, or yesterday, or, with a rest day available,
    ///   the day before yesterday (yesterday becomes the rest day and today
    ///   must be practised to keep the run). Otherwise 0.
    /// - `longest`: the longest run anywhere in the history.
    /// - `restDayUsed`: yesterday was missed and is being carried as a rest
    ///   day right now, so the streak is on the line today.
    ///
    /// Empty input returns (0, 0, false).
    static func streak(
        from sessionDates: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> (current: Int, longest: Int, restDayUsed: Bool) {
        let all = runs(from: sessionDates, calendar: calendar)
        guard let last = all.last else { return (0, 0, false) }
        let longest = all.map(\.length).max() ?? 0

        let todayStart = calendar.startOfDay(for: today)
        let gap = calendar.dateComponents([.day], from: last.lastDay, to: todayStart).day ?? 0
        switch gap {
        case ...1:
            return (last.length, longest, false)
        case 2:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart),
                  restAvailable(on: yesterday, after: last.restDays, calendar: calendar)
            else { return (0, longest, false) }
            return (last.length, longest, true)
        default:
            return (0, longest, false)
        }
    }
}
