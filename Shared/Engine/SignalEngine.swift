import Foundation

// MARK: - Engine input types
//
// Plain value types that form the engine's contract. They live here (not in the
// Watch's MotionRecorder) so the pure-Swift engine, both apps, and the test target
// share ONE definition.
//
// NOTE (deviation from the Phase-3 spec): the spec listed a `gravity` field on
// MotionSample, but the Watch's CoreMotion capture never records it and the
// analysis never uses it, so the shipped struct is {t, pitch, roll, userAccel} —
// matching what `MotionRecorder` actually produces. Adding an unused field would
// be dead weight and force a change to verified Phase-2 capture code.

/// One CoreMotion device-motion sample, timestamped from the start of recording.
/// `pitch`/`roll` are attitude angles (radians); `userAccel` is the magnitude of
/// user acceleration (g), gravity removed by CoreMotion's sensor fusion.
struct MotionSample {
    let t: TimeInterval
    let pitch: Double
    let roll: Double
    let userAccel: Double

    init(t: TimeInterval, pitch: Double, roll: Double, userAccel: Double) {
        self.t = t
        self.pitch = pitch
        self.roll = roll
        self.userAccel = userAccel
    }
}

/// One averaged heart-rate sample (BPM) from `HKLiveWorkoutBuilder`, timestamped
/// from the start of the session.
struct HRSample {
    let t: TimeInterval
    let bpm: Double

    init(t: TimeInterval, bpm: Double) {
        self.t = t
        self.bpm = bpm
    }
}

// MARK: - Engine output

/// The computed output of the signal engine for one session — a plain value type
/// (the persisted `MeditationStats` @Model mirrors these fields).
///
/// The three resampled timeseries (heartRate, stillness, breathingRate) share ONE
/// overlapping sliding window and ONE index. `heartRateTimeseries` and
/// `stillnessTimeseries` always have length == window count. `breathingRateTimeseries`
/// and `breathDepthTimeseries` have length == window count ONLY for a belly session
/// with a readable breathing signal; otherwise they are EMPTY (the convention the
/// tests assert). Point `i`'s timestamp = `startedAt + i*hopSec + windowSec/2`.
struct SignalResult: Codable, Equatable {
    // Heart rate (always)
    var heartRateTimeseries: [Double]
    var meanHR: Double
    var startHR: Double?
    var endHR: Double?
    var hrDecline: Double?               // startHR - endHR; positive = slowed

    // Stillness (always)
    var stillnessTimeseries: [Double]
    var stillnessScore: Double?
    var stillnessMethod: String          // "total" | "breathingExcluded"

    // Belly breathing (only when opted in AND the signal was readable)
    var breathingRateTimeseries: [Double]
    var breathDepthTimeseries: [Double]
    var meanBreathingRate: Double?
    var breathingRegularity: Double?
    var resonanceMatchScore: Double?

    // Combined "practice landed" summary
    var overallScore: Double?

    var windowSec: Int
    var hopSec: Int
    var algorithmVersion: String
}

extension SignalResult {
    /// A copy with every non-finite Double replaced: NaN/Inf → 0 for required
    /// values and array elements, → nil for optionals. Real (messy) motion can push
    /// a breathing/stillness value non-finite; `JSONEncoder` throws on NaN/Inf, which
    /// silently dropped the whole WatchConnectivity transfer (the belly-nil bug).
    /// Sanitizing keeps the payload encodable AND the persisted stats clean.
    func sanitized() -> SignalResult {
        func f(_ x: Double) -> Double { x.isFinite ? x : 0 }
        func o(_ x: Double?) -> Double? { x.flatMap { $0.isFinite ? $0 : nil } }
        func a(_ arr: [Double]) -> [Double] { arr.map { $0.isFinite ? $0 : 0 } }
        return SignalResult(
            heartRateTimeseries: a(heartRateTimeseries), meanHR: f(meanHR),
            startHR: o(startHR), endHR: o(endHR), hrDecline: o(hrDecline),
            stillnessTimeseries: a(stillnessTimeseries), stillnessScore: o(stillnessScore),
            stillnessMethod: stillnessMethod,
            breathingRateTimeseries: a(breathingRateTimeseries),
            breathDepthTimeseries: a(breathDepthTimeseries),
            meanBreathingRate: o(meanBreathingRate), breathingRegularity: o(breathingRegularity),
            resonanceMatchScore: o(resonanceMatchScore), overallScore: o(overallScore),
            windowSec: windowSec, hopSec: hopSec, algorithmVersion: algorithmVersion
        )
    }
}

