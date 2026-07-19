import Foundation
import SwiftData

/// Seeds the built-in meditation tracks on first launch — one per type (guided /
/// frequency / nature). **Silence is a mode, never a track**, so it is not seeded.
///
/// Idempotent: seeds only when the store has no tracks yet. Pure SwiftData over a
/// passed-in `ModelContext`, so it's testable headlessly (the iOS app calls
/// `seedIfNeeded` once at launch).
///
/// `audioURL` holds a bundled filename; the actual audio assets live in
/// `Coherence/Audio/` (added with the Phase-5 playback work). Seeding the rows is
/// independent of the files existing.
enum TrackSeeder {

    /// One track per type, inserted only if the store is currently empty.
    static func seedIfNeeded(in context: ModelContext) {
        let count = (try? context.fetch(FetchDescriptor<MeditationTrack>()))?.count ?? 0
        guard count == 0 else { return }

        let defaults: [MeditationTrack] = [
            MeditationTrack(
                type: TrackType.guided.rawValue,
                title: "Grounding Body Scan",
                trackDescription: "A gentle guided settling into the body.",
                audioURL: "guided_grounding.m4a",
                durationSec: 600,               // guided tracks carry their own length
                sortOrder: 0
            ),
            MeditationTrack(
                type: TrackType.frequency.rawValue,
                title: "432 Hz Calm",
                trackDescription: "A steady resonant tone.",
                audioURL: "frequency_432.m4a",
                durationSec: nil,               // duration chosen at setup
                sortOrder: 0
            ),
            MeditationTrack(
                type: TrackType.nature.rawValue,
                title: "Rainfall",
                trackDescription: "Soft, continuous rain.",
                audioURL: "nature_rain.m4a",
                durationSec: nil,
                sortOrder: 0
            ),
        ]
        for track in defaults { context.insert(track) }
        try? context.save()
    }

    /// Active tracks of a type, ordered by `sortOrder` — the query the Phase-5
    /// Frequency/Nature track lists use.
    static func tracks(ofType type: TrackType, in context: ModelContext) -> [MeditationTrack] {
        let raw = type.rawValue
        let descriptor = FetchDescriptor<MeditationTrack>(
            predicate: #Predicate { $0.type == raw && $0.isActive },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
