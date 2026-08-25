import Foundation

/// Rule-based, on-device "spoken verdict" for the evidence screen. No AI, no
/// network: thresholds pick true statements from the measured signals and join
/// them into one sentence. Every claim here must be backed by a number shown
/// on the same screen — the phrase bank only states what the signals show,
/// and bad sessions get honest coaching, never shame.
public enum VerdictEngine {

    public struct Verdict: Equatable {
        public let headline: String
        public let sentence: String
    }

    /// Facts the engine reads (a plain value type so it's trivially testable
    /// and never touches SwiftData).
    public struct Inputs {
        public var overallScore: Double?        // 0–1
        public var stillnessScore: Double?      // 0–1
        public var hrDecline: Double?           // positive = HR fell (bpm)
        /// Breaths/min. Populated by the belly path (historic sessions) or the
        /// wrist path (posture-free, 2026-08-07) — the engine only fills these
        /// when a breath was genuinely readable, so presence IS the license to
        /// speak about it. `bellyBreathing` no longer gates breath claims; it
        /// stays for callers that still pass it.
        public var meanBreathingRate: Double?
        public var resonanceMatchScore: Double? // 0–1
        /// The slow opening, when there was one. This is what the score is
        /// built from, so this is what the verdict speaks about.
        public var breathDoorwayRate: Double?
        public var breathDoorwayHeldSec: Double?
        public var bellyBreathing: Bool

        public init(overallScore: Double? = nil, stillnessScore: Double? = nil,
                    hrDecline: Double? = nil, meanBreathingRate: Double? = nil,
                    resonanceMatchScore: Double? = nil,
                    breathDoorwayRate: Double? = nil, breathDoorwayHeldSec: Double? = nil,
                    bellyBreathing: Bool = false) {
            self.overallScore = overallScore
            self.stillnessScore = stillnessScore
            self.hrDecline = hrDecline
            self.meanBreathingRate = meanBreathingRate
            self.resonanceMatchScore = resonanceMatchScore
            self.breathDoorwayRate = breathDoorwayRate
            self.breathDoorwayHeldSec = breathDoorwayHeldSec
            self.bellyBreathing = bellyBreathing
        }
    }

    /// - Parameter numbers: false renders the same verdict with every measured
    ///   quantity removed. This is what a free-tier user reads: the claims stay
    ///   exactly as true, they just stop being specific. Free 808 gives the
    ///   score and withholds the evidence, and a sentence saying "heart settled
    ///   11 beats" IS evidence, so it would walk straight through the lock the
    ///   graph card above it is enforcing.
    ///
    ///   Every numberless phrase here is its numbered sibling with the quantity
    ///   removed, not a softer claim. "Heart settled" and "heart settled 11
    ///   beats" report the same fact at different resolutions; a free user is
    ///   never told something a paid user would be told differently.
    public static func verdict(for m: Inputs, numbers: Bool = true) -> Verdict {
        let overall = m.overallScore ?? 0

        // Collect true, concrete claims — strongest first within each signal.
        var claims: [String] = []

        if let d = m.hrDecline {
            if d >= 10 {
                claims.append(numbers ? "heart settled \(Int(d.rounded())) beats" : "heart settled")
            } else if d >= 4 {
                claims.append(numbers ? "heart eased down \(Int(d.rounded())) beats" : "heart eased down")
            } else if d <= -5 {
                claims.append("heart stayed lively")
            }
        }
        // The doorway, never the session mean: the mean is what the score
        // stopped being built from. Silence above 8/min used to leave a score's
        // largest component unexplained, so the last branch exists to say the
        // true thing rather than nothing.
        if let rate = m.breathDoorwayRate {
            let heldLongEnough = (m.breathDoorwayHeldSec ?? 0) >= 90
            if numbers {
                let held = m.breathDoorwayHeldSec.map { " for \(Int(($0 / 60).rounded(.down)))" }
                let minutes = heldLongEnough ? (held.map { "\($0) minutes" } ?? "") : ""
                claims.append(String(format: "breath slowed to %.1f a minute%@", rate, minutes))
            } else {
                claims.append(heldLongEnough ? "breath slowed and held there" : "breath slowed")
            }
        } else if m.meanBreathingRate != nil {
            claims.append("breath stayed at its own pace")
        }
        if let s = m.stillnessScore {
            if s >= 0.85 { claims.append("body went almost fully still") }
            else if s >= 0.65 { claims.append("body mostly settled") }
            else if s < 0.4 { claims.append("body stayed restless") }
        }

        let headline = headlineFor(overall)

        let sentence: String
        if claims.isEmpty {
            sentence = overall >= 0.55
                ? "The signals agree: you settled."
                : "The signals were faint this time. Showing up still counts, and the streak holds."
        } else {
            sentence = claims.prefix(3).joined(separator: ", ")
                .replacingFirstLetterCapitalized() + "."
        }
        return Verdict(headline: headline, sentence: sentence)
    }

