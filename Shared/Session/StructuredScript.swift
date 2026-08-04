import Foundation

/// Step-by-step guidance for a session with **no narration** — the arc of the
/// guided meditation, delivered as timed text instead of a voice.
///
/// Why this exists: a Guided session hands you a 25-minute recording and tells
/// you what to do. Everything else — silence, a frequency, nature — leaves you
/// alone with your own eyes closed, which is exactly when a beginner wonders
/// whether they're doing it right. This gives the same structure without a
/// narrator, and without fixing the session length to a track.
///
/// **Timing is proportional, not absolute.** Cues are placed as fractions of
/// the session, so a 5-minute sit and a 20-minute sit both get the whole arc
/// rather than the short one being cut off partway through the body scan.
///
/// Pure Foundation: no SwiftUI, no SwiftData, trivially testable.
public enum StructuredScript {

    /// The five movements of the practice, in order. Named after what the user
    /// is doing, not what the app is doing.
    public enum Step: String, CaseIterable, Equatable {
        /// Arrive; let the breath settle before asking anything of it.
        case settle
        /// Bring the written intentions to mind.
        case intention
        /// Release the body part by part — the doorway to the rest.
        case bodyScan
        /// See it as already done, from inside the scene.
        case envision
        /// Wrap the images in the feeling — this is the part that sticks.
        case emotion
        /// Let go and come back.
        case release
    }

    public struct Cue: Equatable, Identifiable {
        public let id: Int
        /// Seconds from the start of the session.
        public let at: Double
        public let text: String
        public let step: Step
    }

    /// Share of the session each step occupies. Envision and body scan carry
    /// the most time because they're the parts that actually take a while;
    /// settling and releasing are short by design.
    private static let weights: [(Step, Double)] = [
        (.settle,    0.08),
        (.intention, 0.10),
        (.bodyScan,  0.24),
        (.envision,  0.28),
        (.emotion,   0.18),
        (.release,   0.12),
    ]

    /// The lines themselves. The first line of each step is the one that
    /// survives on a short session, so write it to carry the whole step alone.
    private static let lines: [Step: [String]] = [
        .settle: [
            "Close your eyes. Let the breath find its own pace.",
            "Nothing to do yet. Just arrive.",
        ],
        .intention: [
            "Bring your intentions to mind — the ones you wrote down.",
            "Hold them lightly. No need to push.",
        ],
        .bodyScan: [
            "Start at the crown of your head. Let it soften.",
            "Face, jaw, throat — let them go.",
            "Shoulders down. Arms heavy.",
            "Chest, belly, back — soften with each exhale.",
            "Hips, legs, feet. Let the whole body get heavy.",
        ],
        .envision: [
            "Now picture it done. Not coming — done.",
            "Look around from inside that moment. Where are you?",
            "Who are you in that scene? Move as that person.",
            "Say something to someone from inside it. Hear them answer.",
        ],
        .emotion: [
            "Feel it. The relief of it already being real.",
            "Let gratitude come — as if thanking someone for something already given.",
            "Stay with the feeling, not the pictures.",
        ],
        .release: [
            "Let the images go. Keep the feeling.",
            "It's planted. You don't have to hold it.",
            "Come back to the breath. Come back to the room.",
        ],
    ]

    /// No two cues closer than this. A 2-minute session would otherwise flash
    /// fourteen lines at someone whose eyes are shut.
    public static let minimumGapSec: Double = 20

    /// The cue timeline for a session of `total` seconds.
    ///
    /// Every step always contributes at least its opening line, so the arc is
    /// intact even on a very short sit; the extra lines within a step are
    /// dropped first when there isn't room.
    public static func cues(forDurationSec total: Double) -> [Cue] {
        guard total > 0 else { return [] }

        var placed: [(Double, String, Step)] = []
        var cursor = 0.0
        for (step, weight) in weights {
            let span = total * weight
            let texts = lines[step] ?? []
            guard !texts.isEmpty else { cursor += span; continue }
            // Spread the step's lines across its span, first one at the top.
            let slot = span / Double(texts.count)
            for (i, text) in texts.enumerated() {
                placed.append((cursor + slot * Double(i), text, step))
            }
            cursor += span
        }

        // Thin out anything too close to the previous cue — but never drop a
        // step's opening line, or the arc loses a movement entirely.
        var kept: [(Double, String, Step)] = []
        var seenSteps: Set<Step> = []
        for entry in placed {
            let isStepOpener = !seenSteps.contains(entry.2)
            let farEnough = kept.last.map { entry.0 - $0.0 >= minimumGapSec } ?? true
            if isStepOpener || farEnough {
                kept.append(entry)
                seenSteps.insert(entry.2)
            }
        }

        return kept.enumerated().map { Cue(id: $0.offset, at: $0.element.0,
                                           text: $0.element.1, step: $0.element.2) }
    }

    /// The cue that should be on screen at `elapsed` seconds — the most recent
    /// one that has come due. Nil before the first cue.
    public static func cue(at elapsed: Double, in cues: [Cue]) -> Cue? {
        cues.last { $0.at <= elapsed }
    }
}
