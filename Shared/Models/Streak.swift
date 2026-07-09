import Foundation
import SwiftData

/// Consecutive-day meditation streak for a user. One Streak per user, enforced
/// in code. `lastSessionDate` is stored as a local calendar day-start so the
/// day comparison is by calendar day, not by timestamp.
@Model
final class Streak {
    var id: UUID = UUID()
    var userID: UUID?
    var currentDays: Int = 0
    var longestDays: Int = 0
    var lastSessionDate: Date?           // local day-start
    var createdAt: Date = Date()         // row birth, immutable
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        currentDays: Int = 0,
        longestDays: Int = 0,
        lastSessionDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.currentDays = currentDays
        self.longestDays = longestDays
        self.lastSessionDate = lastSessionDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
