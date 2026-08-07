import Foundation

/// The onboarding interview: what we ask, what the user answered, and the
/// things we compute from it. Pure Foundation so the arithmetic behind the
/// projection and the practice profile is testable without a UI.
///
/// **The integrity rule for this whole file:** every claim onboarding makes
/// back to the user must be either (a) their own answer repeated, or (b)
/// arithmetic from their own answer. We never invent a goal date, a
/// percentage, or a diagnosis. See `ONBOARDING.md` — "what we deliberately do
/// NOT copy from QUITTR".

// MARK: - Questions

public enum Motivation: String, CaseIterable, Identifiable, Codable {
    case lessStressed, sharperFocus, moreDiscipline, betterSleep, lessAnxious, deeperPractice

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .lessStressed:   return "Less stressed"
        case .sharperFocus:   return "Sharper focus"
        case .moreDiscipline: return "More discipline"
        case .betterSleep:    return "Better sleep"
        case .lessAnxious:    return "Less anxious"
        case .deeperPractice: return "Deeper prayer or practice"
        }
    }

    public var icon: String {
        switch self {
        case .lessStressed:   return "wind"
        case .sharperFocus:   return "scope"
        case .moreDiscipline: return "flame"
        case .betterSleep:    return "moon.stars"
        case .lessAnxious:    return "heart"
        case .deeperPractice: return "hands.and.sparkles"
        }
    }
}

/// Where they are today. The baseline: a "before" so everything the app does
/// later has something to be measured against. Every honest answer here IS the
/// inconsistency the product exists to fix, so nothing has to be asserted at
/// them afterwards.
public enum CurrentFrequency: String, CaseIterable, Identifiable, Codable {
    case never, triedNeverStuck, fewTimesMonth, mostWeeks, almostDaily

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .never:           return "Never. This would be the start"
        case .triedNeverStuck: return "I've tried, it never stuck"
        case .fewTimesMonth:   return "A few times a month"
        case .mostWeeks:       return "Most weeks"
        case .almostDaily:     return "Almost every day"
        }
    }

    /// Every option list carries icons. Without them a five-row list is five
    /// floating sentences, and the screen reads as unfinished no matter how it
    /// is spaced. The symbol also gives the selected state somewhere to tint
    /// besides the tick.
    public var icon: String {
        switch self {
        case .never:           return "circle.dotted"
        case .triedNeverStuck: return "arrow.trianglehead.counterclockwise"
        case .fewTimesMonth:   return "calendar"
        case .mostWeeks:       return "calendar.badge.checkmark"
        case .almostDaily:     return "flame"
        }
    }
}

/// The escalation question. Its job is to turn a static problem into a
/// worsening one — that's where urgency comes from. **We ask; we never tell.**
/// Asserting that someone's attention has degraded would be a claim about their
/// brain we cannot measure, the same line the theta copy has to respect.
/// "Better" is a real option: without an out the question is leading, and
/// people can feel when they're being handled.
public enum AloneWithThoughts: String, CaseIterable, Identifiable, Codable {
    case notLikeIUsedTo, harder, same, better

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .notLikeIUsedTo: return "No, not like I used to"
        case .harder:         return "It's got harder"
        case .same:           return "About the same"
        case .better:         return "Actually better now"
        }
    }

    public var icon: String {
        switch self {
        case .notLikeIUsedTo: return "waveform.path.ecg"
        case .harder:         return "arrow.down.right"
        case .same:           return "equal"
        case .better:         return "arrow.up.right"
        }
    }

    /// True when they told us it's slipping — used to choose which pain the
    /// reflection screen speaks to.
    public var isSlipping: Bool { self == .notLikeIUsedTo || self == .harder }
}

