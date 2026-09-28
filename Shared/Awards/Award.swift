import Foundation

/// The awards catalog and the rules that earn them.
///
/// **Awards are DERIVED, never stored.** Exactly like the streak, which is
/// computed from session dates rather than written down. This is not a
/// micro-optimisation, it is what makes three separate problems disappear:
///
/// - **Backfill is free.** Melvin and Aziz open a full shelf on the first
///   launch because the rules simply read the history that is already there.
///   No migration, no one-time flag, nothing to get wrong.
/// - **An award can never be lost.** Every rule asks "did this EVER happen",
///   so a broken streak cannot take back the fifty-day award. Taking it back
///   would punish exactly the person we are trying to bring back.
/// - **Nothing can drift.** A stored award could disagree with the history it
///   claims to describe. A derived one cannot.
///
/// The one thing that IS stored is which awards have already been announced,
/// so the unlock moment fires once. See `AwardsInbox`.
///
/// **Every award comes from something measured or done.** Nothing for opening
/// the app, nothing on a timer, no participation badges. The signup award is
/// the single exception and it is honest, because beginning really is the step
/// most people never take.
///
/// **Grown from 16 to about 50 (2026-09-28).** The 16 original ids and their
/// behaviour are untouched; everything below them is new. Three groups were
/// added (`timeOfDay`, `variety`, `otto`) rather than overloading the old
/// four. **Hand-logged sessions** (`Session.isLogged`, "Record one") never
/// earn a single-session-length or time-of-day award: nothing timed them in
/// real time, so a typed-in "90 minutes" or "before 8am" would be measuring
/// a guess, not a sit. They still count toward totals, session counts and
/// streaks exactly as they already did, since a logged sit is a real sit
/// that really happened on that day.
public struct Award: Identifiable, Hashable {

    public enum Group: String, CaseIterable {
        case beginning, consistency, depth, endurance, timeOfDay, variety, otto

        public var title: String {
            switch self {
            case .beginning:   return "Beginning"
            case .consistency: return "Consistency"
            case .depth:       return "Depth"
            case .endurance:   return "Endurance"
            case .timeOfDay:   return "Time of day"
            case .variety:     return "Variety"
            case .otto:        return "Otto"
            }
        }
    }

    /// What the badge shows. Numbers where there is a number, the 808 mark
    /// where there isn't.
    public enum Face: Hashable {
        case mark
        case number(String, unit: String)
    }

    public let id: String
    public let title: String
    /// One line on the shelf and at the top of the detail page.
    public let blurb: String
    public let group: Group
    public let face: Face
    /// Why this threshold is worth reaching. Kept true: no health claims, and
    /// nothing about brain states.
    public let meaning: String

    // MARK: - The list

