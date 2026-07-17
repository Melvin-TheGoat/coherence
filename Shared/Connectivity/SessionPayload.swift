import Foundation

/// The WatchConnectivity transfer contract for the session pipeline. Both types
/// are `Codable` and shipped as a single JSON blob over `WCSession` so the schema
/// stays in one place.

/// Phone → Watch. Parameters that start a session on the wrist. Sent when the user
/// taps "Begin" on the phone (alongside `HKHealthStore.startWatchApp`).
struct SessionParams: Codable, Equatable {
    let sessionID: UUID
    let mode: String                 // SessionMode rawValue
    let trackID: UUID?               // nil = silence
    let plannedDurationSec: Int?     // nil = open-ended
    let bellyBreathing: Bool
    let hapticsEnabled: Bool

    init(
        sessionID: UUID,
        mode: String,
        trackID: UUID? = nil,
        plannedDurationSec: Int?,
        bellyBreathing: Bool,
        hapticsEnabled: Bool
    ) {
        self.sessionID = sessionID
        self.mode = mode
        self.trackID = trackID
        self.plannedDurationSec = plannedDurationSec
        self.bellyBreathing = bellyBreathing
        self.hapticsEnabled = hapticsEnabled
    }
}

/// Watch → Phone. The finished session plus its computed `SignalResult`, ready for
/// the phone to persist. `discard == true` (or `result == nil`) means the session
/// was too short / unusable and nothing should be written.
struct SessionPayload: Codable, Equatable {
    let sessionID: UUID
    let startedAt: Date
    let mode: String
    let trackID: UUID?
    let bellyBreathing: Bool
    let durationSec: Int
    let discard: Bool
    let result: SignalResult?

    init(
        sessionID: UUID,
        startedAt: Date,
        mode: String,
        trackID: UUID? = nil,
        bellyBreathing: Bool,
        durationSec: Int,
        discard: Bool,
        result: SignalResult?
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.mode = mode
        self.trackID = trackID
        self.bellyBreathing = bellyBreathing
        self.durationSec = durationSec
        self.discard = discard
        self.result = result
    }
}
