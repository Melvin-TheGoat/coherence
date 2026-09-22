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

// MARK: - What he says when you tap him

/// The lines a tap on Otto cycles through on Home, after whatever today gives
/// him to say first (Melvin, 2026-09-22: twenty-five more, famous meditators
/// among them, "from buddha to ray dalio to jim carrey to jerry seinfeld to
/// confucius"). Twelve are famous people, thirteen are his own, and they
/// alternate so a run of taps is never all quotes.
///
/// **Rules for adding one**, each pinned by `OttoAuraTests`:
/// - Nothing about a score, a doorway or a Watch. Every line is true for a
///   session on the phone with nothing measured.
/// - No one technique. There are endless ways to meditate, so where he gives
///   advice he offers a few ways in rather than prescribing one.
/// - A famous person's line is checked against its source first, and
///   paraphrased when the original runs long. Many famous ones are fake:
///   "It does not matter how slowly you go" is in no edition of the Analects,
///   and sloths hold their breath for about fifteen minutes, not the forty
///   everyone repeats.
/// - No em dashes, and two lines at most in his bubble: 74 characters
///   fits two on the narrowest iPhone, and a third line on Home runs into
///   the Guide circle beside the streak.
///
/// Sources, checked 2026-09-22: Dhammapada 122 (Müller); Analects IX, the
/// mound raised a basket at a time (Legge); Tao Te Ching 64 (Legge);
/// Meditations 4.3 (Long); Seinfeld on Good Morning America with Bob Roth
/// (TM since the early 1970s); Dalio to CNBC and elsewhere (TM since 1968);
/// Carrey to the Ottawa Citizen, December 2005, per Quote Investigator;
/// Lynch, Catching the Big Fish (2006); Jobs in Isaacson's Steve Jobs (2011);
/// Gates, GatesNotes (2018); Kabat-Zinn, Wherever You Go, There You Are
/// (1994); Thich Nhat Hanh, Peace Is Every Step (1991); algae in sloth fur
/// (Smithsonian Tropical Research Institute); wild sloths sleep eight to ten
/// hours (Sloth Conservation Foundation).
enum OttoSayings {
    static let all: [String] = [
        "Sloths move so slowly that algae grows in our fur. I call that commitment.",
        "The Buddha said a water pot fills drop by drop. Habits fill the same way.",
        "No wrong way in: silence, rain, music, a guided voice. It all counts.",
        "Jerry Seinfeld calls meditation a charger for your whole body and mind.",
        "Did your mind wander? Noticing and coming back is the whole practice.",
        "Confucius said learning is a hill you raise one basket of earth at a time.",
        "Sit on a cushion, a chair, or a bus. I recommend a branch, but I'm biased.",
        "Ray Dalio calls meditation the biggest ingredient in his success.",
        "You don't need to feel calm to start. Frazzled is a fine place to begin.",
        "Lao Tzu said a thousand-mile journey starts with one step. Mine are slow.",
        "I saved you a spot on the cushion. It's been warming up all day.",
        "Jim Carrey says being rich and famous isn't the answer. He'd know.",
        "Wild sloths sleep eight to ten hours, not twenty. Unhurried, not lazy.",
        "Steve Jobs said sitting shows how restless your mind is. In time it calms.",
        "Whatever today's been, set it down for a few minutes. I'll hold it.",
        "Marcus Aurelius ran Rome and called his own soul the quietest retreat.",
        "Tip: turn on Do Not Disturb before you start. I'll keep an eye out.",
        "Bill Gates calls meditation exercise for the mind. I'm your trainer now.",
        "Sleeping is lovely. Meditating is resting with the lights on.",
        "David Lynch said big ideas are like big fish. You go deeper to catch them.",
        "Lost? Rest on one thing, like a sound, and come back to it when you drift.",
        "Jon Kabat-Zinn says you can't stop the waves, but you can learn to surf.",
        "The best time to meditate is whenever you'll actually do it.",
        "Thich Nhat Hanh said to walk like you're kissing the Earth with your feet.",
        "I like you. That's it. That's the message."
    ]

    /// The same lines, starting somewhere different each day, so the second
    /// thing he says changes from one day to the next. Decided by the date
    /// alone, so a redraw never jumps him to another line.
    static func forDay(_ day: Date, calendar: Calendar = .current) -> [String] {
        let count = all.count
        let dayNumber = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
        let start = ((dayNumber % count) + count) % count
        return Array(all[start...] + all[..<start])
    }
}