/// The concrete cost, and the counterpart to `AloneWithThoughts`: that one asks
/// for the trend, this one asks for the evidence in their own behaviour.
///
/// Answered instantly — you already know your answer, which is the property
/// that makes their arousal question work. An earlier draft asked how many of
/// the last seven days they were "present" for; it was cut because nobody
/// tracks that, so it asks for data the user never collected.
///
/// The scale is deliberately a ladder from seconds to comfortable, so the
/// answer lands somewhere on a spectrum rather than in a yes/no.
public enum DoingNothing: String, CaseIterable, Identifiable, Codable {
    case seconds, aMinute, fewMinutes, anHour, comfortable

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .seconds:     return "A few seconds"
        case .aMinute:     return "About a minute"
        case .fewMinutes:  return "A few minutes"
        case .anHour:      return "An hour"
        case .comfortable: return "I'm fine doing nothing"
        }
    }

    public var icon: String {
        switch self {
        case .seconds:     return "bolt"
        case .aMinute:     return "timer"
        case .fewMinutes:  return "clock"
        case .anHour:      return "hourglass"
        case .comfortable: return "leaf"
        }
    }

    /// True when stillness is already hard for them — feeds which pain the
    /// reflection screen speaks to.
    public var isRestless: Bool { self == .seconds || self == .aMinute }
}

/// How many times they've started a practice and stopped. The admission.
public enum RestartCount: String, CaseIterable, Identifiable, Codable {
    case never, once, few, many, lostCount
    /// The identity out, same as IntendedFor.alreadyPractice one screen later:
    /// the question presumes the practice never stuck, and for some arrivals
    /// it did. Picking it reroutes the Result reflection and the profile's
    /// pattern card exactly like alreadyPractice does.
    case sticks

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .never:     return "This would be my first try"
        case .once:      return "Once"
        case .few:       return "Two or three times"
        case .many:      return "More than I'd like to admit"
        case .lostCount: return "I've lost count"
        case .sticks:    return "It sticks. I'm here for the stats"
        }
    }

    public var icon: String {
        switch self {
        case .never:     return "sparkles"
        case .once:      return "1.circle"
        case .few:       return "3.circle"
        case .many:      return "arrow.trianglehead.2.clockwise"
        case .lostCount: return "questionmark.circle"
        case .sticks:    return "chart.xyaxis.line"
        }
    }
}

/// How long they've been *meaning* to start. Their version asks what age you
/// first saw explicit content — the cleverest question in that flow, because it
/// makes the problem feel lifelong while quietly removing blame ("you were a
/// kid"). The literal translation is dead for meditation, but the job carries:
/// give the pattern a LENGTH to sit alongside the count from `RestartCount`.
///
/// The blame removal lives in the subtitle — "Not trying. Meaning to." Nobody
/// feels judged for having intended something.
public enum IntendedFor: String, CaseIterable, Identifiable, Codable {
    case weeks, months, aYear, years, forever
    /// The identity out. The question presumes the user hasn't started, but
    /// the baseline screen literally offers "Almost every day" — someone who
    /// picked it reaches this screen with no true answer. Their pain isn't
    /// quitting, it's practicing blind, so this selection reframes the Result
    /// reflection and the profile's pattern card (an answer that changes
    /// nothing is the documented "decorative questions" failure).
    case alreadyPractice

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .weeks:   return "A few weeks"
        case .months:  return "Months"
        case .aYear:   return "A year or so"
        case .years:   return "Years"
        case .forever: return "As long as I can remember"
        case .alreadyPractice: return "I already meditate. I'm here for the stats"
        }
    }

    public var icon: String {
        switch self {
        case .weeks:   return "calendar"
        case .months:  return "calendar.badge.clock"
        case .aYear:   return "clock.arrow.circlepath"
        case .years:   return "hourglass"
        case .forever: return "infinity"
        case .alreadyPractice: return "chart.xyaxis.line"
        }
    }

    /// Phrase for reflecting the answer back ("you've been meaning to for years").
    public var phrase: String {
        switch self {
        case .weeks:   return "a few weeks"
        case .months:  return "months"
        case .aYear:   return "about a year"
        case .years:   return "years"
        case .forever: return "as long as you can remember"
        case .alreadyPractice: return "already, in your own practice"
        }
    }
}

