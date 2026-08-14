import Foundation
import SwiftData

/// The computed output of the signal engine for one session. Immutable.
///
/// Three resampled timeseries (heartRate, stillness, breathingRate) share one
/// overlapping sliding window: `windowSec` is the analysis window, `hopSec` how
/// far it advances between points. They are the same length and share one index;
/// point `i`'s timestamp is `session.startedAt + i*hopSec + windowSec/2` (window
/// center). Both are stored per-row so a result stays interpretable if the
/// analysis parameters change.
///
/// Breathing fields are populated only for belly-breathing sessions with a
/// readable breathing signal; otherwise they stay empty/nil and the session is a
/// 2-signal (stillness + HR) result. `stillnessMethod` records how stillness was
/// scored: `"total"` (regular) or `"breathingExcluded"` (belly).
@Model
final class MeditationStats {
    var id: UUID = UUID()
    var sessionID: UUID?

    // Heart rate (always)
    var heartRateTimeseries: [Double] = []
    var meanHR: Double = 0
    var startHR: Double?
    var endHR: Double?
    var hrDecline: Double?               // startHR - endHR; positive = slowed

    // Stillness (always)
    var stillnessTimeseries: [Double] = []
    var stillnessScore: Double?
    var stillnessMethod: String = "total"    // "total" | "breathingExcluded"

    // Belly breathing (only when opted in AND the signal was readable)
    var breathingRateTimeseries: [Double] = []
    var breathDepthTimeseries: [Double] = []
    var meanBreathingRate: Double?
    var breathingRegularity: Double?
    var resonanceMatchScore: Double?

    // The doorway: the slow opening the score is built from. All optional, so
    // CloudKit lightweight migration applies and old rows read back as nil.
    var breathDoorwayRate: Double?
    var breathDoorwayHeldSec: Double?
    /// Seconds from session start to the beginning of the doorway. The results
    /// graph highlights exactly this stretch.
    var breathDoorwayStartSec: Double?
    /// Per-window path clarity, same index as `breathingRateTimeseries`.
    /// Stored because the score now needs it: without it no migration can
    /// recompute a score from this row alone.
    var breathClarityTimeseries: [Double] = []

    // HRV (SDNN), read from HealthKit — Apple computes it, we don't.
    //
    // NOT heart coherence, and not the RMSSD the camera path produced. Values
    // are milliseconds. Empty/nil is a normal outcome: the Watch generates
    // these opportunistically, so a short session may produce none. The
    // baseline is the user's own mean over the preceding 30 days, which is
    // what makes a single sample worth anything.
    var hrvSDNNSamples: [Double] = []
    var hrvMeanSDNN: Double?
    var hrvBaselineSDNN: Double?
    var hrvBaselineSampleCount: Int = 0

    // Combined "practice landed" summary
    var overallScore: Double?

    // Optional camera-coherence snapshots (finger-on-camera PPG, ~45 s each,
    // taken before/after the session when the user opts in — Phase 9). The
    // post fields are attached once, right after the session ends; both stay
    // nil when the user skipped or a read failed. Device-local like the rest
    // of this row.
    var preCoherenceScore: Double?
    var preCoherenceHR: Double?
    var preCoherenceRMSSD: Double?
    var postCoherenceScore: Double?
    var postCoherenceHR: Double?
    var postCoherenceRMSSD: Double?

    /// Which instrument produced this row's signals — `"watch"` (accelerometer
    /// + averaged HR) or `"camera"` (finger PPG). Recorded because the two are
    /// NOT comparable: a wrist accelerometer and a phone lens measure different
    /// things at different fidelities, so a score only means something next to
    /// the instrument that produced it. Defaulted for every pre-existing row,
    /// which was necessarily the Watch.
    var measurementSource: String = "watch"

    var windowSec: Int = 30
    var hopSec: Int = 5
    var algorithmVersion: String = "2.0.0"
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        heartRateTimeseries: [Double] = [],
        meanHR: Double = 0,
        startHR: Double? = nil,
        endHR: Double? = nil,
        hrDecline: Double? = nil,
        stillnessTimeseries: [Double] = [],
        stillnessScore: Double? = nil,
        stillnessMethod: String = "total",
        breathingRateTimeseries: [Double] = [],
        breathDepthTimeseries: [Double] = [],
        meanBreathingRate: Double? = nil,
        breathingRegularity: Double? = nil,
        resonanceMatchScore: Double? = nil,
        breathDoorwayRate: Double? = nil,
        breathDoorwayHeldSec: Double? = nil,
        breathDoorwayStartSec: Double? = nil,
        breathClarityTimeseries: [Double] = [],
        hrvSDNNSamples: [Double] = [],
        hrvMeanSDNN: Double? = nil,
        hrvBaselineSDNN: Double? = nil,
        hrvBaselineSampleCount: Int = 0,
        overallScore: Double? = nil,
        measurementSource: String = "watch",
        windowSec: Int = 30,
        hopSec: Int = 5,
        algorithmVersion: String = "2.0.0",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.heartRateTimeseries = heartRateTimeseries
        self.meanHR = meanHR
        self.startHR = startHR
        self.endHR = endHR
        self.hrDecline = hrDecline
        self.stillnessTimeseries = stillnessTimeseries
        self.stillnessScore = stillnessScore
        self.stillnessMethod = stillnessMethod
        self.breathingRateTimeseries = breathingRateTimeseries
        self.breathDepthTimeseries = breathDepthTimeseries
        self.meanBreathingRate = meanBreathingRate
        self.breathingRegularity = breathingRegularity
        self.resonanceMatchScore = resonanceMatchScore
        self.breathDoorwayRate = breathDoorwayRate
        self.breathDoorwayHeldSec = breathDoorwayHeldSec
        self.breathDoorwayStartSec = breathDoorwayStartSec
        self.breathClarityTimeseries = breathClarityTimeseries
        self.hrvSDNNSamples = hrvSDNNSamples
        self.hrvMeanSDNN = hrvMeanSDNN
        self.hrvBaselineSDNN = hrvBaselineSDNN
        self.hrvBaselineSampleCount = hrvBaselineSampleCount
        self.overallScore = overallScore
        self.measurementSource = measurementSource
        self.windowSec = windowSec
        self.hopSec = hopSec
        self.algorithmVersion = algorithmVersion
        self.createdAt = createdAt
    }
}