    public static let all: [Award] = [

        Award(id: "firstStep", title: "The first step",
              blurb: "You began.",
              group: .beginning, face: .mark,
              meaning: """
              "The journey of a thousand miles begins with a single step." Lao Tzu.

              Congratulations on beginning your meditation journey. This is the \
              one award here you did not have to measure up to, because starting \
              is the part most people never do.
              """),

        Award(id: "firstSession", title: "First meditation",
              blurb: "Your first session.",
              group: .beginning, face: .number("1", unit: "session"),
              meaning: """
              You sat down and stayed. Everything else on this shelf is built \
              on top of this one.
              """),

        Award(id: "friendBrought", title: "Brought a friend",
              blurb: "Someone you invited sat their first session.",
              group: .beginning, face: .mark,
              meaning: """
              You asked someone to sit with you, they said yes, and they sat. \
              Practice is easier to keep with company, and you gave someone \
              theirs.
              """),

        streak(3,   "Three days",   "Three in a row."),
        streak(5,   "Five days",    "Five in a row."),
        streak(7,   "One week",     "Seven in a row."),
        streak(10,  "Ten days",     "Ten in a row."),
        streak(21,  "Three weeks",  "Twenty one in a row."),
        streak(25,  "Twenty five",  "Twenty five in a row."),
        streak(50,  "Fifty",        "Fifty in a row."),
        streak(60,  "Two months",   "Sixty in a row."),
        streak(100, "One hundred",  "One hundred in a row."),
        streak(180, "Half a year",  "One hundred and eighty in a row."),
        streak(200, "Two hundred","Two hundred in a row."),
        streak(300, "Three hundred","Three hundred in a row."),
        streak(365, "A full year",  "Three hundred and sixty five in a row."),

        Award(id: "score50", title: "It landed",
              blurb: "A session scoring 50 or more.",
              group: .depth, face: .number("50", unit: "score"),
              meaning: """
              Your body settled enough for the measurements to say so. The score \
              is how deep you got and how long you held it, nothing else.
              """),

        Award(id: "score75", title: "Deep",
              blurb: "A session scoring 75 or more.",
              group: .depth, face: .number("75", unit: "score"),
              meaning: """
              A heart that came down and stayed down, a body that stopped asking \
              for attention. Sessions like this are not something you can force, \
              which is why they are worth marking.
              """),

        Award(id: "score90", title: "Rare air",
              blurb: "A session scoring 90 or more.",
              group: .depth, face: .number("90", unit: "score"),
              meaning: """
              Near the top of what the measurements can register. Most practice \
              does not go here, and chasing it tends to prevent it.
              """),

        Award(id: "min20", title: "Twenty minutes",
              blurb: "A single session of 20 minutes.",
              group: .endurance, face: .number("20", unit: "min"),
              meaning: """
              Twenty minutes is where the score's time factor stops climbing, \
              and it is the length most traditions land on independently.
              """),

        Award(id: "min30", title: "Half an hour",
              blurb: "A single session of 30 minutes.",
              group: .endurance, face: .number("30", unit: "min"),
              meaning: """
              Past the point where sitting still is the hard part.
              """),

        Award(id: "min60", title: "One hour",
              blurb: "A single session of 60 minutes.",
              group: .endurance, face: .number("60", unit: "min"),
              meaning: """
              An hour on the cushion. There is no research saying an hour beats \
              twenty minutes, so take this one as endurance rather than depth.
              """),

        // MARK: New milestones (2026-09-28)

        sessionCount(5,    "Five sessions",         "Five sessions logged."),
        sessionCount(10,   "Ten sessions",          "Ten sessions logged."),
        sessionCount(25,   "Twenty five sessions",  "Twenty five sessions logged."),
        sessionCount(50,   "Fifty sessions",        "Fifty sessions logged."),
        sessionCount(100,  "A hundred sessions",    "One hundred sessions logged."),
        sessionCount(250,  "Two fifty",             "Two hundred and fifty sessions logged."),
        sessionCount(500,  "Five hundred sessions", "Five hundred sessions logged."),
        sessionCount(1000, "A thousand sessions",   "One thousand sessions logged."),

        practicedDays(365, "A year of days",
                      "Three hundred and sixty five different days practiced."),

        Award(id: "perfectWeek", title: "Perfect week",
              blurb: "Seven days in a row, every single one.",
              group: .consistency, face: .number("7", unit: "days"),
              meaning: """
              Every day of one calendar week had a sit in it. No rest day \
              needed to bridge it, just seven days that all had time in them.
              """),

        Award(id: "multipleInADay", title: "Twice in a day",
              blurb: "Two sessions in the same day.",
              group: .consistency, face: .number("2", unit: "in a day"),
              meaning: """
              Some days ask for more than one sit. This was one of them, and \
              you took it twice.
              """),

        Award(id: "cameBack", title: "The return",
              blurb: "Back after a week or more away.",
              group: .consistency, face: .mark,
              meaning: """
              A week or longer between sits, and then another one anyway. \
              Coming back counts for just as much as never having stopped.
              """),

        Award(id: "weekendWarrior", title: "Weekend practice",
              blurb: "Both days of a weekend.",
              group: .consistency, face: .mark,
              meaning: """
              Saturday and Sunday, back to back. The weekend is the easiest \
              time to let practice slide, and this one didn't.
              """),

        Award(id: "restDayContinued", title: "Kept going",
              blurb: "Used a forgiven day off and carried the streak forward.",
              group: .consistency, face: .mark,
              meaning: """
              One day away inside a run of practice, and the streak picked \
              right back up afterward. That is exactly what the rest day is \
              there for.
              """),

        length(15, "Fifteen minutes", "A single session of 15 minutes."),
        length(45, "Forty five minutes", "A single session of 45 minutes."),
        length(90, "Ninety minutes", "A single session of 90 minutes."),

        totalHours(1,   "One hour",        "One hour of practice, all together."),
        totalHours(10,  "Ten hours",       "Ten hours of practice, all together."),
        totalHours(100, "A hundred hours", "One hundred hours of practice, all together."),

        // MARK: Time of day

        Award(id: "earlyBird", title: "Early bird",
              blurb: "A session before 8am.",
              group: .timeOfDay, face: .mark,
              meaning: """
              The day had not properly started yet, and neither had anyone \
              else.
              """),

        Award(id: "lunchBreak", title: "Lunch break",
              blurb: "A session around midday.",
              group: .timeOfDay, face: .mark,
              meaning: """
              A sit tucked into the middle of the day, instead of at either \
              end of it.
              """),

        Award(id: "eveningWindDown", title: "Evening wind down",
              blurb: "A session in the early evening.",
              group: .timeOfDay, face: .mark,
              meaning: """
              The day's work was done, and this is what came next instead of \
              more of it.
              """),

        Award(id: "nightOwl", title: "Night owl",
              blurb: "A session late at night.",
              group: .timeOfDay, face: .mark,
              meaning: """
              Late enough that most people had already stopped for the day. \
              You hadn't.
              """),

        Award(id: "allPartsOfDay", title: "Any time works",
              blurb: "A session in every part of the day.",
              group: .timeOfDay, face: .mark,
              meaning: """
              Morning, midday, evening, and late at night have each had a sit \
              in them. There is no wrong hour for this.
              """),

        // MARK: Variety

        Award(id: "soundExplorer", title: "Sound explorer",
              blurb: "Three different sounds tried.",
              group: .variety, face: .number("3", unit: "sounds"),
              meaning: """
              Three different sounds behind three different sits. The \
              measurement is the same either way; this is just about what \
              you like to sit with.
              """),

        Award(id: "techniqueVariety", title: "A few ways in",
              blurb: "Three different techniques logged.",
              group: .variety, face: .number("3", unit: "ways in"),
              meaning: """
              There is more than one way into stillness, and you've tried at \
              least three of them.
              """),

        Award(id: "guidedComplete", title: "The full journey",
              blurb: "The guided track, start to finish.",
              group: .variety, face: .mark,
              meaning: """
              The whole guided session, beginning to end, not just a few \
              minutes of it.
              """),

        Award(id: "sessionInSilence", title: "Just silence",
              blurb: "A session with no sound at all.",
              group: .variety, face: .mark,
              meaning: """
              Nothing playing, nothing guiding, just you and the quiet.
              """),

        Award(id: "sessionRated", title: "Rated a session",
              blurb: "Said how a sit felt, out of ten.",
              group: .variety, face: .mark,
              meaning: """
              Putting a number on how it felt is its own small habit, \
              separate from the sit itself.
              """),

        Award(id: "wroteANote", title: "Put it in words",
              blurb: "Wrote a note about a session.",
              group: .variety, face: .mark,
              meaning: """
              A few words about a sit, kept alongside it, for whenever you \
              want to remember what that day was like.
              """),

        Award(id: "addedPhoto", title: "A picture of it",
              blurb: "Added a photo or video to a session.",
              group: .variety, face: .mark,
              meaning: """
              A picture kept with a sit, so the log is more than just a list \
              of numbers.
              """),

        // MARK: Otto

        Award(id: "ottoSteady", title: "Otto's steady",
              blurb: "Brought his colour back.",
              group: .otto, face: .mark,
              meaning: """
              Otto starts the way everyone does, half gray. One sit was \
              enough to bring his colour back.
              """),

        Award(id: "ottoBright", title: "Otto's bright",
              blurb: "Reached Otto's brighter stage.",
              group: .otto, face: .mark,
              meaning: """
              A run of practice bright enough that it shows on him, not just \
              in your own log.
              """),

        Award(id: "ottoRadiant", title: "Otto's radiant",
              blurb: "Reached Otto's radiant stage, glowing and lifted.",
              group: .otto, face: .mark,
              meaning: """
              Otto is off the ground here, glowing, about as far along as a \
              steady run of practice takes him.
              """),

        Award(id: "ottoNirvana", title: "Otto's nirvana",
              blurb: "Reached Otto's highest stage.",
              group: .otto, face: .mark,
              meaning: """
              As bright as Otto gets. Nothing else to unlock in him after \
              this, just more days like the ones that got you here.
              """),
    ]