/// Why they stopped. Every option is one 808 has an answer for — that mapping
/// is the whole point of screen 16d, so it lives on the case itself.
public enum DropoutCause: String, CaseIterable, Identifiable, Codable {
    case couldntTell, tooManyChoices, forgot, feltWrong, noTime, gotBoring

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .couldntTell:    return "I couldn't tell it was working"
        case .tooManyChoices: return "Too many choices every time"
        case .forgot:         return "I forgot"
        case .feltWrong:      return "I felt like I was doing it wrong"
        case .noTime:         return "I ran out of time"
        case .gotBoring:      return "It got boring"
        }
    }

    public var icon: String {
        switch self {
        case .couldntTell:    return "eye.slash"
        case .tooManyChoices: return "square.grid.3x3"
        case .forgot:         return "bell.slash"
        case .feltWrong:      return "questionmark.circle"
        case .noTime:         return "clock.badge.exclamationmark"
        case .gotBoring:      return "zzz"
        }
    }

    /// The feature that answers this objection, in the user's own framing.
    ///
    /// **Each one must be unique and must stand alone.** Screen 16d lists the
    /// answers to causes the user did NOT pick, with no quote above them to
    /// explain what they're for, so a line that only makes sense underneath its
    /// objection will read as a non-sequitur there. Two causes sharing one
    /// answer would also print the same row twice. Locked by a test.
    public var answer: String {
        switch self {
        case .couldntTell:    return "A score after every session"
        case .tooManyChoices: return "One tap. No length to pick, nothing to choose"
        case .forgot:         return "A nudge at the time you chose"
        // Was pointed at "your own audio, still measured", which answers a
        // completely different objection. Feeling like you're doing it wrong
        // is answered by there being nothing to do wrong: the score comes
        // from heart rate settling and the body going still, so no posture
        // gets graded and there's no breath count to hit.
        case .feltWrong:      return "Nothing to get wrong. We read your body, not your technique"
        case .noTime:         return "Sessions end when you end them, so two minutes still counts"
        case .gotBoring:      return "Your own audio, still measured"
        }
    }
}

/// When they'll practise — anchored to something they already do daily,
/// because anchoring to an existing routine measurably lowered abandonment
/// (Mindfulness, 2023; see ONBOARDING.md).
public enum Anchor: String, CaseIterable, Identifiable, Codable {
    case wake, coffee, commute, lunch, afterWork, beforeBed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .wake:      return "Right after I wake up"
        case .coffee:    return "With my morning coffee"
        case .commute:   return "After my commute"
        case .lunch:     return "Around lunch"
        case .afterWork: return "When I get home from work"
        case .beforeBed: return "Before bed"
        }
    }

    public var icon: String {
        switch self {
        case .wake:      return "sunrise"
        case .coffee:    return "cup.and.saucer"
        case .commute:   return "car"
        case .lunch:     return "fork.knife"
        case .afterWork: return "house"
        case .beforeBed: return "moon.stars"
        }
    }

    /// The phrase used in the reminder and the permission pre-prompt, so the
    /// ask is in their own words: "…right after your morning coffee".
    public var phrase: String {
        switch self {
        case .wake:      return "right after you wake up"
        case .coffee:    return "with your morning coffee"
        case .commute:   return "after your commute"
        case .lunch:     return "around lunch"
        case .afterWork: return "when you get home"
        case .beforeBed: return "before bed"
        }
    }

    /// Default reminder hour (24h) — pre-fills the notification time so the
    /// user isn't asked a second time for something they just told us.
    public var defaultHour: Int {
        switch self {
        case .wake:      return 7
        case .coffee:    return 8
        case .commute:   return 9
        case .lunch:     return 12
        case .afterWork: return 18
        case .beforeBed: return 22
        }
    }
}

/// Attribution — the one question in the flow that isn't persuasion. It tells
/// us which channel actually produces installs, which is the difference between
/// spending on what works and what merely feels busy. Skippable by design:
/// every other screen gives the user something back, this one serves us.
public enum ReferralSource: String, CaseIterable, Identifiable, Codable {
    case instagram, tiktok, friend, appStore, other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .instagram: return "Instagram"
        case .tiktok:    return "TikTok"
        case .friend:    return "A friend told me"
        case .appStore:  return "Searching the App Store"
        case .other:     return "Somewhere else"
        }
    }

    public var icon: String {
        switch self {
        case .instagram: return "camera"
        case .tiktok:    return "music.note"
        case .friend:    return "person.2"
        case .appStore:  return "magnifyingglass"
        case .other:     return "ellipsis"
        }
    }
}

