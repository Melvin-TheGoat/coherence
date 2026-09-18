import Foundation

/// Batches from a Garmin watch, accumulated into exactly what the Apple Watch
/// hands the phone at the end of a sit.
///
/// **This is the join.** On Apple the watch runs `SignalEngine` and ships a
/// finished `SignalResult`; a Garmin watch has 28.5 KB and cannot, so the
/// phone runs the identical engine over samples the watch reduced. The output
/// is the same `SessionPayload`, so everything downstream (persistence, the
/// score, the doorway, the verdict, history) is untouched and a Garmin sit is
/// comparable with every Watch sit in the same log. That comparability is the
/// reason the reduction happens on the watch at all.
///
/// Nothing here is Garmin-specific beyond decoding: it is a buffer and one
/// call to `SignalEngine.analyze`.
final class GarminStream {

    let sessionID: UUID
    let startedAt: Date
    let mode: String
    let trackID: UUID?

    private(set) var motion: [MotionSample] = []
    private(set) var hr: [HRSample] = []
    private(set) var beatIntervalsMs: [Int] = []
    private(set) var batchCount = 0
    /// Batches whose stamp jumped further than the sample rate explains, i.e.
    /// the watch dropped one because the phone was out of range. Counted for
    /// diagnostics only: the engine skips short windows on its own.
    private(set) var gaps = 0

    private var lastSentAt: TimeInterval?

    init(sessionID: UUID, startedAt: Date, mode: String, trackID: UUID? = nil) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.mode = mode
        self.trackID = trackID
    }

    func accept(_ batch: GarminBatch) {
        // A batch that arrives out of order or repeats is dropped rather than
        // interleaved: WatchConnectivity taught this codebase three times that
        // every arrival may be stale, and BLE is no better behaved.
        if let last = lastSentAt, batch.sentAt <= last { return }
        if let last = lastSentAt {
            let span = Double(batch.samples.count) / batch.hz
            if batch.sentAt - last > span * 1.5 { gaps += 1 }
        }
        lastSentAt = batch.sentAt

        for (i, s) in batch.samples.enumerated() {
            let t = batch.time(of: i)
            guard t >= 0 else { continue }
            motion.append(MotionSample(t: t, pitch: s.pitch, roll: s.roll, userAccel: s.userAccel))
        }
        if let bpm = batch.bpm {
            hr.append(HRSample(t: batch.sentAt, bpm: bpm))
        }
        beatIntervalsMs.append(contentsOf: batch.beatIntervalsMs)
        batchCount += 1
    }

    /// The finished sit, in the shape the Watch would have sent.
    ///
    /// `bellyBreathing` is false always: the Garmin path is the posture-free
    /// wrist path, exactly as every Apple Watch session has been since the
    /// belly mode was cut.
    func payload(endedAt: Date, minDurationSec: Int = 30) -> SessionPayload {
        let wallClock = endedAt.timeIntervalSince(startedAt)
        let measured = motion.last?.t ?? 0
        let duration = Int(max(wallClock, measured).rounded())

        // Too short, or so little arrived that there is nothing to read. The
        // second case is a Garmin-only failure the Watch cannot have: the
        // phone may have been out of range for most of the sit.
        let usable = duration >= minDurationSec && measured >= Double(minDurationSec)
        guard usable else {
            return SessionPayload(
                sessionID: sessionID, startedAt: startedAt, mode: mode, trackID: trackID,
                bellyBreathing: false, durationSec: duration, discard: true, result: nil
            )
        }

        let result = SignalEngine.analyze(motion: motion, hr: hr, bellyBreathing: false)
        return SessionPayload(
            sessionID: sessionID, startedAt: startedAt, mode: mode, trackID: trackID,
            bellyBreathing: false, durationSec: duration, discard: false, result: result
        )
    }
}