// MARK: - Engine
//
// Pure Swift (Foundation only — Accelerate is permitted by the spec but unnecessary
// at these lengths). Turns a raw capture into stillness / HR-decline / breathing
// metrics plus aligned timeseries and one overall score.
//
// WINDOWS: window `i` covers `[i*hopSec, i*hopSec + windowSec)`. Count =
// `floor((totalSec - windowSec) / hopSec) + 1`, or 0 if the session is shorter than
// one window. `totalSec` is the max end time across the motion and HR channels.
//
// BREATHING BAND: 0.033–0.5 Hz (~2–30 breaths/min). Resonance target: ~0.1 Hz (6/min).
//
// OVERALL SCORE WEIGHTING (documented, renormalized over whichever signals exist):
//   belly + readable breathing → stillness .30, hrDecline .25, resonance .25, regularity .20
//   otherwise (2-signal)       → stillness .55, hrDecline .45
// `hrDecline` is normalized as `clamp(decline / 15 bpm, 0, 1)` before weighting.
enum SignalEngine {

    static let version = "2.0.0"

    private static let breathBandLo = 0.033  // Hz — supports slow held breaths (~2/min)
    private static let breathBandHi = 0.5     // Hz
    private static let resonanceHz = 0.1      // ~6 breaths/min
    private static let concentrationMin = 0.30 // band power concentration for "clear"
    private static let ampFloor = 0.004        // rad; below this the pitch is flat
    private static let hrDeclineFull = 15.0    // bpm drop that maps to 1.0
    private static let stillnessGain = 5.0     // activity → stillness sharpness
    private static let attitudeWeight = 1.0    // radians vs g weighting in activity

