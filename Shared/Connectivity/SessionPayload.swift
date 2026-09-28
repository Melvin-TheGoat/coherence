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
        sentAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.mode = mode
        self.trackID = trackID
        self.plannedDurationSec = plannedDurationSec
        self.bellyBreathing = bellyBreathing
        self.hapticsEnabled = hapticsEnabled
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

/// How a `SessionPayload` travels over WatchConnectivity.
///
/// The JSON grows about 1 KB per minute of session (three curves on a 5 s
/// hop), and `sendMessage` refuses anything over roughly 64 KB, so past an
/// hour the immediate channel failed and the finished session waited in the
/// queued `transferUserInfo` channel instead: "End on the Watch does nothing"
/// again, for exactly the longest, most committed sessions. LZFSE shrinks the
/// JSON. Compression alone only halves it, because the bulk is seventeen-digit
/// decimals, so the CURVES (never the summary numbers the score is made of) are
/// first rounded to six significant digits: a heart rate to 0.0001 bpm, far
/// below anything the sensor resolves. Measured: a four-hour session then
/// travels in about 53 KB. A four-byte tag marks the compressed form; plain
/// JSON (which always opens with `{`) still decodes, so a phone can read a
/// payload from a Watch on an older build and the other way round.
enum PayloadCoding {
    static let tag = Data("808Z".utf8)
    /// What `sendMessage` will accept, with headroom for the dictionary around it.
    static let messageLimit = 60_000

    /// `x` to `digits` significant digits; zero and non-finite values untouched.
    static func significant(_ x: Double, _ digits: Int = 6) -> Double {
        guard x.isFinite, x != 0 else { return x }
        let scale = pow(10, Double(digits) - ceil(log10(abs(x))))
        return (x * scale).rounded() / scale
    }

    /// The payload as it travels: every curve rounded, every summary exact.
    static func forTransport(_ payload: SessionPayload) -> SessionPayload {
        guard var r = payload.result else { return payload }
        let round: ([Double]) -> [Double] = { $0.map { significant($0) } }
        r.heartRateTimeseries = round(r.heartRateTimeseries)
        r.stillnessTimeseries = round(r.stillnessTimeseries)
        r.breathingRateTimeseries = round(r.breathingRateTimeseries)
        r.breathDepthTimeseries = round(r.breathDepthTimeseries)
        r.breathClarityTimeseries = round(r.breathClarityTimeseries)
        return SessionPayload(sessionID: payload.sessionID, startedAt: payload.startedAt,
                              mode: payload.mode, trackID: payload.trackID,
                              bellyBreathing: payload.bellyBreathing,
                              durationSec: payload.durationSec, discard: payload.discard,
                              result: r, bellyDiag: payload.bellyDiag, hrv: payload.hrv)
    }

    static func encode(_ payload: SessionPayload) throws -> Data {
        let json = try JSONEncoder().encode(forTransport(payload))
        guard let packed = try? (json as NSData).compressed(using: .lzfse) as Data,
              packed.count + tag.count < json.count else { return json }
        return tag + packed
    }

    static func decode(_ data: Data) -> SessionPayload? {
        var json = data
        if data.starts(with: tag) {
            let body = data.dropFirst(tag.count)
            guard let unpacked = try? (Data(body) as NSData).decompressed(using: .lzfse) as Data
            else { return nil }
            json = unpacked
        }
        return try? JSONDecoder().decode(SessionPayload.self, from: json)
    }
}