    private static func streak(_ days: Int, _ title: String, _ blurb: String) -> Award {
        Award(id: "streak\(days)", title: title, blurb: blurb,
              group: .consistency, face: .number("\(days)", unit: "days"),
              meaning: """
              \(days) days in a row. Across 280,000 sessions in one large study (Cearns and Clark 2023), how often \
              people practiced predicted whether they improved. How long each \
              sitting lasted did not.
              """)
    }

    /// A running total of sessions, whatever their length, source, or
    /// outcome. Reachable from a phone the same as from a Watch.
    private static func sessionCount(_ n: Int, _ title: String, _ blurb: String) -> Award {
        Award(id: "sessions\(n)", title: title, blurb: blurb,
              group: .consistency, face: .number("\(n)", unit: "sessions"),
              meaning: """
              \(n) sessions, whenever they landed and however each one went. \
              The count is the whole story: you kept sitting down.
              """)
    }

    /// Distinct calendar days with at least one session, not necessarily in
    /// a row. Different from a streak on purpose: this one survives every \
    /// gap you have ever taken.
    private static func practicedDays(_ n: Int, _ title: String, _ blurb: String) -> Award {
        Award(id: "practicedDays\(n)", title: title, blurb: blurb,
              group: .consistency, face: .number("\(n)", unit: "days"),
              meaning: """
              \(n) different days with a sit in them, in any order and with \
              any gaps between. Not a streak, just a lot of days you showed \
              up.
              """)
    }

