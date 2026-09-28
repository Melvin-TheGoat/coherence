import Foundation

/// How bright Otto is today: 0 to 100, derived from session dates and
/// durations, and the windows Otto was told "Not now" in.
///
/// **The rule (Melvin, 2026-09-21, from `mockups/otto-aura.html`):** everyone
/// starts at 40, so a new person is never greeted by a sad sloth. Today only
/// counts once it is practised: an unfinished day is not a missed one.
///
/// **A day's gain is proportional to how long it was practised (Melvin,
/// 2026-09-28): "His glow should increase proportional to the length of the
/// meditation, max 20% glow for one hour or more. If you do 20 minutes then
/// its 10%. So like 2 minutes or less is 1%, 4 minutes or less is 2%. 10
/// minutes is 5%. 20 minutes is 10%. 40 minutes is like 15%, 60+ minutes is
/// 20%."** See `gain(minutes:)`. A day's sessions are summed into one minute
/// total BEFORE the curve is applied, never one gain per session: two
/// ten-minute sits and one twenty-minute sit earn the same +10, because the
/// curve flattens past 20 minutes and scoring each session on its own would
/// let splitting a sit into pieces out-earn sitting through it once.
///
/// **Missed days cost more the longer the run (Melvin and Aziz, 2026-09-23:
/// "first day missed -10, second day in a row missed -15, then -20 for third
/// etc.").** The first day missed in a row costs 10 and each further day in
/// the same run 5 more (`missCost(run:)`). A missed day costs nothing when
/// the streak forgives it as a rest day, which is the streak's own rule read
/// from `StreakCalculator.runs` (`forgivenDays`), so the two can never
/// disagree: a lone missed day between practised days, once a week. The
/// first day of a longer gap is not a rest day and costs 10. A day
/// meditated ends the run.
///
/// So a ten-minute first session lifts him from Stirring to Steady (his
/// colour comes back, +5 to 45), and five twenty-minute days in a row from
/// the start reach 90, Nirvana (+10 a day, the same climb a flat daily gain
/// used to make). A week away from Nirvana still brings him to Withered, the
/// missed-day costs being unchanged.
///
/// **"Not now" (Melvin, 2026-09-22).** Telling Otto "Not now" costs nothing if
/// a session follows inside the same window. If the window closes with no
/// session in it, it costs glow in proportion to how long the apps were held:
/// `20 × hours / 24`, so a skipped Mindful day costs 20 and a skipped hour
/// costs under one. Two rules keep that from compounding: **a missed day and
/// its windows are never added together** (the day costs whichever is
/// larger, and a day's windows are capped at 20), and **a rest day forgives
/// the missed day, never the "Not now"**.
///
/// **Consistency only, never the score.** A short, rough session still counts
/// as showing up, and the score keeps its own ring. Derived at read time like
/// the streak: nothing is stored here, so there is nothing to sync or go stale.
///
/// Pure Foundation. Pass `today` and `calendar` in tests.
enum OttoAura {

    static let startLevel = 40
    /// The first day missed in a row, and what each further day in the same
    /// run adds: 10, 15, 20, 25 ...
    static let firstMissCost = 10
    static let missStep = 5
    /// A whole day of apps held and skipped after "Not now", and the most a
    /// day's windows can cost together.
    static let heldDayCost = 20

    /// What the `run`th missed day in a row costs, counting from 1.
    static func missCost(run: Int) -> Int {
        firstMissCost + missStep * max(0, run - 1)
    }

    /// One meditation, on one day, for `level`/`stage`/`dateStageFirstReached`
    /// to sum. Hand-logged sessions (`Session.source == "logged"`) count here
    /// too, by their typed duration, exactly as they always have.
    struct Sit {
        let date: Date
        let seconds: Int

        init(date: Date, seconds: Int) {
            self.date = date
            self.seconds = seconds
        }
    }