/// What the inconsistency is costing them, ticked across three lenses.
///
/// **Self-report only.** We never assign a condition. The reference flow pairs
/// its symptom list with an invented "64% suited to this product" score; we
/// dropped the score and kept the list, because those are separable. The score
/// was fiction. This is the user telling us about their own life, which is the
/// only kind of claim about someone's inner state we're entitled to repeat.
///
/// Written in the first person on purpose: "My thoughts won't switch off" is
/// harder to hold at arm's length than "trouble switching off".
public enum CostSymptom: String, CaseIterable, Identifiable, Codable {
    case thoughtsWontStop, cantFocus, wakeBehind          // Mind
    case dontFinish, knowButDont, gapFromIntent           // Discipline
    case daysPassBy, elsewhere, driftedFromPractice       // Spirit

    public var id: String { rawValue }

    public enum Lens: String, CaseIterable, Identifiable {
        case mind, discipline, spirit
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .mind:       return "Mind"
            case .discipline: return "Discipline"
            case .spirit:     return "Spirit"
            }
        }
    }

    public var lens: Lens {
        switch self {
        case .thoughtsWontStop, .cantFocus, .wakeBehind: return .mind
        case .dontFinish, .knowButDont, .gapFromIntent:  return .discipline
        case .daysPassBy, .elsewhere, .driftedFromPractice: return .spirit
        }
    }

    public var label: String {
        switch self {
        case .thoughtsWontStop:    return "My thoughts won't switch off"
        case .cantFocus:           return "I can't focus when it matters"
        case .wakeBehind:          return "I wake up already behind"
        case .dontFinish:          return "I start things and don't finish them"
        case .knowButDont:         return "I know what to do, I just don't do it"
        case .gapFromIntent:       return "The gap between who I am and who I meant to be"
        case .daysPassBy:          return "Days go by without me really in them"
        case .elsewhere:           return "I'm somewhere else even when I'm here"
        case .driftedFromPractice: return "I've drifted from a practice that mattered"
        }
    }

    /// Short form for echoing back on the commitment screen, where it has to
    /// finish the sentence "so that…".
    public var echo: String {
        switch self {
        case .thoughtsWontStop:    return "your thoughts might switch off"
        case .cantFocus:           return "you can focus when it matters"
        case .wakeBehind:          return "you stop waking up behind"
        case .dontFinish:          return "you finish what you start"
        case .knowButDont:         return "you do the thing you already know to do"
        case .gapFromIntent:       return "the gap closes"
        case .daysPassBy:          return "your days stop passing you by"
        case .elsewhere:           return "you're here when you're here"
        case .driftedFromPractice: return "you find your way back to the practice"
        }
    }

    public static func inLens(_ lens: Lens) -> [CostSymptom] {
        allCases.filter { $0.lens == lens }
    }
}

// MARK: - The answers

/// Everything the interview collects. Codable so an interrupted onboarding can
/// be resumed rather than restarted.
public struct OnboardingAnswers: Codable, Equatable {
    public var currentFrequency: CurrentFrequency?
    public var motivations: Set<Motivation> = []
    /// 0 = "Fine", 1 = "Fried".
    public var stress: Double = 0.5
    public var aloneWithThoughts: AloneWithThoughts?
    public var doingNothing: DoingNothing?
    public var restarts: RestartCount?
    public var intendedFor: IntendedFor?
    public var causes: Set<DropoutCause> = []
    public var costs: Set<CostSymptom> = []
    public var hasWatch: Bool?
    public var anchor: Anchor?
    public var firstName: String = ""
    public var ageBracket: String?
    public var referral: ReferralSource?
    /// Days per week they commit to.
    public var daysPerWeek: Int = 5

    public init() {}

