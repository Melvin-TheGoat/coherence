import Foundation
import SwiftData

/// A reference to the raw `HKHeartbeatSeriesSample` recorded on the Watch during
/// a session. We store only the HealthKit UUID and beat count — never the raw
/// biometric samples (those stay in HealthKit and are never ours).
@Model
final class HeartbeatSeries {
    var id: UUID = UUID()
    var sessionID: UUID?
    var healthkitUUID: String = ""
    var beatCount: Int = 0
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        healthkitUUID: String = "",
        beatCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.healthkitUUID = healthkitUUID
        self.beatCount = beatCount
        self.createdAt = createdAt
    }
}