    static func analyze(
        motion: [MotionSample],
        hr: [HRSample],
        bellyBreathing: Bool,
        windowSec: Int = 30,
        hopSec: Int = 5
    ) -> SignalResult {

        let totalSec = max(motion.last?.t ?? 0, hr.last?.t ?? 0)
        let w = Double(windowSec)
        let h = Double(hopSec)
        let windowCount = totalSec >= w ? Int(((totalSec - w) / h).rounded(.down)) + 1 : 0

        // Empty / too-short session: valid but blank result.
        guard windowCount > 0 else {
            let meanHR = hr.isEmpty ? 0 : hr.map(\.bpm).reduce(0, +) / Double(hr.count)
            return SignalResult(
                heartRateTimeseries: [], meanHR: meanHR, startHR: nil, endHR: nil, hrDecline: nil,
                stillnessTimeseries: [], stillnessScore: nil, stillnessMethod: "total",
                breathingRateTimeseries: [], breathDepthTimeseries: [],
                meanBreathingRate: nil, breathingRegularity: nil, resonanceMatchScore: nil,
                overallScore: nil, windowSec: windowSec, hopSec: hopSec, algorithmVersion: version
            )
        }

        let windows: [(lo: Double, hi: Double)] = (0..<windowCount).map {
            (Double($0) * h, Double($0) * h + w)
        }

        // MARK: Heart rate (always)
        let heartRateTimeseries = resampleHR(hr, windows: windows)
        let meanHR = hr.isEmpty ? 0 : hr.map(\.bpm).reduce(0, +) / Double(hr.count)
        let startHR = heartRateTimeseries.first
        let endHR = heartRateTimeseries.last
        let hrDecline: Double? = (startHR != nil && endHR != nil) ? startHR! - endHR! : nil

        // MARK: Breathing (belly only) — computed first so stillness knows whether
        // the breathing band should be excluded (readable) or not (fell back).
        var breathingRateTimeseries: [Double] = []
        var breathDepthTimeseries: [Double] = []
        var meanBreathingRate: Double?
        var breathingRegularity: Double?
        var resonanceMatchScore: Double?
        var breathingReadable = false

        // Band-passed attitude, plus the placement-tolerant breathing axis. Which
        // axis the belly's rise/fall tilts the wrist into depends on how it sits —
        // palm-on-belly offsets the watch off flat, so the breathing lands in roll
        // or a pitch+roll mix. We therefore choose the breathing axis by *cleanest
        // peak* (highest concentration) among pitch, roll, and their PCA principal
        // axis — NOT by variance. PCA alone maximizes variance, so a large
        // non-breathing sway (e.g. postural pitch drift while sitting up) captures
        // it and buries a clean breathing peak sitting on the other axis. Selecting
        // by concentration recovers that peak (verified on-device: a sitting-up
        // session read nil from PCA while roll carried a clean 0.43-conc signal).
        let times = motion.map(\.t)
        let pitchBP = bandPass(motion.map(\.pitch), times: times)
        let rollBP = bandPass(motion.map(\.roll), times: times)
        let breathBP = bellyBreathing
            ? selectBreathingAxis(pitchBP: pitchBP, rollBP: rollBP, times: times)
            : principalComponent(pitchBP, rollBP)

        if bellyBreathing {
            let amp = stddev(breathBP)
            let (bestF, bestP, totalP) = dominantFrequency(times: times, values: breathBP,
                                                            fMin: breathBandLo, fMax: breathBandHi)
            let concentration = (totalP > 0 && !pitchBP.isEmpty)
                ? 2 * bestP / (totalP * Double(pitchBP.count)) : 0

            if amp >= ampFloor && concentration >= concentrationMin && bestF > 0 {
                breathingReadable = true

                // Per-window rate (dominant band frequency) + depth (peak-to-trough).
                var rates: [Double] = []
                for win in windows {
                    let idx = indices(times, in: win)
                    if idx.count >= 8 {
                        let wt = idx.map { times[$0] }
                        let wp = idx.map { breathBP[$0] }
                        let (f, p, tot) = dominantFrequency(times: wt, values: wp,
                                                            fMin: breathBandLo, fMax: breathBandHi)
                        let conc = (tot > 0) ? 2 * p / (tot * Double(wp.count)) : 0
                        let rate = (conc >= concentrationMin && f > 0) ? f * 60 : 0
                        rates.append(rate)
                        let depth = (wp.max() ?? 0) - (wp.min() ?? 0)
                        breathDepthTimeseries.append(depth)
                    } else {
                        rates.append(0)
                        breathDepthTimeseries.append(0)
                    }
                }
                breathingRateTimeseries = rates

                let readable = rates.filter { $0 > 0 }
                if readable.isEmpty {
                    breathingReadable = false
                    breathingRateTimeseries = []
                    breathDepthTimeseries = []
                } else {
                    meanBreathingRate = readable.reduce(0, +) / Double(readable.count)
                    resonanceMatchScore = resonanceMatch(meanBreathingRate!)
                    breathingRegularity = regularity(signal: breathBP, times: times)
                }
            }
        }

        // MARK: Stillness (always). Belly + readable → exclude the breathing band so
        // the deliberate oscillation isn't penalized as restlessness; else score the
        // full motion ("total").
        let excludeBreathing = bellyBreathing && breathingReadable
        let stillnessMethod = excludeBreathing ? "breathingExcluded" : "total"

        // Residual attitude channels for the belly case: the breathing band is
        // removed from BOTH axes, so stillness is already axis-agnostic (no PCA).
        let pitchResid = zip(motion.map(\.pitch), pitchBP).map { $0 - $1 }
        let rollResid = zip(motion.map(\.roll), rollBP).map { $0 - $1 }

        var stillnessTimeseries: [Double] = []
        for win in windows {
            let idx = indices(times, in: win)
            let accel = idx.map { motion[$0].userAccel }
            let pitchCh = idx.map { excludeBreathing ? pitchResid[$0] : motion[$0].pitch }
            let rollCh  = idx.map { excludeBreathing ? rollResid[$0]  : motion[$0].roll }
            let activity = rms(accel) + attitudeWeight * (stddev(pitchCh) + stddev(rollCh))
            stillnessTimeseries.append(1 / (1 + stillnessGain * activity))
        }
        let stillnessScore = stillnessTimeseries.isEmpty
            ? nil : stillnessTimeseries.reduce(0, +) / Double(stillnessTimeseries.count)

        // MARK: Overall score
        let overallScore = combine(
            stillness: stillnessScore,
            hrDecline: hrDecline,
            resonance: resonanceMatchScore,
            regularity: breathingRegularity
        )

        return SignalResult(
            heartRateTimeseries: heartRateTimeseries, meanHR: meanHR,
            startHR: startHR, endHR: endHR, hrDecline: hrDecline,
            stillnessTimeseries: stillnessTimeseries, stillnessScore: stillnessScore,
            stillnessMethod: stillnessMethod,
            breathingRateTimeseries: breathingRateTimeseries, breathDepthTimeseries: breathDepthTimeseries,
            meanBreathingRate: meanBreathingRate, breathingRegularity: breathingRegularity,
            resonanceMatchScore: resonanceMatchScore,
            overallScore: overallScore,
            windowSec: windowSec, hopSec: hopSec, algorithmVersion: version
        ).sanitized()   // guarantee finite values — JSONEncoder throws on NaN/Inf
    }

