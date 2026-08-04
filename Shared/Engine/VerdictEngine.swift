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
        public var meanBreathingRate: Double?   // breaths/min (belly only)
        public var resonanceMatchScore: Double? // 0–1 (belly only)
        public var bellyBreathing: Bool

        public init(overallScore: Double? = nil, stillnessScore: Double? = nil,
                    hrDecline: Double? = nil, meanBreathingRate: Double? = nil,
                    resonanceMatchScore: Double? = nil, bellyBreathing: Bool = false) {
            self.overallScore = overallScore
            self.stillnessScore = stillnessScore
            self.hrDecline = hrDecline
            self.meanBreathingRate = meanBreathingRate
            self.resonanceMatchScore = resonanceMatchScore
            self.bellyBreathing = bellyBreathing
        }
    }

    public static func verdict(for m: Inputs) -> Verdict {
        let overall = m.overallScore ?? 0

        // Collect true, concrete claims — strongest first within each signal.
        var claims: [String] = []

        if let d = m.hrDecline {
            if d >= 10 { claims.append("heart settled \(Int(d.rounded())) beats") }
            else if d >= 4 { claims.append("heart eased down \(Int(d.rounded())) beats") }
            else if d <= -5 { claims.append("heart stayed lively") }
        }
        if m.bellyBreathing, let res = m.resonanceMatchScore, let rate = m.meanBreathingRate {
            if res >= 0.6 { claims.append("breath found the resonance zone") }
            else if rate <= 8 { claims.append(String(format: "breath slowed to %.1f a minute", rate)) }
        }
        if let s = m.stillnessScore {
            if s >= 0.85 { claims.append("body went almost fully still") }
            else if s >= 0.65 { claims.append("body mostly settled") }
            else if s < 0.4 { claims.append("body stayed restless") }
        }

        let headline: String
        switch overall {
        case 0.75...:      headline = "Your practice landed."
        case 0.55..<0.75:  headline = "It landed — gently."
        case 0.35..<0.55:  headline = "A mixed one."
        default:           headline = "A restless one — that happens."
        }

        let sentence: String
        if claims.isEmpty {
            sentence = overall >= 0.55
                ? "The signals agree: you settled."
                : "The signals were faint this time. Showing up still counts — the streak holds."
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
    public static func standing(score: Double?, history: [Double]) -> String? {
        guard let score else { return nil }
        // Cold start: with almost no history, any comparison is noise dressed as
        // insight. Say nothing rather than something shaky.
        guard history.count >= minimumHistory else { return nil }

        let window = Array(history.prefix(10))
        let beaten = window.filter { score > $0 }.count

        if beaten == window.count { return "your stillest session yet" }
        if beaten == 0 { return "a quieter showing than usual" }
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
    public static func breathReading(meanRate: Double?, resonance: Double?) -> String? {
        guard let rate = meanRate else { return nil }
        if let res = resonance, res >= 0.6 { return "held near 6/min" }
        return String(format: "averaged %.1f/min", rate)
    }
}

private extension String {
    func replacingFirstLetterCapitalized() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