    /// A single sitting's length, timed in the app in real time. Unlike
    /// `min20`/`min30`/`min60` above, a hand-logged session never earns
    /// these: nothing timed it, so a typed-in length would be a guess
    /// wearing the badge a real sit earns.
    private static func length(_ minutes: Int, _ title: String, _ blurb: String) -> Award {
        Award(id: "length\(minutes)", title: title, blurb: blurb,
              group: .endurance, face: .number("\(minutes)", unit: "min"),
              meaning: """
              \(minutes) minutes, sat inside 808 in one sitting.
              """)
    }

    /// Every minute you have ever sat, added together. Includes hand-logged
    /// sessions, the same way the streak and the count above do.
    private static func totalHours(_ n: Int, _ title: String, _ blurb: String) -> Award {
        Award(id: "totalHours\(n)", title: title, blurb: blurb,
              group: .endurance, face: .number("\(n)", unit: n == 1 ? "hour" : "hours"),
              meaning: """
              \(n) \(n == 1 ? "hour" : "hours") of sitting, added up minute by \
              minute across every session you have logged.
              """)
    }

    public static func award(id: String) -> Award? { all.first { $0.id == id } }

    /// The streak length each consistency award asks for, read back off the id
    /// so the catalog stays the single source of truth.
    public var streakDays: Int? {
        guard group == .consistency, id.hasPrefix("streak") else { return nil }
        return Int(id.dropFirst("streak".count))
    }
}
