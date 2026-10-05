import Foundation

/// The twenty ways Otto asks you to meditate before an app you had him hold
/// (`mockups/block-v1.html`, section 3, approved 2026-09-22). Each is one
/// screen, and every one ends in the same two doors: meditate now, or "Not
/// now" for a few minutes.
///
/// Chill but convincing: he asks, he never scolds, and he never tells anyone
/// what they lack.
enum InterventionKind: String, CaseIterable, Codable {
    case standing, textThread, faceTime, breatheWithMe, voiceNote
    case fridgeNote, stillThere, wakingOtto, sign, streak
    case glow, twoDoors, countdown, affirmation, bedtime
    case sticker, valley, friend, oneMinute, askWhy

    /// Screens taken out of the rotation. The case stays, so a recent-screens
    /// list saved on a phone still decodes, but nothing picks or shows it.
    /// `stillThere` ("It'll all still be there in five minutes") went on
    /// 2026-10-04 (Aziz: too close to the standing screen's "Are you sure?").
    static let retired: Set<InterventionKind> = [.stillThere]

    /// The screens in use: every case but the retired ones.
    static var inUse: [InterventionKind] { allCases.filter { !retired.contains($0) } }
}

extension InterventionKind {
    /// Each screen gets its own reply to "Not now", answering what it said
    /// (Aziz, 2026-10-04: "make complementary screens... telling ppl to
    /// meditate"). Under two lines in his bubble; true to the moment (the
    /// streak's number, the friend's name); never a scolding. The video call
    /// and the breath keep the plain one, which Aziz chose for them.
    func notNowReply(_ context: InterventionContext) -> String {
        switch self {
        case .standing: return "Fine... I'll allow it, but I'm disappointed."
        // The morning screen lets it go kindly.
        case .wakingOtto: return "Okay, the day is early. Make sure to meditate later today."
        case .sign: return "Fine... but the sign stays up. Meditate later today."
        case .streak:
            return "Okay... just don't let your \(context.streak)-day streak slip. Meditate later today."
        // True: a "Not now" whose window passes with no session costs glow.
        case .glow: return "Okay... that'll cost me a little glow. Meditate later today?"
        case .twoDoors: return "The scroll wins this time. Calm will be here when you're ready."
        case .countdown: return "You waited it out. Fine... how much time do you need?"
        case .affirmation: return "Okay. Choose to meditate later today, then."
        case .bedtime: return "Okay... don't scroll too late. Meditate before you sleep."
        case .sticker: return "No sticker back? Fine... meditate later today."
        case .valley: return "Okay. The valley will still be here. Come sit before the day ends."
        case .friend:
            return context.friendWhoSat.map { "Okay. There's still time to join \($0) today." }
                ?? "Okay. There's still time today."
        case .oneMinute: return "Not even five? Fine... make sure to meditate later today."
        case .askWhy: return "Fair enough. Make sure you meditate later today."
        default: return "Fine... how much time do you need?"
        }
    }

}

/// What Otto knows about the moment, so he only says what is true.
struct InterventionContext: Equatable {
    var hour: Int
    var streak: Int
    var aura: OttoAura.Stage
    /// A friend who meditated today, by first name, when Friends is on.
    var friendWhoSat: String?
    /// Whether this person has a session today. Otto's text says "you
    /// haven't meditated today" only when it is true: a Focus-hours blocker
    /// can hold apps after a morning session (2026-10-04).
    var meditatedToday = false

    var isMorning: Bool { (5..<11).contains(hour) }
    var isNight: Bool { hour >= 20 || hour < 4 }
}

enum InterventionPicker {

    /// The screens that are true right now. The morning ones only show in the
    /// morning, bedtime only at night, the streak only when there is one, his
    /// glow only when there is some left to earn, a friend only when one sat.
    static func eligible(_ context: InterventionContext) -> [InterventionKind] {
        InterventionKind.inUse.filter { kind in
            switch kind {
            case .wakingOtto, .affirmation: return context.isMorning
            case .bedtime: return context.isNight
            case .streak: return context.streak >= 2
            case .glow: return context.aura < .nirvana
            case .friend: return context.friendWhoSat != nil
            default: return true
            }
        }
    }

    /// One of them, never the last one shown, and preferring any not seen in
    /// the last five, so the same screen does not wear thin.
    static func pick<R: RandomNumberGenerator>(_ context: InterventionContext,
                                               recent: [InterventionKind],
                                               using rng: inout R) -> InterventionKind {
        let pool = eligible(context)
        let fresh = pool.filter { !recent.suffix(5).contains($0) }
        let notLast = pool.filter { $0 != recent.last }
        let choices = !fresh.isEmpty ? fresh : (!notLast.isEmpty ? notLast : pool)
        return choices.randomElement(using: &rng) ?? .standing
    }

    static func pick(_ context: InterventionContext, recent: [InterventionKind]) -> InterventionKind {
        var rng = SystemRandomNumberGenerator()
        return pick(context, recent: recent, using: &rng)
    }
}
