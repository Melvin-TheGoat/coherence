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
    case lessStressed, sharperFocus, moreDiscipline, betterSleep, lessAnxious,
         deeperPractice, manifestGoals, changeIdentity, other
    /// Added 2026-09-23 for "What's your goal with meditation?" (Aziz). New
    /// cases go LAST: the answers are stored by raw value, but keeping the
    /// declaration order stable keeps every switch and test readable.
    case morePresent, overthinkLess, justCurious

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .lessStressed:   return "Feel less stressed"
        case .sharperFocus:   return "Sharpen my focus"
        case .moreDiscipline: return "More discipline"
        case .betterSleep:    return "Sleep better"
        case .lessAnxious:    return "Less anxious"
        case .deeperPractice: return "Deeper prayer or practice"
        case .manifestGoals:  return "Manifest my goals"
        case .changeIdentity: return "Change who I am"
        case .other:          return "Something else"
        case .morePresent:    return "Be more present"
        case .overthinkLess:  return "Overthink less"
        case .justCurious:    return "Just curious"
        }
    }

    /// What the motivation screen offers. `.lessAnxious` was cut 2026-08-25
    /// (Melvin: same thing as less stressed, and the list was giving him
    /// choice fatigue) but the case survives so stored answers still decode.
    ///
    /// **Six, one pick** since 2026-09-23 (Aziz, from Brainrot's goal
    /// screen): "What's your goal with meditation?". Making it a daily habit
    /// is left out on purpose: that is what the whole app is for, so it goes
    /// without saying. The older cases stay so stored answers still decode.
    public static var offered: [Motivation] {
        [.lessStressed, .sharperFocus, .betterSleep, .morePresent, .overthinkLess, .justCurious]
    }

    public var icon: String {
        switch self {
        case .lessStressed:   return "wind"
        case .sharperFocus:   return "scope"
        case .moreDiscipline: return "flame"
        case .betterSleep:    return "moon.stars"
        case .lessAnxious:    return "heart"
        case .deeperPractice: return "hands.and.sparkles"
        case .manifestGoals:  return "sparkles"
        case .changeIdentity: return "person.crop.circle.badge.checkmark"
        case .other:          return "ellipsis.circle"
        case .morePresent:    return "leaf"
        case .overthinkLess:  return "brain.head.profile"
        case .justCurious:    return "questionmark.circle"
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

    /// The slider's readout (Aziz, 2026-09-25). `allCases` runs from "Not
    /// yet" at the left to "Every day" at the right, which is the slider.
    public var sliderLabel: String {
        switch self {
        case .never:           return "Not yet"
        case .triedNeverStuck: return "Once in a while"
        case .fewTimesMonth:   return "A few times a month"
        case .mostWeeks:       return "A few times a week"
        case .almostDaily:     return "Every day"
        }
    }

    /// The line under the slider, one per stop. Encouraging, and never what
    /// the reader lacks (the standing copy rule).
    public var sliderLine: String {
        switch self {
        case .never:           return "The perfect time to start. I've got you."
        case .triedNeverStuck: return "Every session counts from here."
        case .fewTimesMonth:   return "A great base to build on."
        case .mostWeeks:       return "You're close. A few more days and it's a habit."
        case .almostDaily:     return "You've done the hardest part. Let's keep it going."
        }
    }

    /// Of the week's seven flames, how many light at this stop, and whether
    /// they are only faintly lit (once in a while).
    public var flames: (lit: Int, faint: Bool) {
        switch self {
        case .never:           return (0, false)
        case .triedNeverStuck: return (1, true)
        case .fewTimesMonth:   return (1, false)
        case .mostWeeks:       return (4, false)
        case .almostDaily:     return (7, false)
        }
    }

    public var label: String {
        switch self {
        case .never:           return "Never. This would be the start"
        case .triedNeverStuck: return "I've tried, it never stuck"
        case .fewTimesMonth:   return "A few times a month"
        case .mostWeeks:       return "A few times a week"
        case .almostDaily:     return "Daily"
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
        case .sticks:    return "It sticks. I'm here for the stats and community"
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
    /// Never meant to. The question presumed an intention, and a tester who
    /// had none found no true answer (2026-09-14). Listed first so it is the
    /// first thing a person with no history sees.
    case never
    case weeks, months, aYear, forever
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
        case .never:   return "I haven't, honestly"
        case .weeks:   return "A few weeks"
        case .months:  return "Months"
        case .aYear:   return "A year or more"
        case .forever: return "As long as I can remember"
        case .alreadyPractice: return "I already meditate. I'm here for the stats"
        }
    }

    public var icon: String {
        switch self {
        case .never:   return "leaf"
        case .weeks:   return "calendar"
        case .months:  return "calendar.badge.clock"
        case .aYear:   return "hourglass"
        case .forever: return "infinity"
        case .alreadyPractice: return "chart.xyaxis.line"
        }
    }

    /// Phrase for reflecting the answer back ("you've been meaning to for years").
    public var phrase: String {
        switch self {
        case .never:   return "not at all, until now"
        case .weeks:   return "a few weeks"
        case .months:  return "months"
        case .aYear:   return "a year or more"
        case .forever: return "as long as you can remember"
        case .alreadyPractice: return "already, in your own practice"
        }
    }
}

/// Why they stopped. Every option is one 808 has an answer for — that mapping
/// is the whole point of screen 16d, so it lives on the case itself.
/// Q · body A: does a session have a hidden physical story? Every answer is a
/// yes of a different size; the question plants the idea without claiming
/// anything (approved 2026-08-29).
public enum BodyCuriosity: String, CaseIterable, Identifiable, Codable {
    case allTheTime, afterGoodOnes, neverThought, assumedNoWay

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .allTheTime:   return "All the time"
        case .afterGoodOnes: return "Sometimes, after a good one"
        case .neverThought: return "Never thought about it until now"
        case .assumedNoWay: return "I assumed there was no way to know"
        }
    }

    public var icon: String {
        switch self {
        case .allTheTime:   return "sparkle.magnifyingglass"
        case .afterGoodOnes: return "clock.arrow.circlepath"
        case .neverThought: return "lightbulb"
        case .assumedNoWay: return "eye.slash"
        }
    }
}

