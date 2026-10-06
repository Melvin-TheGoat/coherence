import Foundation

/// Works out what the home screen widget shows (`OttoWidgetSnapshot`), from
/// the same rules Home uses: `OttoAura` for the glow, `StreakCalculator` for
/// the flame, `OttoLines` for what he says. Pure, so it is tested.
enum OttoWidgetFeed {
    /// Days worked out past today. A widget redraws itself all day without
    /// the app, so it needs to know what tomorrow looks like if nobody sits;
    /// three days covers a long weekend away from 808, and after that the
    /// last day stands.
    static let daysAhead = 3

    static func snapshot(sits: [OttoAura.Sit],
                         notNow: [DateInterval] = [],
                         since: Date?,
                         member: Bool,
                         now: Date = Date(),
                         calendar: Calendar = .current) -> OttoWidgetSnapshot {
        guard member else { return OttoWidgetSnapshot(member: false, days: [], written: now) }
        let dates = sits.map(\.date)
        let todayStart = calendar.startOfDay(for: now)
        var days: [OttoWidgetSnapshot.Day] = []
        for offset in 0...daysAhead {
            guard let start = calendar.date(byAdding: .day, value: offset, to: todayStart) else { break }
            // Today as it is now; each later day as it stands at its midnight.
            let when = offset == 0 ? now : start
            let level = OttoAura.level(from: sits, notNow: notNow, since: since, today: when, calendar: calendar)
            let streak = StreakCalculator.streak(from: dates, today: when, calendar: calendar)
            let practiced = dates.contains { calendar.isDate($0, inSameDayAs: when) }
            let line = OttoLines.widget(stage: OttoAura.Stage(level: level),
                                        hasSessions: !sits.isEmpty,
                                        practicedToday: practiced,
                                        streak: streak)
            days.append(.init(start: start, level: level, streak: streak.current, line: line))
        }
        return OttoWidgetSnapshot(member: true, days: days, written: now)
    }
}
