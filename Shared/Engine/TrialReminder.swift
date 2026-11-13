import Foundation

/// When Otto's "your free trial ends tomorrow" notification fires, and what it
/// and the paywall's timeline say. Pure, so the one promise onboarding makes
/// about money ("I'll remind you the day before it ends", Aziz, 2026-11-11)
/// is tested rather than trusted.
///
/// **The reminder has to leave time to act.** Apple stops a renewal only if it
/// is cancelled at least 24 hours before the period ends, so a reminder sent
/// 20 hours before the end arrives too late to be any use, however true it
/// is. It fires on the day before the trial's last day, at 10 in the morning,
/// and moves a day earlier whenever that is under 26 hours before the end (a
/// trial ending at 2 in the morning). Never at night.
enum TrialReminder {
    /// The hour it fires, local time.
    static let hour = 10
    /// The least time between the reminder and the end of the trial: Apple's
    /// 24 hours, plus two to actually do it.
    static let minimumLead: TimeInterval = 26 * 3600

    /// When a free trial of `days` days started at `start` ends: the same
    /// time of day, `days` calendar days later, which is how the App Store
    /// counts it.
    static func end(start: Date, days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: start)
            ?? start.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    /// When the reminder fires for a trial ending at `trialEnd`, or nil when
    /// that moment has already passed (it is never sent late).
    static func fireDate(trialEnd: Date, now: Date, calendar: Calendar = .current) -> Date? {
        let endDay = calendar.startOfDay(for: trialEnd)
        for back in 1...3 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: endDay),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return nil }
            if trialEnd.timeIntervalSince(fire) >= minimumLead {
                return fire > now.addingTimeInterval(60) ? fire : nil
            }
        }
        return nil
    }

    /// "tomorrow", or "on Wednesday" when the reminder had to come a day
    /// earlier. Always true of the day the trial actually ends.
    static func endsWhen(fire: Date, end: Date, calendar: Calendar = .current) -> String {
        let from = calendar.startOfDay(for: fire)
        let to = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 1
        if days == 1 { return "tomorrow" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale ?? Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return "on " + f.string(from: end)
    }

    /// The notification's words, from Otto.
    static func body(fire: Date, end: Date, calendar: Calendar = .current) -> String {
        "Your free trial ends \(endsWhen(fire: fire, end: end, calendar: calendar)). Want to keep meditating together?"
    }

    /// The three dates a trial starting now is about: today, the reminder,
    /// the end. The reminder falls back to the day before the end if it could
    /// not be scheduled (a trial so short it has no room for one), so the
    /// timeline always has three rows.
    struct Timeline: Equatable {
        let start: Date
        let reminder: Date
        let end: Date
    }

    static func timeline(start: Date, days: Int, calendar: Calendar = .current) -> Timeline {
        let end = end(start: start, days: days, calendar: calendar)
        let reminder = fireDate(trialEnd: end, now: start, calendar: calendar)
            ?? calendar.date(byAdding: .day, value: -1, to: end) ?? end
        return Timeline(start: start, reminder: reminder, end: end)
    }
}
