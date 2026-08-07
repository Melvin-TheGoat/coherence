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
// OVERALL SCORE: see the "Score v3" block below. Depth (breath .45 / heart .35 /
// stillness .20, renormalised when a signal is missing) multiplied by a duration
// ceiling. `hrDecline` remains a REPORTED stat; the score uses `heartSettling`.
enum SignalEngine {

    static let version = "3.0.0"

    private static let breathBandLo = 0.033  // Hz — supports slow held breaths (~2/min)
    private static let breathBandHi = 0.5     // Hz
    private static let resonanceHz = 0.1      // ~6 breaths/min
    private static let concentrationMin = 0.30 // band power concentration for "clear"
    private static let ampFloor = 0.004        // rad; below this the pitch is flat

    // MARK: Wrist-breathing calibration (pilot: 4 on-device sessions, 2026-08-07)
    //
    // Breathing read from the wrist resting anywhere (knee, lap, bed) — no
    // placement, no posture. The torso rocks the arm a fraction of a degree per
    // breath; deliberate slow breathing came back at the paced rate in every
    // posture tried (6.0 seated conc .53, 5.9 reclined conc .86). All three
    // constants are measurements, not guesses:
    private static let wristAmpFloor = 0.0005  // rad. Wrist waves are millirads —
        // the pilot's cleanest session was 2.6 mrad sd, but a genuinely still
        // user breathing gently measured 1.1–1.5 mrad (live session 3), which a
        // 1.5 mrad floor rejected: the stiller the body, the SMALLER the wave.
        // 0.5 mrad sits 2–3× above attitude sensor noise, so a watch on a table
        // still reads nothing, while the quietest real breath observed clears
        // it with double margin. The junk this floor doesn't catch (drift) is
        // caught by the rate floor and concentration gates, not amplitude.
    private static let wristBandLo = 0.05      // Hz (3/min). The wrist's enemy is
        // settling drift, which showed up at ~2.1/min in every pilot capture and
        // out-powers the breath 6–15×. The belly band's 0.033 floor (held
        // breaths) would hand the drift the peak; 0.05 excludes what we
        // observed while keeping 4/min breathing readable.
    private static let wristAccelGateRatio = 1.5  // × the session's own median
        // window accel → window unreadable. A slow arm reposition reads as a
        // clean fake ~2/min wave at only ~1.6× median accel (measured), far
        // under any absolute threshold that survives normal fidgeting. Relative
        // to the session's own median catches exactly the shift windows.
    private static let wristMinReadableFraction = 0.6  // of windows, or breathing
        // is dropped entirely. True sessions ran 0.85–1.00 across six live
        // captures; the worst junk session managed 0.51 by scattered luck.
        // Either the session's breath was readable, or 808 says nothing —
        // never a flickering half-curve, never a guess.
    private static let wristSoloConc = 0.40    // the winning axis alone is
        // believed at this clarity. A 9/min breath measured at 0.4–0.9 mrad
        // (live session 5 — faster breathing is SHALLOWER breathing) ran conc
        // 0.41–0.58 on the correct axis while the other axis carried junk, so
        // demanding pristine-or-agreement refused a session whose pitch track
        // averaged 9.0 against a counted 9. Between concentrationMin and this,
        // a window is believed only when both axes agree on the rate (within
        // 25%): a torso-driven breath rocks the whole arm together.
    private static let wristMaxRateIQR = 2.0   // breaths/min, across the final
        // readable curve. The junk-vs-truth tiebreak the per-window gates can't
        // make: a true breath is ONE coherent track (drifting 6.6→9.5 still
        // gave IQR 1.3–1.6), while junk assembles scattered plateaus at
        // different rates (4.8 here, 8.2 there → IQR 2.5). A session whose
        // readable rates spread wider than this is not one rhythm and ships
        // as nothing.
    private static let wristMinRate = 3.5      // breaths/min. Settling drift
        // leaks spectral power right at the band's bottom edge, so a window
        // whose "breath" sits at the boundary bin is indistinguishable from
        // drift by construction and must read as nothing. Real deliberate
        // breathing runs 4–8/min; nothing legitimate lives at 3.0–3.4.
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
        } else {
            // MARK: Wrist breathing — opportunistic, posture-free, evidence-only.
            //
            // Every non-belly session gets a breathing attempt with the wrist
            // calibration (tighter band, millirad floor, movement gating). The
            // user does nothing: no mode, no placement, no coaching. Deliberate
            // slow breathing reads; quiet automatic breathing usually won't
            // clear the readable-fraction floor, and then these fields stay
            // empty — the same honest degrade the belly path had.
            let pitchW = bandPass(motion.map(\.pitch), times: times, slowSec: 12)
            let rollW = bandPass(motion.map(\.roll), times: times, slowSec: 12)
            let axis = selectBreathingAxis(pitchBP: pitchW, rollBP: rollW, times: times,
                                           floor: wristAmpFloor, fMin: wristBandLo)

            // NO whole-file concentration gate here, deliberately — that gate
            // assumes a stationary rate. A real breath that drifts (the first
            // live session read 6.6 → 9.5/min across one minute) smears the
            // whole-file peak below the clarity floor and got rejected even
            // though every individual window was clean. Per-window gates below
            // (amplitude, clarity, movement, readable fraction) are the real
            // guards; the whole-file check only ever added this failure mode.
            if stddev(axis) >= wristAmpFloor {
                // Movement gate, relative to this session's own baseline: a slow
                // arm reposition sits at only ~1.6× the median window accel and
                // masquerades as a clean slow breath, so gated windows read 0
                // rather than a fake rate.
                let windowAccel = windows.map { win in
                    rms(indices(times, in: win).map { motion[$0].userAccel })
                }
                let gate = median(windowAccel) * wristAccelGateRatio

                var rates: [Double] = []
                var depths: [Double] = []
                for (i, win) in windows.enumerated() {
                    let idx = indices(times, in: win)
                    if idx.count >= 8 && windowAccel[i] <= gate {
                        // Both axes, per window. The best axis by clarity gives
                        // the rate; whether we BELIEVE it is the clean-or-agree
                        // rule on wristStrongConc above. The amplitude floor
                        // keeps a near-flat window's noise from showing a
                        // spuriously clean peak; the rate floor keeps settling
                        // drift's band-edge leakage from reading as breath.
                        let wt = idx.map { times[$0] }
                        let wpP = idx.map { pitchW[$0] }
                        let wpR = idx.map { rollW[$0] }
                        let (fP, pP, totP) = dominantFrequency(times: wt, values: wpP,
                                                               fMin: wristBandLo, fMax: breathBandHi)
                        let (fR, pR, totR) = dominantFrequency(times: wt, values: wpR,
                                                               fMin: wristBandLo, fMax: breathBandHi)
                        let cP = totP > 0 ? 2 * pP / (totP * Double(wpP.count)) : 0
                        let cR = totR > 0 ? 2 * pR / (totR * Double(wpR.count)) : 0
                        let (f, conc, wp) = cP >= cR ? (fP, cP, wpP) : (fR, cR, wpR)
                        let amp = max(stddev(wpP), stddev(wpR))
                        let agree = fP > 0 && fR > 0 && abs(fP - fR) <= 0.25 * max(fP, fR)
                        let readable = amp >= wristAmpFloor && f * 60 >= wristMinRate
                            && (conc >= wristSoloConc || (conc >= concentrationMin && agree))
                        rates.append(readable ? f * 60 : 0)
                        depths.append((wp.max() ?? 0) - (wp.min() ?? 0))
                    } else {
                        rates.append(0)
                        depths.append(0)
                    }
                }
                rates = medianFiltered5(rates)

                let readable = rates.filter { $0 > 0 }
                let fraction = rates.isEmpty ? 0 : Double(readable.count) / Double(rates.count)
                // Track coherence: one rhythm or nothing (see wristMaxRateIQR).
                let sortedR = readable.sorted()
                let iqr = sortedR.isEmpty ? 0
                    : sortedR[(sortedR.count * 3) / 4] - sortedR[sortedR.count / 4]
                if fraction >= wristMinReadableFraction && iqr <= wristMaxRateIQR {
                    breathingReadable = true
                    breathingRateTimeseries = rates
                    breathDepthTimeseries = depths
                    meanBreathingRate = readable.reduce(0, +) / Double(readable.count)
                    resonanceMatchScore = resonanceMatch(meanBreathingRate!)
                    breathingRegularity = regularity(signal: axis, times: times)
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

        // MARK: Overall score (v3 — see the Score v3 block below)
        //
        // Breath now counts toward the score on every session, not just belly
        // ones. The earlier evidence-only rule existed to avoid punishing
        // natural breathers, and the renormalising weights handle that better:
        // a session with no readable breath is scored on the two signals it
        // did produce, never penalised for the one it didn't. And breath turns
        // out to be the best-evidenced signal we can capture, so excluding it
        // was leaving the strongest measurement out of the number.
        // Time is a ceiling, not a bonus: it can cap a good session, never
        // rescue a bad one. Shared with the v3 back-fill — see `score`.
        let overallScore = score(stillnessScore: stillnessScore,
                                 heartRateTimeseries: heartRateTimeseries,
                                 resonanceMatchScore: resonanceMatchScore,
                                 durationSec: Int(totalSec.rounded()))

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
    private static func bandConcentration(_ bp: [Double], times: [Double],
                                          fMin: Double = breathBandLo) -> Double {
        let (_, p, tot) = dominantFrequency(times: times, values: bp, fMin: fMin, fMax: breathBandHi)
        return (tot > 0 && !bp.isEmpty) ? 2 * p / (tot * Double(bp.count)) : 0
    }

    /// Picks the cleanest breathing axis: the highest-concentration candidate among
    /// those clearing the amplitude floor (a near-flat axis can show a spuriously
    /// high concentration, so gate on amplitude first). See the call site for why
    /// concentration beats PCA's variance criterion. The floor and band default to
    /// the belly calibration; the wrist path passes its own.
    private static func selectBreathingAxis(pitchBP: [Double], rollBP: [Double], times: [Double],
                                            floor: Double = ampFloor,
                                            fMin: Double = breathBandLo) -> [Double] {
        let cands = breathingCandidates(pitchBP: pitchBP, rollBP: rollBP)
        let ranked = cands.map { (bp: $0.bp,
                                  rank: stddev($0.bp) >= floor ? bandConcentration($0.bp, times: times, fMin: fMin) : -1) }
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

    /// Band-pass via difference of two centered moving averages (fast low-pass
    /// minus slow low-pass). Zero-phase, adequate for this band. `slowSec`
    /// sets the low cutoff: 20 s passes ~2/min held breaths (belly); the wrist
    /// path uses ~12 s so settling drift falls out of the band instead of
    /// winning it.
    private static func bandPass(_ y: [Double], times: [Double], slowSec: Double = 20) -> [Double] {
        guard y.count > 2 else { return y.map { _ in 0 } }
        let fs = sampleRate(times)
        let fastWin = max(1, Int((fs * 1.0).rounded()))    // ~1 s  → LP ~0.5 Hz
        let slowWin = max(1, Int((fs * slowSec).rounded()))
        let fast = movingAverage(y, fastWin)
        let slow = movingAverage(y, slowWin)
        return zip(fast, slow).map { $0 - $1 }
    }

    private static func median(_ y: [Double]) -> Double {
        guard !y.isEmpty else { return 0 }
        let s = y.sorted()
        return s[s.count / 2]
    }

    /// Median-of-5 over the per-window rate curve. A single corrupted window
    /// flanked by agreement can't survive it; a genuinely gated stretch of
    /// three-plus zeros still reads as zero. Pilot-motivated: the one artifact
    /// window in the seated paced session (a 4.0 amid forty 6.0s) disappears
    /// under this filter, while the arm-shift stretch stays visible for the
    /// accel gate to handle.
    private static func medianFiltered5(_ y: [Double]) -> [Double] {
        guard y.count >= 5 else { return y }
        var out = y
        for i in y.indices {
            let lo = max(0, i - 2), hi = min(y.count - 1, i + 2)
            out[i] = median(Array(y[lo...hi]))
        }
        return out
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

    // MARK: - Score v3 · how deep you got, and how long you held it
    //
    // WHAT THE NUMBER MEANS, in the words the app uses: how far the body moved
    // out of stress and into recovery, and how long it stayed there. Three
    // signals index the same parasympathetic shift; time multiplies the result.
    //
    // WEIGHTS follow the evidence, not intuition (researched 2026-08-08):
    //   • Breath 45% — the strongest evidence we can capture. Resonance
    //     breathing IS the intervention in HRV-biofeedback trials, which carry
    //     the largest effects in this literature (Hedges g ≈ 0.8, Goessl 2017),
    //     and RSA/HRV is maximised at ~6/min via the baroreflex (Russo 2017).
    //     We measure the driver directly instead of inferring it from HRV we
    //     cannot read on this hardware.
    //   • Heart 35% — replicated but modest (g ≈ 0.24–0.37) and confounded by
    //     how wound up the user was at minute zero.
    //   • Stillness 20% — NO literature grades meditation depth by motion. It
    //     is an excellent validity check and a poor depth measure, which is
    //     exactly how it is used here.
    //   • No breath read → 60/40 heart/stillness.
    //
    // Superseded v2, which spent 55% on stillness. Measured across eight real
    // sessions, stillness ran 0.84–0.97 for every genuine sit (and 0.22 for a
    // deliberately fidgety one), so over half the old score was a constant
    // saying "yes, you sat down".
    //
    // `algorithmVersion` records which formula produced a row, so historical
    // sessions stay interpretable instead of being silently re-scored.

    /// Session length past which the ceiling stops rising. Settling happens
    /// early; past ~20 minutes you are maintaining a state, not reaching one.
    private static let durationFullMinutes = 20.0
    /// What a session of zero length would keep of its depth. The floor is why
    /// "two minutes still counts": a short sit is scored, not crushed.
    private static let durationFloor = 0.40

    /// Time as a CEILING, never a bonus. It multiplies depth, so length can cap
    /// a good session but can never rescue a bad one — thirty restless minutes
    /// still score worse than five settled ones. The square root is deliberate:
    /// the first ten minutes buy more than the second ten.
    ///
    ///     2 min → 0.59   5 min → 0.70   10 min → 0.82   20 min+ → 1.00
    static func durationFactor(seconds: Int) -> Double {
        let minutes = max(0, Double(seconds)) / 60
        let reach = (minutes / durationFullMinutes).squareRoot()
        return durationFloor + (1 - durationFloor) * min(1, reach)
    }

    /// THE score, from the same stored components a persisted row carries.
    ///
    /// `analyze` and the v3 back-fill both go through here on purpose: every
    /// input is a value `MeditationStats` already stores, so rescoring an old
    /// session is exactly equivalent to computing it fresh rather than an
    /// approximation of it. One code path means the two can never drift.
    static func score(stillnessScore: Double?,
                      heartRateTimeseries: [Double],
                      resonanceMatchScore: Double?,
                      durationSec: Int) -> Double? {
        let d = depth(stillness: stillnessScore.map(spreadStillness),
                      hrSettling: heartSettling(heartRateTimeseries),
                      resonance: resonanceMatchScore)
        return d.map { $0 * durationFactor(seconds: durationSec) }
    }

    /// Weighted depth (0–1) across whichever signals were actually read.
    private static func depth(stillness: Double?, hrSettling: Double?, resonance: Double?) -> Double? {
        var terms: [(value: Double, weight: Double)] = []
        let hasBreath = resonance != nil
        if let r = resonance                { terms.append((r, 0.45)) }
        if let h = hrSettling               { terms.append((h, hasBreath ? 0.35 : 0.60)) }
        if let s = stillness                { terms.append((s, hasBreath ? 0.20 : 0.40)) }

        let total = terms.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        return terms.reduce(0) { $0 + $1.value * $1.weight } / total
    }

    /// Stillness rescaled so real sessions actually spread out.
    ///
    /// The raw curve saturates: every genuine sit measured 0.84–0.97. Mapping
    /// [0.80, 0.98] onto [0, 1] restores the resolution — a typical good sit
    /// lands mid-scale and near-perfect stillness has to be earned — while
    /// anything below 0.80 (the fidgety session's territory) floors at 0.
    static func spreadStillness(_ raw: Double) -> Double {
        let lo = 0.80, hi = 0.98
        return min(1, max(0, (raw - lo) / (hi - lo)))
    }

    /// The heart term: mostly "did you stay at or below where you started",
    /// with a minority credit for how far you actually fell.
    ///
    /// Start-minus-end alone measured how wound up someone was at minute zero
    /// rather than how they settled — a 68→68 session is a good sit with no
    /// room to fall and used to score zero. But *only* counting time-below-open
    /// saturates: every session that doesn't climb scores a flat 1.0, and the
    /// term stops discriminating.
    ///
    /// So: 60% for holding at or under your opening (the fairness floor, which
    /// a naturally calm person can always earn), 40% for the size of the drop
    /// (the headroom, which only an agitated body can fully claim). A flat calm
    /// sit lands at 0.6; a real 12-beat settle approaches 1.0; climbing lands
    /// near zero.
    static func heartSettling(_ series: [Double]) -> Double? {
        guard series.count >= 3, let opening = series.first, let closing = series.last
        else { return nil }
        // A small tolerance so ordinary wobble at the opening level still counts
        // as "not climbing".
        let atOrBelow = series.dropFirst().filter { $0 <= opening + 1.0 }.count
        let held = Double(atOrBelow) / Double(series.count - 1)
        let dropped = min(max((opening - closing) / hrDropFull, 0), 1)
        return 0.6 * held + 0.4 * dropped
    }

    /// Beats of decline that earn full credit for the drop half of the heart
    /// term. Twelve is a big settle: the verified Phase-4 pair sat around 9–11.
    private static let hrDropFull = 12.0

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