    /// A day's glow gain, from that day's TOTAL minutes practised (Melvin,
    /// 2026-09-28): "His glow should increase proportional to the length of
    /// the meditation, max 20% glow for one hour or more. If you do 20
    /// minutes then its 10%. So like 2 minutes or less is 1%, 4 minutes or
    /// less is 2%. 10 minutes is 5%. 20 minutes is 10%. 40 minutes is like
    /// 15%, 60+ minutes is 20%."
    ///
    /// Up to 20 minutes the gain is half the minutes, rounded up (so a
    /// session of any length still earns something); from 20 to 60 it climbs
    /// the rest of the way to 20 at a quarter the rate; at 60 and beyond it
    /// is capped at 20. **Called once per DAY on that day's summed minutes,
    /// never once per session**: the curve flattens above 20 minutes on
    /// purpose, so scoring each session separately would let two ten-minute
    /// sits (summing to the same 20 minutes as one) earn more than sitting
    /// through the whole twenty at once, which rewards splitting a practice
    /// into pieces rather than holding it.
    static func gain(minutes: Double) -> Int {
        guard minutes > 0 else { return 0 }
        if minutes <= 20 { return Int((minutes / 2).rounded(.up)) }
        if minutes < 60 { return 10 + Int(((minutes - 20) / 4).rounded(.up)) }
        return 20
    }

    /// The seven drawings, worst to best (Melvin, 2026-09-22, drawn as one
    /// sheet: `mockups/otto-v4/sheet.png`). **His state is physical, never a
    /// mood**: near dead, gray and carrying bugs at the bottom, levitating in
    /// light at the top, and calm in every one of them. Raw values are the
    /// drawing's number, 1 to 7, NOT a level.
    enum Stage: Int, CaseIterable, Comparable {
        case withered = 1, faded, stirring, steady, bright, radiant, nirvana

        /// Seven bands of fifteen, the top one a point wider. Everyone starts
        /// at 40, in Stirring, so the first session is the one that brings
        /// his colour back.
        init(level: Int) {
            switch level {
            case ..<15: self = .withered
            case ..<30: self = .faded
            case ..<45: self = .stirring
            case ..<60: self = .steady
            case ..<75: self = .bright
            case ..<90: self = .radiant
            default:    self = .nirvana
            }
        }

        /// He has left the ground from here up.
        var floats: Bool { self >= .radiant }

        /// This stage's own drawing among the thirteen (`look(level:)`).
        var look: Int { rawValue * 2 - 1 }

        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    /// Which of Otto's THIRTEEN drawings shows at a level (Melvin,
    /// 2026-09-23: "i want it to be super granular"): the seven stages (odd
    /// numbers, `Stage.look`) and one drawing halfway between each pair
    /// (even numbers). The stages above still decide his mood, his stills and
    /// every promise; this only decides the picture, and it never disagrees
    /// with them by more than half a step.
    ///
    /// **Laid out for the levels people actually land on.** A missed day
    /// takes 10, 15, 20 ..., and a day's gain (2026-09-28, `gain(minutes:)`)
    /// is usually a multiple of five too (5 at ten minutes, 10 at twenty), so
    /// the level still lands on or near a multiple of five most of the time,
    /// and each multiple of ten gets its own drawing: start (40) is Stirring
    /// and a twenty-minute-or-longer first session (50) is Steady, exactly as
    /// the stages promise, and 90 shows the drawing just short of Nirvana
    /// (the faint wheel) with the full one at 100. The two in-betweens that
    /// fall between tens (6 at 45-49, 10 at 75-79) show after an
    /// odd-numbered missed day (15, 25 ...), a skipped "Not now" window, or a
    /// shorter session's smaller gain.
    static func look(level: Int) -> Int {
        switch level {
        case ..<5: return 1       // Withered
        case ..<15: return 2
        case ..<25: return 3      // Faded
        case ..<35: return 4
        case ..<45: return 5      // Stirring
        case ..<50: return 6
        case ..<55: return 7      // Steady
        case ..<65: return 8
        case ..<75: return 9      // Bright
        case ..<80: return 10
        case ..<85: return 11     // Radiant
        case ..<95: return 12
        default: return 13        // Nirvana
        }
    }

    /// What one window skipped after a "Not now" costs: 20 for a whole day,
    /// in proportion below that.
    static func skipCost(for window: DateInterval) -> Double {
        Double(heldDayCost) * min(window.duration / 3600, 24) / 24
    }

    /// Each sit's seconds, summed per calendar day, in minutes.
    private static func minutesByDay(_ sits: [Sit], calendar: Calendar) -> [Date: Double] {
        var minutes: [Date: Double] = [:]
        for sit in sits {
            minutes[calendar.startOfDay(for: sit.date), default: 0] += Double(sit.seconds) / 60
        }
        return minutes
    }

