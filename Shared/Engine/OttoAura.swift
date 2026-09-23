import Foundation

/// How bright Otto is today: 0 to 100, derived from session dates and the
/// windows Otto was told "Not now" in.
///
/// **The rule (Melvin, 2026-09-21, from `mockups/otto-aura.html`):** everyone
/// starts at 40, so a new person is never greeted by a sad sloth. Each day
/// meditated adds 10. Each day missed takes 20, except that one missed day a
/// week is a rest day and costs nothing, the streak's own rule
/// (`StreakCalculator.restAvailable`), so the two can never disagree. Today
/// only counts once it is practised: an unfinished day is not a missed one.
///
/// So the first session lifts him from Curious to Progressing, five days in a
/// row reaches Enlightened, and a week away from Enlightened brings him to Low.
///
/// **"Not now" (Melvin, 2026-09-22).** Telling Otto "Not now" costs nothing if
/// a session follows inside the same window. If the window closes with no
/// session in it, it costs glow in proportion to how long the apps were held:
/// `20 × hours / 24`, so a skipped Mindful day costs what a missed day does
/// and a skipped hour costs under one. Two rules keep that from compounding:
/// **no day ever costs more than a missed day** (the day's windows are capped
/// at 20, and a missed day already costs 20), and **a rest day forgives the
/// missed day, never the "Not now"**.
///
/// **Consistency only, never the score.** A short, rough session still counts
/// as showing up, and the score keeps its own ring. Derived at read time like
/// the streak: nothing is stored here, so there is nothing to sync or go stale.
///
/// Pure Foundation. Pass `today` and `calendar` in tests.
enum OttoAura {

    static let startLevel = 40
    static let dayGain = 10
    static let missCost = 20

    /// The six drawings, by the level they stand for.
    enum Stage: Int, CaseIterable, Comparable {
        case low = 0, frustrated = 20, curious = 40, progressing = 60, inFlow = 80, enlightened = 100

        init(level: Int) {
            switch level {
            case ..<10: self = .low
            case ..<30: self = .frustrated
            case ..<50: self = .curious
            case ..<70: self = .progressing
            case ..<90: self = .inFlow
            default:    self = .enlightened
            }
        }

        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    /// What one window skipped after a "Not now" costs: 20 for a whole day,
    /// in proportion below that.
    static func skipCost(for window: DateInterval) -> Double {
        Double(missCost) * min(window.duration / 3600, 24) / 24
    }

    /// - Parameter notNow: every window Otto was told "Not now" in, as the
    ///   whole window the apps were held for that day (Mindful day is
    ///   midnight to midnight). A window costs only once it has closed with no
    ///   session started inside it, and it belongs to the day it opened.
    static func level(from sessionDates: [Date],
                      notNow: [DateInterval] = [],
                      today: Date = Date(),
                      calendar: Calendar = .current) -> Int {
        let practised = Set(sessionDates.map { calendar.startOfDay(for: $0) })

        var skipped: [Date: Double] = [:]
        for window in notNow where window.end <= today {
            let meditatedInside = sessionDates.contains { $0 >= window.start && $0 < window.end }
            guard !meditatedInside else { continue }
            skipped[calendar.startOfDay(for: window.start), default: 0] += skipCost(for: window)
        }

        // The history starts at the first session, or at the first skipped
        // window if that came earlier: someone who set Otto to hold their
        // apps has started, whether or not they have meditated yet.
        guard let first = practised.union(skipped.keys).min() else { return startLevel }
        let todayStart = calendar.startOfDay(for: today)

        var level = Double(startLevel)
        var rests: [Date] = []
        var day = first
        while day <= todayStart {
            let windows = min(Double(missCost), skipped[day] ?? 0)
            if practised.contains(day) {
                level = min(100, level + Double(dayGain)) - windows
            } else if day < todayStart {
                if StreakCalculator.restAvailable(on: day, after: rests, calendar: calendar) {
                    rests.append(day)
                    level -= windows
                } else {
                    level -= Double(missCost)
                }
            } else {
                // Today, not practised yet: only windows that already closed.
                level -= windows
            }
            level = max(0, level)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return Int(level.rounded())
    }

    static func stage(from sessionDates: [Date],
                      notNow: [DateInterval] = [],
                      today: Date = Date(),
                      calendar: Calendar = .current) -> Stage {
        Stage(level: level(from: sessionDates, notNow: notNow, today: today, calendar: calendar))
    }
}