    // MARK: - HR resampling

    /// Per-window mean BPM, gaps filled by nearest-known window so the series has no
    /// holes (length == window count).
    private static func resampleHR(_ hr: [HRSample], windows: [(lo: Double, hi: Double)]) -> [Double] {
        guard !hr.isEmpty else { return windows.map { _ in 0 } }
        var raw: [Double?] = windows.map { win in
            let vals = hr.filter { $0.t >= win.lo && $0.t < win.hi }.map(\.bpm)
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }
        // Forward then backward fill.
        var last: Double?
        for i in raw.indices { if let v = raw[i] { last = v } else { raw[i] = last } }
        var next: Double?
        for i in raw.indices.reversed() { if let v = raw[i] { next = v } else { raw[i] = next } }
        let fallback = hr.map(\.bpm).reduce(0, +) / Double(hr.count)
        return raw.map { $0 ?? fallback }
    }

    // MARK: - Breathing helpers

    /// Closeness of a rate (breaths/min) to the ~6/min resonance target, 0..1.
    private static func resonanceMatch(_ rate: Double) -> Double {
        let target = resonanceHz * 60          // 6
        return exp(-0.5 * pow((rate - target) / 2.0, 2))   // rate 6 → 1.0
    }

    /// Regularity from the variance of breath-to-breath intervals (up-crossings of
    /// the band-passed breathing-axis signal). Lower CoV → higher regularity.
    private static func regularity(signal: [Double], times: [Double]) -> Double? {
        var crossTimes: [Double] = []
        for i in 1..<signal.count where signal[i - 1] <= 0 && signal[i] > 0 {
            crossTimes.append(times[i])
        }
        guard crossTimes.count >= 3 else { return nil }
        var intervals: [Double] = []
        for i in 1..<crossTimes.count { intervals.append(crossTimes[i] - crossTimes[i - 1]) }
        let m = intervals.reduce(0, +) / Double(intervals.count)
        guard m > 0 else { return nil }
        let cv = stddev(intervals) / m
        return exp(-cv)   // CV 0 → 1.0
    }

    /// The candidate breathing axes (band-passed), in a fixed order: the raw pitch
    /// and roll attitude channels, plus their PCA principal axis. All three are
    /// scored the same way; `analyze` and `bellyDiagnostics` share this list so the
    /// diagnostic numbers reflect exactly what the engine reads.
    private static func breathingCandidates(pitchBP: [Double], rollBP: [Double]) -> [(label: String, bp: [Double])] {
        [("pitch", pitchBP), ("roll ", rollBP), ("pca  ", principalComponent(pitchBP, rollBP))]
    }

    /// Fraction of a band-passed axis's power sitting in its single dominant peak
    /// (0..1-ish) — the "how clean is the breathing" measure the readability gate uses.
    private static func bandConcentration(_ bp: [Double], times: [Double]) -> Double {
        let (_, p, tot) = dominantFrequency(times: times, values: bp, fMin: breathBandLo, fMax: breathBandHi)
        return (tot > 0 && !bp.isEmpty) ? 2 * p / (tot * Double(bp.count)) : 0
    }

