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
public struct Award: Identifiable, Hashable {

    public enum Group: String, CaseIterable {
        case beginning, consistency, depth, endurance

        public var title: String {
            switch self {
            case .beginning:   return "Beginning"
            case .consistency: return "Consistency"
            case .depth:       return "Depth"
            case .endurance:   return "Endurance"
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
              blurb: "Your first measured session.",
              group: .beginning, face: .number("1", unit: "session"),
              meaning: """
              You sat, and your Watch recorded what your body did while you were \
              there. Everything else on this shelf is built on top of this.
              """),

        streak(3,   "Three days",   "Three in a row."),
        streak(5,   "Five days",    "Five in a row."),
        streak(10,  "Ten days",     "Ten in a row."),
        streak(25,  "Twenty five",  "Twenty five in a row."),
        streak(50,  "Fifty",        "Fifty in a row."),
        streak(100, "One hundred",  "One hundred in a row."),
        streak(200, "Two hundred",  "Two hundred in a row."),
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
              blurb: "A single sit of 20 minutes.",
              group: .endurance, face: .number("20", unit: "min"),
              meaning: """
              Twenty minutes is where the score's time factor stops climbing, \
              and it is the length most traditions land on independently.
              """),

        Award(id: "min30", title: "Half an hour",
              blurb: "A single sit of 30 minutes.",
              group: .endurance, face: .number("30", unit: "min"),
              meaning: """
              Past the point where sitting still is the hard part.
              """),

        Award(id: "min60", title: "One hour",
              blurb: "A single sit of 60 minutes.",
              group: .endurance, face: .number("60", unit: "min"),
              meaning: """
              An hour on the cushion. There is no research saying an hour beats \
              twenty minutes, so take this one as endurance rather than depth.
              """),
    ]

    private static func streak(_ days: Int, _ title: String, _ blurb: String) -> Award {
        Award(id: "streak\(days)", title: title, blurb: blurb,
              group: .consistency, face: .number("\(days)", unit: "days"),
              meaning: """
              \(days) days in a row. Across 280,000 sessions in one large study (Cearns and Clark 2023), how often \
              people practised predicted whether they improved. How long each \
              sitting lasted did not.

              Yours to keep. If the streak breaks, this award stays.
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
