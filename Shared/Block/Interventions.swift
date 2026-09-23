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
}

/// What Otto knows about the moment, so he only says what is true.
struct InterventionContext: Equatable {
    var hour: Int
    var streak: Int
    var aura: OttoAura.Stage
    /// A friend who meditated today, by first name, when Friends is on.
    var friendWhoSat: String?

    var isMorning: Bool { (5..<11).contains(hour) }
    var isNight: Bool { hour >= 20 || hour < 4 }
}

enum InterventionPicker {

    /// The screens that are true right now. The morning ones only show in the
    /// morning, bedtime only at night, the streak only when there is one, his
    /// glow only when there is some left to earn, a friend only when one sat.
    static func eligible(_ context: InterventionContext) -> [InterventionKind] {
        InterventionKind.allCases.filter { kind in
            switch kind {
            case .wakingOtto, .affirmation: return context.isMorning
            case .bedtime: return context.isNight
            case .streak: return context.streak >= 2
            case .glow: return context.aura < .enlightened
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