    /// The missed days the streak forgives as rest days, and only those, so
    /// Otto's glow and the streak can never disagree about a day (the bug
    /// of 2026-09-28: the glow kept one rest-day list for the whole history
    /// and spent it on the first day of ANY gap, while the streak forgives
    /// only a lone missed day between practised days, and starts its weekly
    /// allowance over when a run breaks). The rest days come from
    /// `StreakCalculator.runs`; yesterday is added while the streak is
    /// carrying it as today's rest day (`restDayUsed`), exactly as Home says.
    static func forgivenDays(practised: Set<Date>, today: Date, calendar: Calendar) -> Set<Date> {
        let dates = Array(practised)
        var forgiven = Set(StreakCalculator.runs(from: dates, calendar: calendar).flatMap(\.restDays))
        if StreakCalculator.streak(from: dates, today: today, calendar: calendar).restDayUsed,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today)) {
            forgiven.insert(yesterday)
        }
        return forgiven
    }

    /// - Parameter notNow: every window Otto was told "Not now" in, as the
    ///   whole window the apps were held for that day (Mindful day is
    ///   midnight to midnight). A window costs only once it has closed with no
    ///   session started inside it, and it belongs to the day it opened.
    static func level(from sits: [Sit],
                      notNow: [DateInterval] = [],
                      today: Date = Date(),
                      calendar: Calendar = .current) -> Int {
        let minutes = minutesByDay(sits, calendar: calendar)
        let practised = Set(minutes.keys)

        var skipped: [Date: Double] = [:]
        for window in notNow where window.end <= today {
            let meditatedInside = sits.contains { $0.date >= window.start && $0.date < window.end }
            guard !meditatedInside else { continue }
            skipped[calendar.startOfDay(for: window.start), default: 0] += skipCost(for: window)
        }

        // The history starts at the first session, or at the first skipped
        // window if that came earlier: someone who set Otto to hold their
        // apps has started, whether or not they have meditated yet.
        guard let first = practised.union(skipped.keys).min() else { return startLevel }
        let todayStart = calendar.startOfDay(for: today)

        let forgiven = forgivenDays(practised: practised, today: today, calendar: calendar)
        var level = Double(startLevel)
        var run = 0          // days missed in a row, the rest day included
        var day = first
        while day <= todayStart {
            let windows = min(Double(heldDayCost), skipped[day] ?? 0)
            if let dayMinutes = minutes[day] {
                run = 0
                level = min(100, level + Double(gain(minutes: dayMinutes))) - windows
            } else if day < todayStart {
                run += 1
                if forgiven.contains(day) {
                    level -= windows
                } else {
                    level -= max(Double(missCost(run: run)), windows)
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

    static func stage(from sits: [Sit],
                      notNow: [DateInterval] = [],
                      today: Date = Date(),
                      calendar: Calendar = .current) -> Stage {
        Stage(level: level(from: sits, notNow: notNow, today: today, calendar: calendar))
    }

    /// The day practice first raised Otto to at least `stage`, replayed from
    /// sessions alone (no "Not now" windows: that is Block's own data and
    /// never informs anything outside it). Used by the aura awards
    /// (2026-09-28), so a later dip can never take back a peak that really
    /// happened, the same "did this ever happen" rule as every other award.
    ///
    /// This only ever needs to walk FORWARD from the first session to the
    /// last, because level only rises on a practised day (capped at 100) and
    /// only falls on a missed one, so the running level can never exceed a
    /// value it already held right after some earlier gain. Checking right
    /// after every gain is therefore enough to find the first time a stage
    /// was reached, with no need to project forward to "today" at all.
    static func dateStageFirstReached(_ stage: Stage, from sits: [Sit],
                                      calendar: Calendar = .current) -> Date? {
        let minutes = minutesByDay(sits, calendar: calendar)
        guard let first = minutes.keys.min(), let last = minutes.keys.max() else { return nil }

        // Every missed day in this walk lies between two practised days, so
        // the streak's runs alone say which were rest days.
        let forgiven = Set(StreakCalculator.runs(from: Array(minutes.keys), calendar: calendar)
            .flatMap(\.restDays))
        var level = Double(startLevel)
        var run = 0
        var day = first
        while day <= last {
            if let dayMinutes = minutes[day] {
                run = 0
                level = min(100, level + Double(gain(minutes: dayMinutes)))
                if Stage(level: Int(level.rounded())) >= stage { return day }
            } else {
                run += 1
                if !forgiven.contains(day) {
                    level = max(0, level - Double(missCost(run: run)))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return nil
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