/// Q · body B: how they currently judge a session. Asks about their life, not
/// our instrument, so it needs no metric expertise (the earlier draft asked
/// which metric they'd want to see, and was cut for exactly that reason).
/// Three options, per Aziz.
public enum BodyProof: String, CaseIterable, Identifiable, Codable {
    case byFeel, dont, wantProof

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .byFeel:    return "I go by how I feel after"
        case .dont:      return "Honestly, I don't"
        case .wantProof: return "I've always wanted real proof"
        }
    }

    public var icon: String {
        switch self {
        case .byFeel:    return "hand.wave"
        case .dont:      return "questionmark.circle"
        case .wantProof: return "checkmark.seal"
        }
    }
}

/// Q · body C: the ICP validator. People who close rings already believe in
/// measurement; meditation is the one practice giving them nothing back.
public enum BodyTracking: String, CaseIterable, Identifiable, Codable {
    case rings, sleep, heart, workouts, nothing

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .rings:    return "Activity rings or steps"
        case .sleep:    return "Sleep"
        case .heart:    return "Heart rate or HRV"
        case .workouts: return "Runs, lifts, workouts"
        case .nothing:  return "Nothing yet"
        }
    }

    public var icon: String {
        switch self {
        case .rings:    return "circle.circle"
        case .sleep:    return "moon.stars"
        case .heart:    return "heart"
        case .workouts: return "figure.run"
        case .nothing:  return "circle.dotted"
        }
    }
}

/// "What usually gets in the way of meditating?" (Aziz, 2026-09-23). Asked
/// straight after the goal, because Otto has just promised "Your answers show
/// me what gets in the way, so I can help you keep going": this is that
/// question, in the present tense, for everyone (not only people who quit,
/// which is who `DropoutCause` was written for). Pick any.
public enum Obstacle: String, CaseIterable, Identifiable, Codable {
    case forget, noTime, mindWontSettle, unsureDoingItRight, loseMotivation, phonePulls

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .forget:             return "I forget"
        case .noTime:             return "I don't have time"
        case .mindWontSettle:     return "My mind won't settle"
        case .unsureDoingItRight: return "I'm not sure I'm doing it right"
        case .loseMotivation:     return "I lose motivation after a few days"
        case .phonePulls:         return "My phone pulls me away"
        }
    }

    public var icon: String {
        switch self {
        case .forget:             return "bell.slash"
        case .noTime:             return "clock"
        case .mindWontSettle:     return "tornado"
        case .unsureDoingItRight: return "questionmark.circle"
        case .loseMotivation:     return "battery.25"
        case .phonePulls:         return "iphone"
        }
    }
}

/// "Which one sounds most like you?" (Aziz, 2026-09-23, Brainrot's
/// "Which best describes you?" reworded). One pick.
public enum Role: String, CaseIterable, Identifiable, Codable {
    case creative, deskJob, founder, athlete, student, liveWell

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .creative: return "Creative"
        case .deskJob:  return "Employee"
        case .founder:  return "Founder"
        case .athlete:  return "Athlete"
        case .student:  return "Student"
        case .liveWell: return "Just trying to live well"
        }
    }

    public var icon: String {
        switch self {
        case .creative: return "paintpalette"
        case .deskJob:  return "desktopcomputer"
        case .founder:  return "chart.line.uptrend.xyaxis"
        case .athlete:  return "figure.run"
        case .student:  return "book.closed"
        case .liveWell: return "heart"
        }
    }
}

