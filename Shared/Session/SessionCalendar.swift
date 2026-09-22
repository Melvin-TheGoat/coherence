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

    // MARK: - Weeks
    //
    // **The week is the unit the session log is read in** (Aziz, 2026-09-21:
    // "you see it based off a weekly basis"). It is also the unit the rest of
    // the product already thinks in: the streak forgives one rest day per
    // seven, Home's strip is seven days, and a week of sessions fits on one
    // screen without scrolling, which a month never does.
    //
    // **The week starts on the calendar's OWN `firstWeekday`, not on Monday.**
    // The picker's grid rows are weeks by construction (see `monthGrid`), so
    // hardcoding Monday here would have made a row of that grid and a week of
    // this log two different seven-day spans on every US phone.

    /// The day-start the week containing `date` begins on.
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)          // 1...7
        let back = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    /// The seven day-starts of the week containing `date`.
    static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = weekStart(for: date, calendar: calendar)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// `weeks` weeks forward (or back, when negative) from the week of `date`.
    static func week(_ weeks: Int, from date: Date, calendar: Calendar = .current) -> Date {
        let start = weekStart(for: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: weeks * 7, to: start) ?? start
    }

    /// True when `date` falls inside the week beginning `start`.
    ///
    /// Half-open on purpose: the last instant of a Saturday and the first of
    /// the next Sunday must land in different weeks, and `<=` on an end date
    /// built from midnight would put both in the earlier one.
    static func isIn(week start: Date, _ date: Date, calendar: Calendar = .current) -> Bool {
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return false }
        return date >= start && date < end
    }

    /// What the header calls a week: "This week", "Last week", else its span.
    ///
    /// The span names the month once when a week sits inside one ("Sep 14 - 20")
    /// and twice when it straddles two ("Aug 31 - Sep 6"), and it adds the year
    /// only when the week is not in this one.
    static func weekTitle(_ start: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let thisWeek = weekStart(for: now, calendar: calendar)
        if start == thisWeek { return "This week" }
        if start == week(-1, from: now, calendar: calendar) { return "Last week" }

        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let sameYear = calendar.isDate(start, equalTo: now, toGranularity: .year)
        let f = DateFormatter()
        // **The formatter takes the CALENDAR's zone, not the device's.** A
        // week start is a midnight in the calendar it was computed in, and a
        // formatter left on the device zone renders that midnight as the
        // evening before: "Sep 6 to 12" printed as "Sep 5 to 11" four hours
        // west of UTC. Caught by a test rather than by a user, which is the
        // only reason it is a footnote.
        //
        // The ZONE only. Handing the formatter the calendar as well renders
        // the months as "M09" whenever that calendar carries no locale, the
        // way a hand-built one in a test does.
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMM d"
        let left = f.string(from: start)
        f.dateFormat = calendar.isDate(start, equalTo: end, toGranularity: .month)
            ? (sameYear ? "d" : "d, yyyy")
            : (sameYear ? "MMM d" : "MMM d, yyyy")
        return "\(left) to \(f.string(from: end))"
    }

    /// True when `day` sits in the same calendar month as `reference` (used to dim
    /// the adjacent-month padding cells).
    static func isSameMonth(_ day: Date, as reference: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, equalTo: reference, toGranularity: .month)
    }
}
