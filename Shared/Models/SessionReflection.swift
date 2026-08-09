import Foundation
import SwiftData

/// The user's post-session reflection — a subjective 0–10 rating, an optional
/// note ("how did that feel?"), and which method they practised. Kept separate
/// from the immutable `Session` so the biometric record stays untouched; one
/// reflection per session, FK by `sessionID`.
///
/// `technique` lives here rather than on `Session` for the same reason the
/// rating does: it's self-reported after the fact, and it's editable. It's also
/// the field that makes "which method actually settles you" answerable — see
/// METHODS.md on why that comparison is only defensible WITHIN one user.
///
/// CloudKit-safe: every stored property is optional or defaulted, no `.unique`,
/// no relationships.
@Model
final class SessionReflection {
    var id: UUID = UUID()
    var sessionID: UUID?
    var rating: Int?             // 0...10, nil = not rated
    var note: String = ""
    /// A `MeditationMethod` id, `MeditationMethod.ownID`, or nil = unreported.
    /// Never forced: an unlabelled session is a perfectly good session.
    var technique: String?
    /// Free text, only when `technique == MeditationMethod.ownID`.
    var techniqueNote: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        rating: Int? = nil,
        note: String = "",
        technique: String? = nil,
        techniqueNote: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.rating = rating
        self.note = note
        self.technique = technique
        self.techniqueNote = techniqueNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