    /// Picks the cleanest breathing axis: the highest-concentration candidate among
    /// those clearing the amplitude floor (a near-flat axis can show a spuriously
    /// high concentration, so gate on amplitude first). See the call site for why
    /// concentration beats PCA's variance criterion.
    private static func selectBreathingAxis(pitchBP: [Double], rollBP: [Double], times: [Double]) -> [Double] {
        let cands = breathingCandidates(pitchBP: pitchBP, rollBP: rollBP)
        let ranked = cands.map { (bp: $0.bp,
                                  rank: stddev($0.bp) >= ampFloor ? bandConcentration($0.bp, times: times) : -1) }
        return ranked.max(by: { $0.rank < $1.rank })!.bp
    }

    /// Direct band-limited DFT scan for the dominant frequency in `[fMin, fMax]`,
    /// using actual sample times (robust to non-uniform sampling). Returns the best
    /// frequency, its power, and the signal's total (mean-removed) power.
    private static func dominantFrequency(
        times: [Double], values: [Double], fMin: Double, fMax: Double
    ) -> (freq: Double, power: Double, total: Double) {
        guard values.count >= 8 else { return (0, 0, 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let x = values.map { $0 - mean }
        let total = x.reduce(0) { $0 + $1 * $1 }
        guard total > 0 else { return (0, 0, 0) }
        let steps = 120
        var bestF = 0.0, bestP = -1.0
        for k in 0...steps {
            let f = fMin + (fMax - fMin) * Double(k) / Double(steps)
            var re = 0.0, im = 0.0
            for i in 0..<x.count {
                let ang = 2 * Double.pi * f * times[i]
                re += x[i] * cos(ang)
                im -= x[i] * sin(ang)
            }
            let p = re * re + im * im
            if p > bestP { bestP = p; bestF = f }
        }
        return (bestF, bestP, total)
    }

    // MARK: - Filtering / stats

    /// Band-pass ~[0.05, 0.5] Hz via difference of two centered moving averages
    /// (fast low-pass minus slow low-pass). Zero-phase, adequate for this band.
    private static func bandPass(_ y: [Double], times: [Double]) -> [Double] {
        guard y.count > 2 else { return y.map { _ in 0 } }
        let fs = sampleRate(times)
        let fastWin = max(1, Int((fs * 1.0).rounded()))    // ~1 s  → LP ~0.5 Hz
        let slowWin = max(1, Int((fs * 20.0).rounded()))   // ~20 s → LP ~0.025 Hz (passes ~2/min)
        let fast = movingAverage(y, fastWin)
        let slow = movingAverage(y, slowWin)
        return zip(fast, slow).map { $0 - $1 }
    }

    private static func sampleRate(_ times: [Double]) -> Double {
        guard let first = times.first, let last = times.last, last > first, times.count > 1
        else { return 20 }
        return Double(times.count - 1) / (last - first)
    }

    private static func movingAverage(_ y: [Double], _ win: Int) -> [Double] {
        guard win > 1, !y.isEmpty else { return y }
        let half = win / 2
        var out = [Double](repeating: 0, count: y.count)
        for i in 0..<y.count {
            let lo = max(0, i - half), hi = min(y.count - 1, i + half)
            var s = 0.0
            for j in lo...hi { s += y[j] }
            out[i] = s / Double(hi - lo + 1)
        }
        return out
    }

    private static func indices(_ times: [Double], in win: (lo: Double, hi: Double)) -> [Int] {
        (0..<times.count).filter { times[$0] >= win.lo && times[$0] < win.hi }
    }

    private static func rms(_ y: [Double]) -> Double {
        guard !y.isEmpty else { return 0 }
        return (y.reduce(0) { $0 + $1 * $1 } / Double(y.count)).squareRoot()
    }

    private static func stddev(_ y: [Double]) -> Double {
        let n = Double(y.count)
        guard n > 1 else { return 0 }
        let m = y.reduce(0, +) / n
        return (y.reduce(0) { $0 + ($1 - m) * ($1 - m) } / n).squareRoot()
    }

    // MARK: - Score combination

    private static func combine(
        stillness: Double?, hrDecline: Double?, resonance: Double?, regularity: Double?
    ) -> Double? {
        var terms: [(value: Double, weight: Double)] = []
        let breathing = resonance != nil || regularity != nil
        let wStill = breathing ? 0.30 : 0.55
        let wHR = breathing ? 0.25 : 0.45

        if let s = stillness { terms.append((s, wStill)) }
        if let d = hrDecline { terms.append((min(max(d / hrDeclineFull, 0), 1), wHR)) }
        if let r = resonance { terms.append((r, 0.25)) }
        if let g = regularity { terms.append((g, 0.20)) }

        let totalWeight = terms.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return terms.reduce(0) { $0 + $1.value * $1.weight } / totalWeight
    }

    // MARK: - Diagnostics (temporary Phase-4 belly debugging)

    /// Per-axis breathing-readability inputs (pitch, roll, and a PCA dominant
    /// axis), for console logging when a belly session falls back to 2-signal.
    /// Reveals which axis actually carries the breathing given the watch's real
    /// (palm-on-belly, offset) placement. Pass the SAME trimmed + rebased motion
    /// `analyze` receives.
    static func bellyDiagnostics(motion: [MotionSample]) -> String {
        let times = motion.map(\.t)
        let pitchBP = bandPass(motion.map(\.pitch), times: times)
        let rollBP = bandPass(motion.map(\.roll), times: times)
        let cands = breathingCandidates(pitchBP: pitchBP, rollBP: rollBP)

        // The axis analyze() actually reads from (same rule as selectBreathingAxis).
        let ranked = cands.map { (label: $0.label,
                                  rank: stddev($0.bp) >= ampFloor ? bandConcentration($0.bp, times: times) : -1) }
        let selected = ranked.max(by: { $0.rank < $1.rank })!.label

        func line(_ label: String, _ bp: [Double]) -> String {
            let amp = stddev(bp)
            let (f, p, tot) = dominantFrequency(times: times, values: bp, fMin: breathBandLo, fMax: breathBandHi)
            let conc = (tot > 0 && !bp.isEmpty) ? 2 * p / (tot * Double(bp.count)) : 0
            let ok = amp >= ampFloor && conc >= concentrationMin && f > 0
            let mark = label == selected ? " ←reads" : ""
            return String(format: "%@ amp=%.4f conc=%.3f bestF=%.3fHz (%.1f/min) %@%@",
                          label, amp, conc, f, f * 60, ok ? "OK" : "reject", mark)
        }
        return ([
            String(format: "floor amp %.4f · min conc %.2f · fs %.1f · n %d",
                   ampFloor, concentrationMin, sampleRate(times), times.count),
        ] + cands.map { line($0.label, $0.bp) }).joined(separator: "\n")
    }

    /// The projection of two mean-removed channels onto their dominant (largest-
    /// variance) axis — a 2D PCA that finds the breathing oscillation regardless of
    /// how the watch is rotated on the belly.
    private static func principalComponent(_ a: [Double], _ b: [Double]) -> [Double] {
        let n = Double(a.count)
        guard n > 1, a.count == b.count else { return a }
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        let ca = a.map { $0 - ma }, cb = b.map { $0 - mb }
        var caa = 0.0, cbb = 0.0, cab = 0.0
        for i in 0..<a.count { caa += ca[i] * ca[i]; cbb += cb[i] * cb[i]; cab += ca[i] * cb[i] }
        caa /= n; cbb /= n; cab /= n
        let tr = caa + cbb, det = caa * cbb - cab * cab
        let disc = max(0, tr * tr / 4 - det).squareRoot()
        let lambda = tr / 2 + disc
        var vx = cab, vy = lambda - caa
        if abs(vx) < 1e-12 && abs(vy) < 1e-12 { vx = 1; vy = 0 }
        let norm = (vx * vx + vy * vy).squareRoot()
        vx /= norm; vy /= norm
        return zip(ca, cb).map { $0 * vx + $1 * vy }
    }
}
