import Foundation

/// One message from the Garmin watch, decoded and put into SI units.
///
/// The watch sends a dictionary every four seconds (see
/// `GarminWatch/source/Capture.mc`). Everything on the wire is an integer,
/// because a Connect IQ `Number` is a 32-bit int whatever we put in it, so the
/// finer unit is free: microradians for tilt, micro-g for movement,
/// milliseconds for time.
///
/// The transport hands us `[AnyHashable: Any]` out of a BLE payload we do not
/// control the far end of during development, so every field is validated and
/// a malformed message decodes to nil rather than throwing. A dropped batch is
/// a gap the engine already tolerates; a crash is not.
struct GarminBatch: Equatable {

    /// One reduced sample: where the wrist pointed, and what the body did.
    struct Sample: Equatable {
        let pitch: Double     // radians
        let roll: Double      // radians
        let userAccel: Double // g, the RMS of the residual over the bin
    }

    /// Seconds since the watch began the sit, at the moment the batch was
    /// SENT. Garmin calls us back after collecting a whole period, so this
    /// stamps the END of the window and the samples run backwards from it.
    let sentAt: TimeInterval
    let hz: Double
    let samples: [Sample]
    /// One heart rate per batch (the watch reads it at 1 Hz and stamps the
    /// batch with the latest). Nil when the sensor has not answered yet.
    let bpm: Double?
    /// Beat-to-beat intervals, which Garmin gives and the Apple Watch never
    /// has. Collected from the first build; deliberately not scored, so that a
    /// Garmin sit and a Watch sit stay comparable.
    let beatIntervalsMs: [Int]

    private static let micro = 1_000_000.0

    init?(message: [AnyHashable: Any]) {
        guard let version = message["v"] as? Int, version == 1 else { return nil }
        guard let millis = message["t"] as? Int, millis >= 0 else { return nil }

        // An end marker carries no samples and is not a batch.
        guard let flat = message["s"] as? [Int], !flat.isEmpty else { return nil }
        guard flat.count % 3 == 0 else { return nil }

        let rate = (message["hz"] as? Int).map(Double.init) ?? 5.0
        guard rate > 0, rate <= 100 else { return nil }

        sentAt = Double(millis) / 1000.0
        hz = rate
        samples = stride(from: 0, to: flat.count, by: 3).map { i in
            Sample(pitch: Double(flat[i]) / Self.micro,
                   roll: Double(flat[i + 1]) / Self.micro,
                   userAccel: Double(flat[i + 2]) / Self.micro)
        }

        // A watch that has not got a heart reading yet sends 0, which is not a
        // heart rate. The engine reads an empty HR series as "no heart data"
        // and degrades honestly, which is far better than a zero in the curve.
        if let raw = message["hr"] as? Int, raw > 20, raw < 250 {
            bpm = Double(raw)
        } else {
            bpm = nil
        }

        beatIntervalsMs = (message["rr"] as? [Int])?.filter { $0 > 200 && $0 < 3000 } ?? []
    }

    /// Time of sample `index`, in seconds from the start of the sit. The batch
    /// is stamped when it was sent, so the LAST sample sits at `sentAt` and the
    /// rest run backwards at the sample rate. Deriving each batch's times from
    /// its own stamp means a dropped batch leaves a gap rather than shifting
    /// everything after it.
    func time(of index: Int) -> TimeInterval {
        sentAt - Double(samples.count - 1 - index) / hz
    }

    /// True when the message is the watch saying the sit is over.
    static func isEnd(_ message: [AnyHashable: Any]) -> Bool {
        (message["v"] as? Int) == 1 && message["end"] != nil
    }
}