/// "When could you fit in a few quiet minutes?" (Aziz, 2026-09-23). One
/// pick, and it is not decorative: the answer becomes the daily reminder's
/// time, already set on the reminder screen later. The old anchor question
/// did this job until it was cut, and the reminder sat at 8 AM since.
public enum QuietTime: String, CaseIterable, Identifiable, Codable {
    case morning, breakInDay, afternoon, evening, beforeBed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .morning:    return "First thing in the morning"
        case .breakInDay: return "On a break during the day"
        case .afternoon:  return "In the afternoon"
        case .evening:    return "In the evening"
        case .beforeBed:  return "Right before bed"
        }
    }

    public var icon: String {
        switch self {
        case .morning:    return "sunrise"
        case .breakInDay: return "cup.and.saucer"
        case .afternoon:  return "sun.max"
        case .evening:    return "sunset"
        case .beforeBed:  return "moon.stars"
        }
    }

    /// The reminder it sets, as hour and minute.
    public var reminder: (hour: Int, minute: Int) {
        switch self {
        case .morning:    return (8, 0)
        case .breakInDay: return (12, 30)
        case .afternoon:  return (15, 30)
        case .evening:    return (19, 0)
        case .beforeBed:  return (22, 0)
        }
    }

    /// Today at that time, which is how `OnboardingAnswers.reminderTime`
    /// holds a time of day.
    public func reminderDate(calendar: Calendar = .current, now: Date = Date()) -> Date? {
        calendar.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: now)
    }
}

/// "Have you tried to make meditation a habit before?" (Aziz, 2026-09-23,
/// Brainrot's "Have you tried to reduce screen time before?"). One pick.
public enum HabitHistory: String, CaseIterable, Identifiable, Codable {
    case didntStick, workedForAWhile, firstTry

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .didntStick:      return "Yes, but it didn't stick"
        case .workedForAWhile: return "Yes, it worked for a while"
        case .firstTry:        return "No, this is my first try"
        }
    }

    public var icon: String {
        switch self {
        case .didntStick:      return "heart.slash"
        case .workedForAWhile: return "hand.thumbsup"
        case .firstTry:        return "sparkles"
        }
    }
}

/// "How old are you?" (Aziz, 2026-09-25, Brainrot's question). Stored in
/// `OnboardingAnswers.ageBracket` as the label, the field the cut `you`
/// question used. "Prefer not to say" is there on purpose: App Review 5.1.1
/// rejects apps that REQUIRE personal information they do not need to work,
/// and nothing in 808 needs an age.
public enum AgeRange: String, CaseIterable, Identifiable, Codable {
    case under18 = "Under 18"
    case from18 = "18 to 24"
    case from25 = "25 to 34"
    case from35 = "35 to 44"
    case from45 = "45 to 54"
    case over55 = "55+"
    case notSaying = "Prefer not to say"

    public var id: String { rawValue }
    public var label: String { rawValue }
}

/// "When something stresses you out, how quickly do you settle back down?"
/// (Aziz, 2026-09-25). Feeds the profile's Emotional balance bar.
public enum StressRecovery: String, CaseIterable, Identifiable, Codable {
    case rightAway, withinHour, allDay, forDays

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .rightAway:  return "Right away"
        case .withinHour: return "Within an hour"
        case .allDay:     return "It stays with me all day"
        case .forDays:    return "It sticks around for days"
        }
    }

    public var icon: String {
        switch self {
        case .rightAway:  return "hare"
        case .withinHour: return "clock"
        case .allDay:     return "sun.max"
        case .forDays:    return "calendar"
        }
    }
}

/// The profile at the end of the questions (Aziz, 2026-09-25, Brainrot's
/// "Your attention profile is"). Five kinds of Otto, each drawn to match. It
/// is the reader's own answers played back, never a measurement: there is no
/// percentage anywhere on it, only a type and two bar positions.
public enum MindProfile: String, CaseIterable, Codable {
    case racingMind, fullPlate, alwaysOn, comeback, freshStart

    public var name: String {
        switch self {
        case .racingMind: return "The Racing Mind"
        case .fullPlate:  return "The Full Plate"
        case .alwaysOn:   return "The Always-On Mind"
        case .comeback:   return "The Comeback"
        case .freshStart: return "The Fresh Start"
        }
    }

