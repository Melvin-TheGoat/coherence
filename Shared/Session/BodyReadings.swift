import Foundation

/// What a Watch-measured session's "Your body" card says (Aziz, 2026-09-28,
/// `mockups/apple-watch/`): the score, then heart rate, stillness and
/// breathing in plain words. Pure, so the words are tested.
///
/// Readings only report; a restless session is described, never scolded.
/// Breathing appears only when it was read: silence means nothing (see the
/// breathing notes in CLAUDE.md).
struct BodyReadings: Equatable {
    struct Reading: Equatable {
        let label: String
        let value: String
        let note: String
    }

    let score: Int?
    let readings: [Reading]

    init(score: Double?, startHR: Double?, endHR: Double?, stillness: Double?,
         doorwayRate: Double?, doorwayHeldSec: Double?, meanBreathingRate: Double?) {
        self.score = score.map { Int(($0 * 100).rounded()) }
        var out: [Reading] = []

        if let start = startHR, let end = endHR, start > 0, end > 0 {
            let s = Int(start.rounded()), e = Int(end.rounded())
            let drop = s - e
            // Said plainly either way: "Held steady" only when it barely
            // moved, so a heart that rose is never called steady.
            let note: String
            if drop >= 2 { note = "Settled \(drop) beats" }
            else if drop <= -2 { note = "Rose \(-drop) beats" }
            else { note = "Held steady" }
            out.append(Reading(label: "Heart rate", value: "\(s) → \(e) bpm", note: note))
        }

        if let still = stillness {
            let word: String
            switch still {
            case 0.9...: word = "Very still"
            case 0.75..<0.9: word = "Still"
            case 0.5..<0.75: word = "Some movement"
            default: word = "Moved a lot"
            }
            out.append(Reading(label: "Stillness", value: word,
                               note: "\(Int((still * 100).rounded()))% still"))
        }

        if let rate = doorwayRate {
            let minutes = max(1, Int(((doorwayHeldSec ?? 60) / 60).rounded()))
            out.append(Reading(label: "Breathing", value: Self.rate(rate),
                               note: "Slow for \(minutes) \(minutes == 1 ? "minute" : "minutes")"))
        } else if let mean = meanBreathingRate, mean > 0 {
            out.append(Reading(label: "Breathing", value: Self.rate(mean), note: "Across the session"))
        }
        readings = out
    }

    /// "5.8 a minute".
    static func rate(_ r: Double) -> String {
        String(format: "%.1f a minute", r)
    }
}
