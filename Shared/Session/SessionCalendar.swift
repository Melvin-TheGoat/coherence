import Foundation

/// Pure calendar math for the history screen: which days the user practiced, and
/// the month grid to render them on. No SwiftData / SwiftUI, so the date logic is
/// unit-tested directly (pass an explicit `calendar` in tests for determinism).
///
/// Sessions are the single source of truth — like `StreakCalculator`, this derives
/// everything from raw `Session.startedAt` dates at read time; nothing is stored.
enum SessionCalendar {

    /// The distinct local day-starts on which at least one session began (multiple
    /// sessions on one day collapse to a single day, matching the streak rule).
    static func practicedDays(from sessionDates: [Date], calendar: Calendar = .current) -> Set<Date> {
        Set(sessionDates.map { calendar.startOfDay(for: $0) })
    }

    /// A 6-row × 7-column grid of day-starts for the month containing `date`, padded
    /// with the trailing days of the previous month and leading days of the next so
    /// every row is full and column 0 is the calendar's `firstWeekday`. Fixed at 6
    /// rows so the grid height doesn't jump between months.
    static func monthGrid(containing date: Date, calendar: Calendar = .current) -> [[Date]] {
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? calendar.startOfDay(for: date)
        // Back up to the first weekday of the week the 1st falls in.
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)   // 1...7
        let lead = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -lead, to: firstOfMonth) ?? firstOfMonth

        let days: [Date] = (0..<42).map {
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: $0, to: gridStart) ?? gridStart)
        }
        return stride(from: 0, to: 42, by: 7).map { Array(days[$0..<$0 + 7]) }
    }

    /// True when `day` sits in the same calendar month as `reference` (used to dim
    /// the adjacent-month padding cells).
    static func isSameMonth(_ day: Date, as reference: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, equalTo: reference, toGranularity: .month)
    }
}
