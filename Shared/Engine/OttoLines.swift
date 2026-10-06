import Foundation

/// What Otto says about today, by rules, never generated. Home's bubble and
/// the home screen widget both read these, so the two can never disagree
/// about the same day (2026-10-05, the widget).
///
/// Home adds its own lines around these (a session that just landed, apps
/// being held, the Apple Watch, the famous sayings); the widget says only the
/// one that matters today (`widget`).
enum OttoLines {
    /// His mood, when it is the news: a sad Otto who says nothing about it
    /// reads as a bug, and a glowing one has earned a word.
    static func mood(_ stage: OttoAura.Stage, practicedToday: Bool) -> String? {
        switch stage {
        case .withered where !practicedToday:
            return "I've been feeling a bit flat. One session today and I'll perk right up."
        case .faded where !practicedToday:
            return "It's been a few days. One short session and I'll be back on my feet."
        case .bright, .radiant:
            return "Feel that? You keep showing up, and it shows on me."
        case .nirvana:
            return "I'm glowing. That's what showing up day after day does."
        default:
            return nil
        }
    }

    /// Where today stands: not started, done, a rest day, or a run going.
    /// The first line is the one that matters; Home cycles the rest.
    static func today(hasSessions: Bool,
                      practicedToday: Bool,
                      streak: (current: Int, longest: Int, restDayUsed: Bool)) -> [String] {
        guard hasSessions else {
            return ["Your first session starts at the plus. I'll be right here."]
        }
        if practicedToday {
            return [streak.current > 1 ? "Day \(streak.current). You already sat today, so today is done."
                                       : "You meditated today. That's the part that counts.",
                    "Nothing more to do here. Come back tomorrow and we'll keep it going."]
        }
        if streak.restDayUsed {
            return ["Rest day yesterday. Sit today and your \(streak.current)-day streak carries on."]
        }
        if streak.current > 1 {
            var lines = ["Day \(streak.current). Sit whenever you're ready, I'll be here."]
            if streak.current == streak.longest, streak.current >= 3 {
                lines.append("\(streak.current) in a row is your longest yet. No rush today either.")
            }
            return lines
        }
        return ["Whenever you're ready. One session is all today asks."]
    }

    /// The one line the widget shows. A sad Otto says so, because his face
    /// already does; otherwise it is where today stands, which is the thing
    /// somebody glancing at a home screen can act on.
    static func widget(stage: OttoAura.Stage,
                       hasSessions: Bool,
                       practicedToday: Bool,
                       streak: (current: Int, longest: Int, restDayUsed: Bool)) -> String {
        if stage <= .faded, let sad = mood(stage, practicedToday: practicedToday) { return sad }
        return today(hasSessions: hasSessions, practicedToday: practicedToday, streak: streak)[0]
    }
}
