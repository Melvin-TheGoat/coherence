import Foundation
import SwiftData

/// The computed output of the coherence engine for one session. Immutable.
///
/// The three timeseries arrays are sampled with an overlapping sliding window:
/// `windowSec` is the FFT analysis window (long enough to resolve ~0.1 Hz);
/// `hopSec` is how far the window advances between points. The arrays are
/// therefore all the same length and share one index. Point `i`'s timestamp is
/// `session.startedAt + i*hopSec + windowSec/2` (the window center).
///
/// Both `windowSec` and `hopSec` are stored per-row so a result stays
/// interpretable if the analysis parameters ever change. `coherenceScore == nil`
/// means the session was too short to resolve the peak.
@Model
final class MeditationStats {
    var id: UUID = UUID()
    var sessionID: UUID?
    var coherenceScore: Double?              // nil = too short to measure
    var coherenceTimeseries: [Double] = []
    var hrvTimeseries: [Double] = []
    var heartRateTimeseries: [Double] = []
    var windowSec: Int = 60
    var hopSec: Int = 5
    var meanHR: Double = 0
    var rmssd: Double = 0
    var peakFrequencyHz: Double?
    var algorithmVersion: String = "1.0.0"
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        coherenceScore: Double? = nil,
        coherenceTimeseries: [Double] = [],
        hrvTimeseries: [Double] = [],
        heartRateTimeseries: [Double] = [],
        windowSec: Int = 60,
        hopSec: Int = 5,
        meanHR: Double = 0,
        rmssd: Double = 0,
        peakFrequencyHz: Double? = nil,
        algorithmVersion: String = "1.0.0",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.coherenceScore = coherenceScore
        self.coherenceTimeseries = coherenceTimeseries
        self.hrvTimeseries = hrvTimeseries
        self.heartRateTimeseries = heartRateTimeseries
        self.windowSec = windowSec
        self.hopSec = hopSec
        self.meanHR = meanHR
        self.rmssd = rmssd
        self.peakFrequencyHz = peakFrequencyHz
        self.algorithmVersion = algorithmVersion
        self.createdAt = createdAt
    }
}
