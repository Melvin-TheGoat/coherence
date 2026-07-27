import Foundation
import SwiftData

/// The user's post-session reflection — a subjective 0–10 rating and an optional
/// note ("how did that feel?"). Kept separate from the immutable `Session` so the
/// biometric record stays untouched; one reflection per session, FK by `sessionID`.
///
/// CloudKit-safe: every stored property is optional or defaulted, no `.unique`,
/// no relationships.
@Model
final class SessionReflection {
    var id: UUID = UUID()
    var sessionID: UUID?
    var rating: Int?             // 0...10, nil = not rated
    var note: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        rating: Int? = nil,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.rating = rating
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
