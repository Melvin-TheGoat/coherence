import Foundation

/// The beat-to-beat result read back from a finished session's
/// `HKHeartbeatSeriesSample`. Produced on the Watch; in Phase 4 it is flattened
/// into the `SessionPayload` sent to the phone.
///
/// `rrIntervals` are in **seconds** (consecutive beat-to-beat differences).
/// Intervals that span a recorded gap are dropped, so every value is a real
/// beat-to-beat interval the coherence engine can trust.
struct CapturedSeries {
    let rrIntervals: [Double]
    let healthkitUUID: String
    let beatCount: Int
}