    // MARK: - Standing (this session vs the user's own history)

    /// How this session sits against the user's own recent practice.
    ///
    /// **Why relative and not absolute:** the Watch and the camera are different
    /// instruments measuring different things, so a cross-user number silently
    /// compares a wrist accelerometer to a phone lens. Scoring each user against
    /// themselves sidesteps that entirely — and it's the honest version of "did
    /// I get there?", which an invented probability would not be. See
    /// `STAGE2_ROADMAP.md` Phase 1 and the citation-integrity note in SCIENCE.md:
    /// nothing here may imply we measured a brain state.
    ///
    /// - Parameters:
    ///   - score: this session's overall score.
    ///   - history: previous sessions' overall scores, most recent first,
    ///     EXCLUDING this one.
    /// - Returns: a phrase like "calmer than 8 of your last 10", or nil when
    ///   there isn't enough history to say anything true.
    /// - Parameter numbers: false drops the count, for the same reason
    ///   `verdict(for:numbers:)` does. "Calmer than 8 of your last 10" is a
    ///   measurement of a run of sessions, which is exactly what the locked
    ///   home sparkline is withholding.
    public static func standing(score: Double?, history: [Double], numbers: Bool = true) -> String? {
        guard let score else { return nil }
        // Cold start: with almost no history, any comparison is noise dressed as
        // insight. Say nothing rather than something shaky.
        guard history.count >= minimumHistory else { return nil }

        let window = Array(history.prefix(10))
        let beaten = window.filter { score > $0 }.count

        if beaten == window.count { return "your stillest session yet" }
        if beaten == 0 { return "a quieter showing than usual" }
        guard numbers else {
            return beaten * 2 >= window.count
                ? "calmer than most of your recent sessions"
                : "a quieter showing than usual"
        }
        return "calmer than \(beaten) of your last \(window.count)"
    }

    /// Below this many previous sessions we make no relative claim at all.
    public static let minimumHistory = 5

    /// One-line reading for the HR curve ("74 → 63 bpm").
    public static func hrReading(start: Double?, end: Double?) -> String? {
        guard let s = start, let e = end else { return nil }
        return "\(Int(s.rounded())) → \(Int(e.rounded())) bpm"
    }

    /// One-line reading for the stillness curve: when it first crossed 0.8
    /// and stayed there ("settled by min 3"), or an honest fallback.
    public static func stillnessReading(points: [Double], hopSec: Double) -> String? {
        guard !points.isEmpty else { return nil }
        if let i = points.firstIndex(where: { $0 >= 0.8 }),
           points[i...].allSatisfy({ $0 >= 0.55 }) {
            let min = Int((Double(i) * hopSec / 60).rounded())
            return min <= 0 ? "still from the start" : "settled by min \(max(1, min))"
        }
        let avg = points.reduce(0, +) / Double(points.count)
        return avg >= 0.6 ? "mostly settled" : "restless throughout"
    }

    /// One-line reading for the breathing-rate curve.
    public static func breathReading(meanRate: Double?, doorwayRate: Double?,
                                     doorwayHeldSec: Double?) -> String? {
        if let rate = doorwayRate, let held = doorwayHeldSec {
            let s = Int(held.rounded())
            let span = s < 60 ? "\(s)s" : String(format: "%d:%02d", s / 60, s % 60)
            return String(format: "slowed to %.1f/min for %@", rate, span)
        }
        guard let rate = meanRate else { return nil }
        return String(format: "averaged %.1f/min", rate)
    }

    /// The doorway and the heart, said together when both actually happened.
    ///
    /// Slow breathing is the intervention and a settling heart is the evidence
    /// it landed, so their co-occurrence is worth naming. Deliberately
    /// DESCRIPTIVE: 808 reads motion and an averaged heart rate, not vagal
    /// tone, so this reports what was seen and lets the meaning follow.
    ///
    /// **Its absence means nothing.** People reach the same state without ever
    /// slowing their breath, so this line appears when the pattern is seen and
    /// is never negated when it isn't.
    private static func headlineFor(_ overall: Double) -> String {
        switch overall {
        case 0.75...:      return "Your practice landed."
        case 0.55..<0.75:  return "It landed, gently."
        case 0.35..<0.55:  return "A mixed one."
        default:           return "A restless one. That happens."
        }
    }

}

private extension String {
    func replacingFirstLetterCapitalized() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