    /// The single cause we speak to when we can only name one. Ordered by how
    /// directly 808 answers it, not by the enum's declaration order.
    public var primaryCause: DropoutCause? {
        let priority: [DropoutCause] = [.couldntTell, .tooManyChoices, .forgot,
                                        .feltWrong, .gotBoring, .noTime]
        return priority.first { causes.contains($0) } ?? causes.first
    }

    public var primaryMotivation: Motivation? {
        let priority: [Motivation] = [.moreDiscipline, .lessAnxious, .lessStressed,
                                      .sharperFocus, .betterSleep, .deeperPractice]
        return priority.first { motivations.contains($0) } ?? motivations.first
    }

    /// "Fried" end of the slider. Used to choose which pain we reflect back.
    public var isHighStress: Bool { stress >= 0.6 }

    /// The cost we echo back on the commitment screen. Ordered by how directly
    /// a measured, consistent practice speaks to it, so the promise they make
    /// answers the cost they named rather than a random one they ticked.
    public var primaryCost: CostSymptom? {
        let priority: [CostSymptom] = [.dontFinish, .knowButDont, .gapFromIntent,
                                       .thoughtsWontStop, .daysPassBy, .elsewhere,
                                       .cantFocus, .wakeBehind, .driftedFromPractice]
        return priority.first { costs.contains($0) }
    }
}

// MARK: - What we compute

public enum OnboardingProjection {

    /// The date their 30th practised day lands, given the days-per-week they
    /// just committed to. **Real arithmetic from their own answer** — the one
    /// number in onboarding that isn't simply repeated back, and the reason
    /// screen 16c carries a footnote saying exactly this.
    ///
    /// - Parameters:
    ///   - daysPerWeek: 1...7, as committed.
    ///   - target: how many practised days we're counting to (default 30).
    ///   - from: start date (defaults to today at the caller's clock).
    /// - Returns: the projected date, or nil if daysPerWeek is out of range.
    public static func streakDate(daysPerWeek: Int, target: Int = 30,
                                  from start: Date, calendar: Calendar = .current) -> Date? {
        guard (1...7).contains(daysPerWeek), target > 0 else { return nil }
        // Practising n days a week means target days take target/n weeks.
        let weeks = Double(target) / Double(daysPerWeek)
        let days = Int((weeks * 7).rounded())
        return calendar.date(byAdding: .day, value: days, to: start)
    }

    /// A rising four-week curve for the projection chart. Deliberately NOT a
    /// promise about their score: it's the count of practised days accumulating
    /// at the rate they chose, which is arithmetic and can't be wrong.
    public static func weeklyCumulativeDays(daysPerWeek: Int, weeks: Int = 4) -> [Int] {
        guard (1...7).contains(daysPerWeek), weeks > 0 else { return [] }
        return (1...weeks).map { $0 * daysPerWeek }
    }
}

/// The four "practice profile" cards on screen 16b — each one a direct echo of
/// something they said, never an inference we dressed up as insight.
public struct PracticeProfile: Equatable {
    public let chasing: String
    public let pattern: String
    public let anchorLine: String
    public let blindSpot: String

    public init(from a: OnboardingAnswers) {
        chasing = a.primaryMotivation?.label ?? "A steadier mind"

        // The identity answer outranks the restart count: someone who told us
        // they already meditate shouldn't be profiled by how often they've
        // stopped. Their card names what they came for.
        if a.intendedFor == .alreadyPractice || a.restarts == .sticks {
            pattern = "Already practicing. Now it gets measured"
        } else {
            switch a.restarts {
            case .never:      pattern = "Starting fresh"
            case .once:       pattern = "Stopped once before"
            case .few:        pattern = "Started and stopped a few times"
            case .many, .some(.lostCount): pattern = "Started and stopped more times than you'd like"
            // Unreachable (handled above), but the switch must stay exhaustive.
            case .sticks:     pattern = "Already practicing. Now it gets measured"
            case .none:       pattern = "Building the habit"
            }
        }

        anchorLine = a.anchor.map { "You practise \($0.phrase)" }
            ?? "You'll find your time"

        blindSpot = a.primaryCause?.label ?? "Not knowing whether it worked"
    }
}
