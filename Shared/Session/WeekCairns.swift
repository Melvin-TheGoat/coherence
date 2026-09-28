import Foundation

/// The pure arithmetic behind Home's "This week" strip (`mockups/session-view.html`,
/// section 2). It was drawn as cairns (option A) for a day and is now a
/// garden (option C, Melvin, 2026-09-28); the name stayed.
///
/// One leaf per session that day, a flower from the third; an empty day is
/// bare soil; a day the streak forgave (one missed day per seven,
/// `StreakCalculator`) draws a fallen leaf instead of nothing, so the strip
/// and the streak headline can never disagree about which days were
/// forgiven and which were simply missed.
///
/// Pure Foundation, no SwiftUI: the view draws the stones, this decides which
/// days get them.
public enum WeekCairns {

    /// The one fact this needs about a session — callers flatten `Session`
    /// into this so the type never learns about storage.
    public struct SessionFact {
        public let startedAt: Date
        public let durationSec: Int

        public init(startedAt: Date, durationSec: Int) {
            self.startedAt = startedAt
            self.durationSec = durationSec
        }
    }

    /// One day of the strip.
    public struct Day: Equatable {
        public let date: Date
        /// Each session sat that day, in minutes, oldest first — one stone
        /// per entry, stacked bottom up.
        public let sessionMinutes: [Int]
        /// A day the streak forgave: missed, but bridging a run because no
        /// other rest day was taken in the previous seven
        /// (`StreakCalculator.runs`). Never a practised day itself.
        public let isRestDay: Bool
        public let isToday: Bool

        public var sessionCount: Int { sessionMinutes.count }

        public init(date: Date, sessionMinutes: [Int], isRestDay: Bool, isToday: Bool) {
            self.date = date
            self.sessionMinutes = sessionMinutes
            self.isRestDay = isRestDay
            self.isToday = isToday
        }
    }

    /// The rolling seven days ending `today` — never the calendar week, for
    /// the reason `WeekStrip` already gives: a Sunday-to-Saturday week draws
    /// days that have not happened yet as failures.
    ///
    /// **Reads the same rule the streak headline does.** A day is a forgiven
    /// rest day here exactly when `StreakCalculator.runs` forgave it, so the
    /// cairn's leaf and "your streak is on the line" can never point at
    /// different days.
    public static func week(from sessions: [SessionFact], today: Date = Date(),
                            calendar: Calendar = .current) -> [Day] {
        let todayStart = calendar.startOfDay(for: today)
        let restDays = Set(StreakCalculator.runs(from: sessions.map(\.startedAt), calendar: calendar)
            .flatMap(\.restDays))

        var minutesByDay: [Date: [Int]] = [:]
        for s in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let day = calendar.startOfDay(for: s.startedAt)
            minutesByDay[day, default: []].append(max(1, s.durationSec / 60))
        }

        return (0..<7).compactMap { offset -> Day? in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: todayStart) else { return nil }
            return Day(date: day, sessionMinutes: minutesByDay[day] ?? [],
                      isRestDay: restDays.contains(day), isToday: day == todayStart)
        }
    }

    /// "9 sessions · 101 min" — the header's own totals for the drawn week.
    public static func summary(_ days: [Day]) -> (sessions: Int, minutes: Int) {
        let all = days.flatMap(\.sessionMinutes)
        return (all.count, all.reduce(0, +))
    }
}
