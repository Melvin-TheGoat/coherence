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
    /// Watch taps the 6s-in / 6s-out rhythm on the wrist during the session
    /// (the onboarding breathing practice). Optional so params from an older
    /// phone decode on a newer Watch and vice versa.
    let paceBreathing: Bool?
    /// When the phone sent this start command. The queued transferUserInfo
    /// channel flushes its whole backlog when a cold Watch launches, replaying
    /// start commands from attempts the phone gave up on long ago; the Watch
    /// only honours a command inside its freshness window. Optional for
    /// decode compatibility, and a MISSING value is treated as stale on
    /// purpose: it can only come from an old build's queue.
    let sentAt: Date?

    init(
        sessionID: UUID,
        mode: String,
        trackID: UUID? = nil,
        plannedDurationSec: Int?,
        bellyBreathing: Bool,
        hapticsEnabled: Bool,
        paceBreathing: Bool? = nil,
        sentAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.mode = mode
        self.trackID = trackID
        self.plannedDurationSec = plannedDurationSec
        self.bellyBreathing = bellyBreathing
        self.hapticsEnabled = hapticsEnabled
        self.paceBreathing = paceBreathing
        self.sentAt = sentAt
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
    /// TEMP diagnostic (belly only): the readability numbers, for calibrating the
    /// gate from the phone. Optional → backward-compatible; remove once dialed in.
    let bellyDiag: String?
    /// Apple's SDNN for this session against the user's baseline. Optional so a
    /// Watch running an older build still decodes.
    let hrv: HRVSnapshot?

    init(
        sessionID: UUID,
        startedAt: Date,
        mode: String,
        trackID: UUID? = nil,
        bellyBreathing: Bool,
        durationSec: Int,
        discard: Bool,
        result: SignalResult?,
        bellyDiag: String? = nil,
        hrv: HRVSnapshot? = nil
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.mode = mode
        self.trackID = trackID
        self.bellyBreathing = bellyBreathing
        self.durationSec = durationSec
        self.discard = discard
        self.result = result
        self.bellyDiag = bellyDiag
        self.hrv = hrv
    }
}
