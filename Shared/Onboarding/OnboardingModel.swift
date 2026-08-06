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
        case .never:           return "Never — this would be the start"
        case .triedNeverStuck: return "I've tried, it never stuck"
        case .fewTimesMonth:   return "A few times a month"
        case .mostWeeks:       return "Most weeks"
        case .almostDaily:     return "Almost every day"
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
        case .notLikeIUsedTo: return "No — not like I used to"
        case .harder:         return "It's got harder"
        case .same:           return "About the same"
        case .better:         return "Actually better now"
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

    /// True when stillness is already hard for them — feeds which pain the
    /// reflection screen speaks to.
    public var isRestless: Bool { self == .seconds || self == .aMinute }
}

/// How many times they've started a practice and stopped. The admission.
public enum RestartCount: String, CaseIterable, Identifiable, Codable {
    case never, once, few, many, lostCount

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .never:     return "This would be my first try"
        case .once:      return "Once"
        case .few:       return "Two or three times"
        case .many:      return "More than I'd like to admit"
        case .lostCount: return "I've lost count"
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

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .weeks:   return "A few weeks"
        case .months:  return "Months"
        case .aYear:   return "A year or so"
        case .years:   return "Years"
        case .forever: return "As long as I can remember"
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

    /// The feature that answers this objection, in the user's own framing.
    public var answer: String {
        switch self {
        case .couldntTell:    return "A score after every session"
        case .tooManyChoices: return "One tap. No length to pick, nothing to choose"
        case .forgot:         return "A nudge at the time you chose"
        case .feltWrong:      return "Your own audio, still measured"
        case .noTime:         return "Sessions end when you end them — two minutes counts"
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

        switch a.restarts {
        case .never:      pattern = "Starting fresh"
        case .once:       pattern = "Stopped once before"
        case .few:        pattern = "Started and stopped a few times"
        case .many, .some(.lostCount): pattern = "Started and stopped more times than you'd like"
        case .none:       pattern = "Building the habit"
        }

        anchorLine = a.anchor.map { "You practise \($0.phrase)" }
            ?? "You'll find your time"

        blindSpot = a.primaryCause?.label ?? "Not knowing whether it worked"
    }
}
