import Foundation

/// How bright Otto is today: 0 to 100, derived from session dates alone.
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
/// **Consistency only, never the score.** A short, rough session still counts
/// as showing up, and the score keeps its own ring. Derived at read time like
/// the streak: nothing is stored, so there is nothing to sync or go stale.
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

    static func level(from sessionDates: [Date],
                      today: Date = Date(),
                      calendar: Calendar = .current) -> Int {
        let practised = Set(sessionDates.map { calendar.startOfDay(for: $0) })
        guard let first = practised.min() else { return startLevel }
        let todayStart = calendar.startOfDay(for: today)

        var level = startLevel
        var rests: [Date] = []
        var day = first
        while day <= todayStart {
            if practised.contains(day) {
                level = min(100, level + dayGain)
            } else if day < todayStart {
                if StreakCalculator.restAvailable(on: day, after: rests, calendar: calendar) {
                    rests.append(day)
                } else {
                    level = max(0, level - missCost)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return level
    }

    static func stage(from sessionDates: [Date],
                      today: Date = Date(),
                      calendar: Calendar = .current) -> Stage {
        Stage(level: level(from: sessionDates, today: today, calendar: calendar))
    }
}