    /// Encouraging, and never a foil ("not X but Y"): the standing copy rules.
    public var line: String {
        switch self {
        case .racingMind: return "Your thoughts move fast. A few quiet minutes a day is how you slow them down."
        case .fullPlate:  return "Your days are packed. Short sessions that fit around them are what will stick."
        case .alwaysOn:   return "Your phone gets a lot of your attention. A few minutes a day is how you take some back."
        case .comeback:   return "You've started before and you know it works. Now it's about coming back every day."
        case .freshStart: return "Everything's ahead of you. Starting small and showing up is all it takes."
        }
    }

    /// Which one. Several obstacles can be picked, so a fixed order decides,
    /// the answer 808 can help with most directly first (Aziz, 2026-09-25):
    /// 1. Always-On: "My phone pulls me away".
    /// 2. Racing Mind: "My mind won't settle" or the goal "Overthink less".
    /// 3. Full Plate: "I don't have time".
    /// 4. Fresh Start: none of those, and new (never meditated, a first try,
    ///    or "I'm not sure I'm doing it right").
    /// 5. Comeback: none of those, and they have meditated before.
    /// Only Comeback's line assumes a history, so being new only has to keep
    /// someone out of Comeback; the other three lines fit a beginner too. And
    /// someone who meditates every day is never "coming back": with nothing
    /// else to go on they read as a Racing Mind.
    public static func of(_ a: OnboardingAnswers) -> MindProfile {
        let obstacles = a.obstacles ?? []
        if obstacles.contains(.phonePulls) { return .alwaysOn }
        if obstacles.contains(.mindWontSettle) || a.motivations.contains(.overthinkLess) { return .racingMind }
        if obstacles.contains(.noTime) { return .fullPlate }
        let isNew = a.currentFrequency == .never
            || obstacles.contains(.unsureDoingItRight)
            || (a.habitHistory == .firstTry
                && (a.currentFrequency == nil || a.currentFrequency == .triedNeverStuck))
        if isNew { return .freshStart }
        if a.currentFrequency == .almostDaily { return .racingMind }
        return .comeback
    }

    /// The drawing for this profile, and how much of its height is his body
    /// from his head (below the tuft) to his seat, measured on the cut-outs
    /// (the Racing Mind's swirls stand above his head), so each is drawn at
    /// the valley Otto's size.
    public var art: (asset: String, bodyShare: Double) {
        switch self {
        case .racingMind: return ("OttoProfileRacing", 381.0 / 458.0)
        case .fullPlate:  return ("OttoProfileFullPlate", 396.0 / 421.0)
        case .alwaysOn:   return ("OttoProfileAlwaysOn", 398.0 / 424.0)
        case .comeback:   return ("OttoProfileComeback", 393.0 / 419.0)
        case .freshStart: return ("OttoProfileFresh", 400.0 / 427.0)
        }
    }

    /// Headspace, 0 cluttered to 1 clear: stress, a mind that won't settle,
    /// the phone and wanting to overthink less each move it toward cluttered.
    /// Never quite at either end, because it is a reading of a few answers.
    public static func headspace(_ a: OnboardingAnswers) -> Double {
        let obstacles = a.obstacles ?? []
        var clear = 1.0 - 0.45 * min(max(a.stress, 0), 1)
        if obstacles.contains(.mindWontSettle) { clear -= 0.20 }
        if obstacles.contains(.phonePulls) { clear -= 0.10 }
        if a.motivations.contains(.overthinkLess) { clear -= 0.10 }
        return min(max(clear, 0.08), 0.94)
    }

    /// Emotional balance, 0 reactive to 1 steady: mostly how fast they settle
    /// after stress, nudged by how stressed they have been lately.
    public static func balance(_ a: OnboardingAnswers) -> Double {
        let base: Double
        switch a.recovery {
        case .rightAway?:  base = 0.88
        case .withinHour?: base = 0.64
        case .allDay?:     base = 0.36
        case .forDays?:    base = 0.14
        case nil:          base = 0.5
        }
        let steady = base - 0.12 * (min(max(a.stress, 0), 1) - 0.5)
        return min(max(steady, 0.08), 0.94)
    }
}

public enum DropoutCause: String, CaseIterable, Identifiable, Codable {
    case couldntTell, tooManyChoices, forgot, feltWrong, noTime, gotBoring,
         noAccountability

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .couldntTell:    return "I couldn't tell it was working"
        case .tooManyChoices: return "Too many choices every time"
        case .forgot:         return "I forgot"
        case .feltWrong:      return "I felt like I was doing it wrong"
        case .noTime:         return "I ran out of time"
        case .gotBoring:      return "It got boring"
        case .noAccountability: return "No one kept me accountable"
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
        case .noAccountability: return "person.2.slash"
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
        // The only answer that reaches outside the app, which is the point:
        // nothing on your own phone can be the person expecting you.
        case .noAccountability: return "A streak that notices, and people practicing alongside you"
        }
    }
}

