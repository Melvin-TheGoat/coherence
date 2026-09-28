import Foundation

/// Flattens the raw SwiftData rows into `AwardEngine.SessionFact`s, in ONE
/// place, so Home and Profile can never compute the shelf two different ways.
///
/// `AwardEngine` stays storage-agnostic on purpose (it never imports
/// SwiftData); this is the seam where `Session` / `MeditationStats` /
/// `SessionReflection` / `SessionPhoto` meet it.
enum AwardFacts {
    static func build(sessions: [Session],
                       stats: [MeditationStats],
                       reflections: [SessionReflection],
                       photos: [SessionPhoto]) -> [AwardEngine.SessionFact] {
        let scores = Dictionary(stats.compactMap { st -> (UUID, Double)? in
            guard let id = st.sessionID, let score = st.overallScore else { return nil }
            return (id, score)
        }, uniquingKeysWith: { a, _ in a })

        let reflectionBySession = Dictionary(reflections.compactMap { r -> (UUID, SessionReflection)? in
            guard let id = r.sessionID else { return nil }
            return (id, r)
        }, uniquingKeysWith: { a, _ in a })

        let photoSessionIDs = Set(photos.compactMap(\.sessionID))

        return sessions.map { session in
            let reflection = reflectionBySession[session.id]
            let note = reflection?.note.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let publicNote = reflection?.publicNote.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return AwardEngine.SessionFact(
                startedAt: session.startedAt,
                durationSec: session.durationSec,
                overallScore: scores[session.id],
                isLogged: session.isLogged,
                mode: session.mode,
                soundID: session.frequencyID,
                technique: reflection?.technique,
                rating: reflection?.rating,
                hasNote: !note.isEmpty || !publicNote.isEmpty,
                hasPhoto: photoSessionIDs.contains(session.id))
        }
    }
}
