import Foundation
import SwiftData

/// One completed meditation. Immutable once written (no `updatedAt`).
/// `trackID == nil` means silence. FKs are plain UUIDs.
@Model
final class Session {
    var id: UUID = UUID()
    var userID: UUID?
    var trackID: UUID?                // nil = silence
    var mode: String = "silence"
    var startedAt: Date = Date()
    var durationSec: Int = 0
    var createdAt: Date = Date()
    // NO updatedAt — sessions are immutable.

    /// Computed accessor over the String-backed `mode`.
    var modeValue: SessionMode {
        get { SessionMode(rawValue: mode) ?? .silence }
        set { mode = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        trackID: UUID? = nil,
        mode: String = "silence",
        startedAt: Date = Date(),
        durationSec: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.trackID = trackID
        self.mode = mode
        self.startedAt = startedAt
        self.durationSec = durationSec
        self.createdAt = createdAt
    }
}