/// When they'll practice — anchored to something they already do daily,
/// because anchoring to an existing routine measurably lowered abandonment
/// (Mindfulness, 2023; see ONBOARDING.md).
public enum Anchor: String, CaseIterable, Identifiable, Codable {
    case wake, coffee, commute, lunch, afterWork, beforeSport, beforeBed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .wake:      return "Right after I wake up"
        case .coffee:    return "With my morning coffee"
        case .commute:   return "After my commute"
        case .lunch:     return "Around lunch"
        case .afterWork: return "When I get home from work"
        case .beforeSport: return "Before my sport or hobby"
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
        case .beforeSport: return "figure.run"
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
        case .beforeSport: return "before you train"
        case .beforeBed: return "before bed"
        }
    }

    /// The same phrase in the FIRST person, for sentences the user speaks
    /// ("I'll practice 5 days a week, with my morning coffee"). The
    /// commitment screen used `phrase` and produced "I'll practice … with
    /// your morning coffee", a person mismatch only a walkthrough caught
    /// (2026-08-31).
    public var firstPersonPhrase: String {
        switch self {
        case .wake:      return "right after I wake up"
        case .coffee:    return "with my morning coffee"
        case .commute:   return "after my commute"
        case .lunch:     return "around lunch"
        case .afterWork: return "when I get home"
        case .beforeSport: return "before I train"
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
        // Early evening: the usual slot for training or a hobby, and it keeps
        // the reminder clear of the before-bed one.
        case .beforeSport: return 17
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
    /// What gets in the way (`Obstacle`). OPTIONAL on purpose: synthesized
    /// Codable requires every non-optional key, so a plain property would
    /// have made every saved resume record from before it fail to decode.
    public var obstacles: Set<Obstacle>?
    /// How quickly they settle after stress (`StressRecovery`). Optional.
    public var recovery: StressRecovery?
    /// Which one sounds most like them (`Role`). Optional for the same reason.
    public var role: Role?
    /// When a few quiet minutes fit (`QuietTime`). Optional, as above.
    public var quietTime: QuietTime?
    /// Whether they have tried to make it a habit (`HabitHistory`). Optional.
    public var habitHistory: HabitHistory?
    /// Their own words, only when "Something else" is picked. Never required.
    public var motivationOther: String = ""
    /// 0 = "Fine", 1 = "Fried".
    public var stress: Double = 0.5
    public var aloneWithThoughts: AloneWithThoughts?
    public var doingNothing: DoingNothing?
    public var restarts: RestartCount?
    public var intendedFor: IntendedFor?
    /// Kept although its question was removed (2026-08-29): the field decodes
    /// interrupted onboardings saved before the change, and the reflection
    /// copy still reads `primaryCause` as a fallback.
    public var causes: Set<DropoutCause> = []
    public var bodyCuriosity: BodyCuriosity?
    public var bodyProof: BodyProof?
    public var bodyTracking: Set<BodyTracking> = []
    public var costs: Set<CostSymptom> = []
    public var hasWatch: Bool?
    public var anchor: Anchor?
    /// The daily reminder time, picked on the notification screen since the
    /// anchor question was cut (2026-09-15). Nil means the 8 AM default.
    public var reminderTime: Date?
    public var firstName: String = ""
    public var username: String = ""
    public var ageBracket: String?
    public var referral: ReferralSource?
    /// What a regular practitioner can't see (regular persona only).
    public var blindSpot: BlindSpot?
    /// Days per week they commit to.
    public var daysPerWeek: Int = 5

    public init() {}

    #if DEBUG
    /// A fully answered set, for opening any onboarding screen directly while
    /// reviewing copy (see `ONBOARDING_STEP`). Screens that quote the user back
    /// to themselves render blank without it.
    /// Plausible answers for reviewing a screen without tapping through the
    /// interview. `ONBOARDING_PERSONA=newcomer|restarter|regular` picks the
    /// path, because each persona answers a different set of questions and the
    /// payoff screens read them back. Defaults to the restarter, the broadest.
    public static var sample: OnboardingAnswers {
        sample(ProcessInfo.processInfo.environment["ONBOARDING_PERSONA"]
                 .flatMap(OnboardingPersona.init(rawValue:)) ?? .restarter)
    }

    public static func sample(_ persona: OnboardingPersona) -> OnboardingAnswers {
        var a = OnboardingAnswers()
        a.motivations = [.lessStressed, .moreDiscipline]
        a.stress = 0.72
        a.costs = [.cantFocus, .knowButDont]
        a.hasWatch = true
        a.anchor = .coffee
        a.firstName = "Melvin"
        a.ageBracket = "25-34"
        a.daysPerWeek = 5

        // Only ever fill what this persona is actually asked. Leaving a field
        // set that the interview never collects is precisely the bug the
        // payoff screens had.
        // Everyone is asked what they track; only people with sessions to
        // wonder about get the curiosity and proof questions.
        a.bodyTracking = [.rings, .sleep]
        switch persona {
        case .newcomer:
            a.currentFrequency = .never
            a.intendedFor = .months
        case .restarter:
            a.currentFrequency = .triedNeverStuck
            a.restarts = .few
            a.bodyCuriosity = .afterGoodOnes
            a.bodyProof = .wantProof
        case .regular:
            a.currentFrequency = .mostWeeks
            a.blindSpot = .whichWorks
            a.bodyCuriosity = .allTheTime
            a.bodyProof = .byFeel
        }
        return a
    }
    #endif

    /// The single cause we speak to when we can only name one. Ordered by how
    /// directly 808 answers it, not by the enum's declaration order.
    public var primaryCause: DropoutCause? {
        let priority: [DropoutCause] = [.couldntTell, .noAccountability, .tooManyChoices,
                                        .forgot, .feltWrong, .gotBoring, .noTime]
        return priority.first { causes.contains($0) } ?? causes.first
    }

    public var primaryMotivation: Motivation? {
        let priority: [Motivation] = [.moreDiscipline, .lessAnxious, .lessStressed,
                                      .overthinkLess, .sharperFocus, .betterSleep,
                                      .morePresent, .changeIdentity, .manifestGoals,
                                      .deeperPractice, .justCurious, .other]
        return priority.first { motivations.contains($0) } ?? motivations.first
    }

    /// "Fried" end of the slider. Used to choose which pain we reflect back.
    public var isHighStress: Bool { stress >= 0.6 }

    /// They told us they already have a practice, whether that came from the
    /// baseline question or from one of the two escape-hatch answers.
    ///
    /// **Every payoff screen must ask this rather than testing the escape
    /// hatches itself.** The old checks read `intendedFor == .alreadyPractice
    /// || restarts == .sticks`, and a regular meditator is asked neither
    /// question, so both were nil and they fell through to the dropout copy:
    /// "You're building the habit", under a clinical dropout statistic, shown
    /// to someone who meditates almost daily.
    public var alreadyPracticing: Bool {
        persona == .regular || intendedFor == .alreadyPractice || restarts == .sticks
    }

    /// What they named as their own problem, paired with what 808 does about
    /// it. A restarter names dropout causes, a regular names a blind spot, and
    /// a newcomer has named neither.
    ///
    /// **Empty is a real answer.** The screen that renders these puts them
    /// under a "You said" header, so inventing a fallback would quote a
    /// sentence back at someone who never said it.
    public var namedConcerns: [NamedConcern] {
        // Enum order, not selection order, so two people who ticked the same
        // things in a different sequence see the same screen.
        let named = DropoutCause.allCases.filter { causes.contains($0) }
        if !named.isEmpty {
            return named.map { NamedConcern(id: $0.rawValue, quote: $0.label, answer: $0.answer) }
        }
        if let blindSpot {
            return [NamedConcern(id: blindSpot.rawValue,
                                 quote: blindSpot.label,
                                 answer: blindSpot.answer)]
        }
        return []
    }

    /// The answers to problems they did not name. Always the dropout answers,
    /// because those are what the product replies to whether or not this
    /// particular person has quit before.
    public var unnamedCauses: [DropoutCause] {
        DropoutCause.allCases.filter { !causes.contains($0) }
    }

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

    /// The date their 30th practiced day lands, given the days-per-week they
    /// just committed to. **Real arithmetic from their own answer** — the one
    /// number in onboarding that isn't simply repeated back, and the reason
    /// screen 16c carries a footnote saying exactly this.
    ///
    /// - Parameters:
    ///   - daysPerWeek: 1...7, as committed.
    ///   - target: how many practiced days we're counting to (default 30).
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
    /// promise about their score: it's the count of practiced days accumulating
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

        // Persona first: someone who told us they already meditate shouldn't be
        // profiled by how often they've stopped, and only a restarter was ever
        // asked the restart count. Reading `restarts` for anyone else meant
        // reading nil and printing "Building the habit" at a daily meditator.
        if a.alreadyPracticing {
            pattern = "Already practicing. Now it gets measured"
        } else if a.persona == .newcomer {
            pattern = "Starting fresh"
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

        anchorLine = a.anchor.map { "You practice \($0.phrase)" }
            ?? "You'll find your time"

        // Their own words where we have them. The regular answered this
        // directly and that answer used to be discarded here; the restarter
        // named it as a dropout cause. A newcomer named neither, so the card
        // looks forward instead of asserting a blind spot they can't have yet.
        if let named = a.blindSpot?.label ?? a.primaryCause?.label {
            blindSpot = named
        } else if a.persona == .newcomer {
            blindSpot = "Whether it's working, once you start"
        } else {
            blindSpot = "Not knowing whether it worked"
        }
    }
}

// MARK: - Who we're talking to

/// Which kind of arrival this is, derived from the very first question.
///
/// **Why this exists.** The interview used to run the same twelve screens for
/// everyone, which meant someone who answered "Never. This would be the start"
/// was still asked *"What made you stop meditating?"* two screens later. The
/// first wrong question destroys the personalisation the whole flow is selling
/// — and the escape-hatch options bolted onto `RestartCount.sticks` and
/// `IntendedFor.alreadyPractice` are the scar tissue from patching that with
/// extra answers instead of fewer questions.
///
/// Deriving a persona lets us *not ask* rather than ask and forgive.
public enum OnboardingPersona: String, CaseIterable, Codable {
    /// Has never really practiced. Their pain is starting.
    case newcomer
    /// Has practiced and it didn't hold. Their pain is consistency.
    case restarter
    /// Practises regularly already. Their pain is flying blind.
    case regular

    public var summary: String {
        switch self {
        case .newcomer:  return "hasn't started yet"
        case .restarter: return "starts and stops"
        case .regular:   return "already practices"
        }
    }
}

extension OnboardingAnswers {

    /// The persona, from the baseline answer alone. Nil until they've answered
    /// the first question — callers should treat nil as `.restarter`, the
    /// broadest path, rather than branching on an unanswered question.
    public var persona: OnboardingPersona {
        switch currentFrequency {
        case .never:                        return .newcomer
        case .triedNeverStuck, .fewTimesMonth: return .restarter
        case .mostWeeks, .almostDaily:      return .regular
        case nil:                           return .restarter
        }
    }

    /// Whether a given interview question is worth asking this person.
    ///
    /// The rule: **never ask a question whose premise the user has already
    /// contradicted.** A newcomer has nothing to have stopped; a regular
    /// practitioner isn't "meaning to start".
    public func asks(_ step: InterviewStep) -> Bool {
        switch step {
        // Everyone. These work regardless of history.
        case .baseline, .motivation, .obstacles, .role, .quietTime, .habitHistory, .age, .stress, .recovery, .referral:
            return true

        // Presumes previous attempts.
        case .restarts:
            return persona == .restarter

        // Presumes they haven't started.
        case .intendedFor:
            return persona == .newcomer

        // Everyone tracks something, or meaningfully doesn't.
        case .bodyTracking:
            return true

        // Only meaningful for someone with a practice to be blind about.
        case .blindSpot:
            return persona == .regular
        }
    }

    /// The interview this person will actually be shown, in order.
    public var interview: [InterviewStep] {
        InterviewStep.allCases.filter(asks)
    }

    /// The most questions any reader is asked, over every path the branching
    /// can take. **Not `InterviewStep.allCases.count`**, which counts the
    /// questions that EXIST: nobody is ever asked all of them, because the
    /// model skips any question whose premise this person has contradicted.
    ///
    /// Onboarding declares this number before the first question (Duolingo's
    /// move, Melvin 2026-09-20), so it has to be a ceiling that is true on
    /// every path rather than a promise of a fixed count: a newcomer is asked
    /// seven and everyone else eight. Derived from the model rather than
    /// typed into a screen, so cutting a question moves the copy with it.
    public static var longestInterview: Int {
        let paths: [CurrentFrequency?] = CurrentFrequency.allCases.map { Optional($0) } + [nil]
        return paths.map { frequency in
            var answers = OnboardingAnswers()
            answers.currentFrequency = frequency
            return answers.interview.count
        }.max() ?? 0
    }
}

/// The question screens, in canonical order. Separate from the view's `Step`
/// enum so the branching is pure Foundation and can be exhaustively tested
/// without a running app.

/// A reader's position in their own interview: "3 of 7", where seven is the
/// number of questions THIS person is asked after the model has skipped the
/// ones whose premise they contradicted. Never the number of questions that
/// exist.
public struct InterviewCount: Equatable {
    public let index: Int
    public let total: Int
    public init(index: Int, total: Int) {
        self.index = index
        self.total = total
    }
}

public enum InterviewStep: String, CaseIterable, Codable {
    /// Attribution FIRST (Melvin, 2026-09-14). It sat last, and only 42% of
    /// installs finish the interview, so most people never told us where
    /// they came from. Asked at the door, nearly everyone answers.
    /// The goal comes first (Aziz, 2026-09-23): it follows "Let's
    /// personalize 808 for you" the way Brainrot's goal screen follows its
    /// own, and the writing Otto carries across into its corner.
    case motivation
    /// What gets in the way, straight after the goal (Aziz, 2026-09-23).
    case obstacles
    /// How stressed have you been lately, the Otto slider, moved up from the
    /// old questions (Aziz, 2026-09-25): the profile's Headspace bar reads it.
    case stress
    /// How quickly do you settle back down, for Emotional balance.
    case recovery
    /// Which one sounds most like you, third (Aziz, 2026-09-23).
    case role
    /// When a few quiet minutes fit, fourth; sets the reminder (Aziz).
    case quietTime
    /// Have you tried to make meditation a habit before, fifth (Aziz).
    case habitHistory
    /// How old are you, sixth, then "Did you know?" (Aziz, 2026-09-25).
    case age
    /// How often do you meditate right now: the slider after "Did you know?"
    /// (Aziz, 2026-09-25), moved up from after `referral`.
    case baseline
    case referral
    case restarts, intendedFor
    case bodyTracking
    case blindSpot
    // CUT 2026-09-23 (Melvin): `bodyCuriosity`, "When you meditate, do you
    // ever wonder what your body is actually doing?". A question about
    // measurement in an app whose sessions mostly measure nothing now.
    // `OnboardingAnswers.bodyCuriosity` stays so resume records decode.
    // CUT 2026-09-22 (Melvin): `watchGate`. Sessions no longer need a Watch
    // (Aziz, 2026-09-21), so asking whether you own one sorted people for a
    // difference the app stopped making. `OnboardingAnswers.hasWatch` stays
    // so resume records decode; nothing asks it any more.
    // CUT 2026-09-19 (Melvin): `aloneWithThoughts` (the last escalation
    // question, gone the way `doingNothing` went) and `you` (name and age;
    // the nickname and handle are asked on Create your profile, so this
    // asked twice for the name and once for an age nothing used).
    // CUT 2026-09-15 (Melvin: "too crowded"): `doingNothing` (the second
    // escalation question asked what `aloneWithThoughts` already had),
    // `bodyProof` (its sibling `bodyCuriosity` carries the idea alone), and
    // `anchor` (people do not want to be made to commit to a time of day;
    // the reminder time is picked on the notification screen instead). The
    // answer fields stay on `OnboardingAnswers` so old resume records and
    // every downstream reader keep decoding; they are simply never asked.
}

/// What a regular practitioner can't tell about their own practice.
///
/// The consistency questions don't apply to someone who already sits most days
/// — their pain isn't stopping, it's having no idea whether any of it is
/// working. This is the one question that's theirs.
public enum BlindSpot: String, CaseIterable, Identifiable, Codable {
    case gettingCalmer, todayVsYesterday, improving, whichWorks, justTheData

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .gettingCalmer:    return "Whether I actually settle"
        case .todayVsYesterday: return "If today went better than yesterday"
        case .improving:        return "Whether I'm improving at all"
        case .whichWorks:       return "Which sessions work and which don't"
        case .justTheData:      return "Nothing. I just want the data"
        }
    }

    public var icon: String {
        switch self {
        case .gettingCalmer:    return "waveform.path.ecg"
        case .todayVsYesterday: return "calendar.badge.clock"
        case .improving:        return "chart.line.uptrend.xyaxis"
        case .whichWorks:       return "slider.horizontal.3"
        case .justTheData:      return "square.grid.2x2"
        }
    }

    /// What 808 does about it, in the same shape as `DropoutCause.answer`, so
    /// a regular meditator's one question gets a reply on screen 16d instead
    /// of being collected and dropped.
    ///
    /// Every line here must describe something the app actually shows. None of
    /// them may imply we read a brain state.
    public var answer: String {
        switch self {
        case .gettingCalmer:    return "A stillness and heart-rate reading from every session"
        case .todayVsYesterday: return "Every session scored the same way, so two days compare"
        case .improving:        return "Your scores as a line, across every session you've done"
        case .whichWorks:       return "Each session logged on its own, so the good ones stand out"
        case .justTheData:      return "The raw curves, not only the number on top of them"
        }
    }
}

/// One thing the user named about their own practice, next to what 808 does
/// about it. Flattens two different questions (dropout causes, blind spot)
/// into one shape so the screen isn't switching on which persona it drew.
public struct NamedConcern: Identifiable, Equatable {
    public let id: String
    public let quote: String
    public let answer: String

    public init(id: String, quote: String, answer: String) {
        self.id = id
        self.quote = quote
        self.answer = answer
    }
}
