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

    // The doorway: the slow opening the score is built from. See
    // SignalEngine.breathDoorway. Nil when the session never slowed down.
    var breathDoorwayRate: Double?
    var breathDoorwayHeldSec: Double?
    /// Seconds from session start to the beginning of the doorway. Drives the
    /// results graph's highlight of exactly the stretch that earned credit.
    var breathDoorwayStartSec: Double?
    /// Per-window path clarity, same index as breathingRateTimeseries.
    /// Persisted because `score` now needs it: without it a migration cannot
    /// recompute a score from stored fields, which is an invariant this engine
    /// relies on.
    var breathClarityTimeseries: [Double]

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
            resonanceMatchScore: o(resonanceMatchScore),
            breathDoorwayRate: o(breathDoorwayRate), breathDoorwayHeldSec: o(breathDoorwayHeldSec),
            breathDoorwayStartSec: o(breathDoorwayStartSec),
            breathClarityTimeseries: a(breathClarityTimeseries),
            overallScore: o(overallScore),
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

    static let version = "5.2.0"

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
    /// Enough windows to SHOW a rate. Deliberately lax: a number on screen that
    /// is roughly right beats an empty tile, and the user can see the curve and
    /// judge it. What this must never do is feed the score, which is gated
    /// separately and strictly (see wristConfidentFraction).
    private static let wristDisplayFraction = 0.35

    // MARK: The doorway (calibrated 2026-08-14 on fourteen captures)
    //
    // Breath scores the opening of a session, not its average. See
    // `breathDoorway` for why the gate is NOT applied at this level.
    private static let breathDwellMinSec = 60.0   // a stretch shorter than this
        // is one observation smeared across overlapping windows, not a held
        // rhythm. Windows overlap by 25 s, so two fully disjoint 30 s
        // observations are six windows apart: (7-1)*5 + 30 = 60.
        //
        // There is deliberately NO ramp above this floor. The first design
        // scaled credit from 60 s to 150 s, and no capture can validate that
        // curve because every one of them is under five minutes — applying it
        // drove three VERIFIED paced sessions down to 0.11, 0.67 and 0.78.
        // Revisit only when counted sessions longer than the ramp exist.
    private static let breathDoorwayMaxRate = 9.0  // breaths/min. Above this
        // nobody is deliberately slowing down, so there is no doorway and
        // breath simply leaves the score. Already this codebase's documented
        // line between slowing on purpose and just breathing.
    private static let breathDoorwayTrustedStartSec = 90.0  // a doorway that
        // BEGINS at or before this scores on start time alone. Measured: all
        // nine confirmed slow-breathing captures start their doorway within
        // 65 s (5, 5, 5, 5, 30, 35, 35, 45, 65). People who slow their breath
        // do it when they sit down.
    private static let breathDoorwayLateClarity = 0.85  // a doorway beginning
        // AFTER the trusted window must average this stretch clarity. The bar
        // sits where sway has never been: across 227 Monte-Carlo drift
        // sessions (random-walk wrist motion, no breathing in any of them)
        // the highest forged-doorway clarity was 0.79, median 0.61, while
        // real paced breathing reads 0.85–0.96. So someone who fidgets for
        // three minutes and then genuinely paces still scores — deliberate
        // pacing is exactly what produces 0.9 clarity — and mid-session sway
        // does not.
        //
        // The belly path feeds its concentration series through the same
        // rule; conc rarely reaches 0.85, so a late-starting belly doorway
        // will usually be refused. Accepted: belly is opt-in deliberate
        // practice begun at Begin, and dormant in the MVP.
    private static let breathDoorwayMaxStartSec = 300.0  // and after five
        // minutes nothing scores, however clear (Aziz, 2026-08-14). Slow
        // breathing is an entry technique — you open the state and then leave
        // it alone — so pacing late is managing a number rather than
        // meditating, and the effort of it costs the state being scored. Same
        // reason the app shows no live biometrics. Fixed seconds, NOT a
        // fraction of the session: opening the state does not take longer in
        // a 25-minute sit. A sit shorter than five minutes is unconstrained
        // by this cap, which is the intent — a four-minute sit is all
        // beginning.
        //
        // Late slow breathing earns nothing but is never penalised: breath
        // can only ever add, because a silent breath signal is ambiguous
        // between "very settled" and "we missed it".
        //
        // KNOWN RESIDUAL, accepted with eyes open: sway inside the trusted
        // window forges a doorway that start time cannot refuse. Measured on
        // pure synthetic drift through the gated engine: 62% of sits forge
        // one, independent of length — only the first 90 s matter now, and
        // the synthetic walk is the adversarial worst case (its clarity and
        // rate are tuned to look like breathing; the accel gate and clarity
        // floor barely bite on it). Nothing measured here separates those
        // from real early doorways — CC436767 (confirmed real slow breathing,
        // stretch clarity 0.58, start 45 s) and 39F2003D (confirmed NO
        // breathing, clarity 0.65, start 45 s) are indistinguishable, and any
        // gate refusing the second refuses the first. Accepted because breath
        // is .20 and binary: a forged doorway moves a typical session about
        // three points. At the old .45 weight it moved eighteen, and this
        // trade would have been wrong.
    private static let breathStretchFloorClarity = 0.45  // PROVISIONAL, not
        // measured. A per-window floor so one weak window BREAKS a run rather
        // than diluting its mean. It also stops `medianFiltered5`, which runs
        // after tracking, from bridging a gap into a fake contiguous stretch.
    private static let wristSoloConc = 0.40    // the winning axis alone is
        // believed at this clarity. A 9/min breath measured at 0.4–0.9 mrad
        // (live session 5 — faster breathing is SHALLOWER breathing) ran conc
        // 0.41–0.58 on the correct axis while the other axis carried junk, so
        // demanding pristine-or-agreement refused a session whose pitch track
        // averaged 9.0 against a counted 9. Between concentrationMin and this,
        // a window is believed only when both axes agree on the rate (within
        // 25%): a torso-driven breath rocks the whole arm together.
    private static let wristMinRate = 3.5      // breaths/min. Settling drift
        // leaks spectral power right at the band's bottom edge, so a window
        // whose "breath" sits at the boundary bin is indistinguishable from
        // drift by construction and must read as nothing. Real deliberate
        // breathing runs 4–8/min; nothing legitimate lives at 3.0–3.4.
    // MARK: Natural-breathing second pass (PROVISIONAL, awaiting calibration)
    //
    // The wrist constants above are tuned for DELIBERATE slow breathing, which
    // is a large slow wave. Quiet automatic breathing is present in the same
    // signal but sits 6–15× below the postural drift on top of it, so the drift
    // wins the peak and the window reads as nothing. The pilot recovered a
    // counted 11/min as ~10/min in about two thirds of windows on pitch, so the
    // information is there; it needs the drift removed, not the gates loosened.
    //
    // Loosening gates is how you get invented numbers, so this pass instead
    // suppresses drift two ways (a tighter band-pass and a per-window linear
    // detrend) and then applies the SAME clarity and coherence rules.
    //
    // EVERY CONSTANT BELOW IS A STARTING POINT, NOT A MEASUREMENT. They must be
    // fitted against real captures with counted breath rates before this ships,
    // exactly as the belly, camera and slow-wrist paths were. Until then the
    // pass can only ever add readings the first pass already refused, and it
    // still has to clear readable-fraction and IQR to say anything at all.
    private static let naturalSlowSec = 8.0     // band-pass low edge ≈ 0.125 Hz
        // (7.5/min) versus the slow path's 12 s (≈5/min). Drift at ~2.1/min is
        // attenuated far harder, at the cost of rates below ~8/min, which the
        // first pass already covers.
    private static let naturalBandLo = 0.13     // Hz (7.8/min) for the DFT scan,
        // above the band edge so drift's leakage cannot win the peak.
    private static let naturalMinRate = 8.0     // breaths/min. Below this belongs
        // to the first pass; overlapping the two would let a drift artefact be
        // reported twice under different tuning.
    private static let naturalAmpFloor = wristAmpFloor  // unchanged on purpose:
        // 0.5 mrad already sits only 2–3× above attitude sensor noise, and
        // faster breathing is SHALLOWER, so this is the constant most likely to
        // need real data. Lowering it without captures would read sensor noise.

    /// Above this rate a reading is reported but earns no resonance credit, and
    /// the score renormalises to heart/stillness exactly as an unread breath
    /// does.
    ///
    /// Without this, detecting normal breathing would PUNISH people for it:
    /// resonance is a bell curve on 6/min taking 45% of the score, so a session
    /// read at 14/min scores 0 on its largest component. Modelled on a real
    /// session (heart .8, stillness .6, 20 min) that is 72 today against 40 if
    /// the breath were simply read. 9/min is the documented boundary between
    /// deliberately slowing down and just breathing.
    /// Half-width of the score's breathing curve, in breaths/min. Wide on
    /// purpose: see breathCredit.
    private static let breathCreditWidth = 5.5

    // COVERAGE IS NO LONGER A SCORE GATE, and reintroducing one would undo the
    // whole doorway model. `wristConfidentFraction = 0.6` used to demand that
    // most of the session be readable breathing, which is exactly what a
    // three-minute opening inside a twenty-minute sit cannot satisfy. It was
    // never the thing catching junk either: measured across fourteen captures,
    // the session clarity mean is what rejects the confirmed no-breath session,
    // and coverage was only punishing correct practice. What replaces it is the
    // doorway's own contiguity requirement (see `breathDwellMinSec`), which is
    // a floor on held time rather than on session share.
    //
    // The split it protected still stands, and for the reason it was written:
    // at minute 2 of a counted session the engine reported 3.9/min at clarity
    // 0.76 while Aziz counted 10. It was not confused. A 4/min postural sway
    // genuinely carried 14x the power of his breath, and clean sway is
    // indistinguishable from clean breath by shape alone. Showing that number
    // costs little; letting it move the score would corrupt the only
    // measurement this product sells. The doorway start rules are now the
    // whole of that defence, and they are imperfect on purpose: early sway
    // can forge a doorway (measured — see breathDoorwayMaxStartSec), but at
    // a .20 binary weight that forgery buys about three points, and every
    // stricter gate tried so far refused real practice to prevent it.

    // MARK: Continuity tracking (calibrated 2026-08-10 on eleven captures)
    //
    // These govern how the rate curve is chosen as a whole. See trackRates.
    private static let wristTrackJumpCost = 0.45  // score paid per breath/min of
        // jump between consecutive windows. Swept against the counted captures
        // and the verified paced ones: below 0.35 the tracker barely holds a
        // line, and at 0.55 it starts dragging a verified 6.9/min session to
        // 5.3. Everything from 0.35 to 0.50 behaves identically, so this sits in
        // the middle of a flat region rather than on the edge of a cliff.
    private static let wristTrackPeaks = 3      // candidates kept per channel.
        // The true rate is the clearest peak in about half of windows and the
        // second or third in most of the rest; past three it is noise.
    private static let wristTrackFloor = 0.10   // clarity below which a peak is
        // not worth a state in the trellis.
    private static let wristCandidateMerge = 0.35  // breaths/min. Closer than
        // this and two candidates are one peak seen through two tunings.
    // REMOVED 2026-08-14: `wristMinPathClarity = 0.60`, the session-level mean
    // clarity along the tracked path. It threw away real doorways, and the
    // failure is structural rather than a bad constant.
    //
    // A 6.6-minute session opened with NINE consecutive windows at 4.8–5.5
    // breaths/min and clarity 0.91–1.00 — the cleanest doorway in the entire
    // capture library. The remaining 5.5 minutes of natural breathing read at
    // 0.36 and dragged the session mean to 0.51, under the bar. **The gate
    // punished a real doorway for what happened after it**, which is exactly
    // the length-dependence that got `wristConfidentFraction` deleted a week
    // earlier. Coverage and clarity-mean are the same bug wearing different
    // clothes: any whole-session statistic penalises a short opening inside a
    // long sit, and a short opening inside a long sit is the practice.
    //
    // Nor can it be moved to the STRETCH instead. Across nine confirmed slow
    // sessions stretch clarity spans 0.58–0.96 while the sessions to refuse
    // span 0.57–0.69. They overlap, and one real session sits below the
    // confirmed no-breathing one. Clarity does not carry the information; do
    // not re-tune it, and do not reintroduce a session-level gate of any kind.
    // Start time does carry it, plus a one-sided clarity admission for late
    // starts — see the doorway constants.
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
                breathDoorwayRate: nil, breathDoorwayHeldSec: nil,
                breathDoorwayStartSec: nil, breathClarityTimeseries: [],
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
        var scoredDoorway: BreathDoorway?     // nil unless the read is trustworthy
        var breathClarityTimeseries: [Double] = []
        var breathDoorwayRate: Double?
        var breathDoorwayHeldSec: Double?
        var breathDoorwayStartSec: Double?
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
                // Per-window concentration, kept rather than discarded: it is
                // the belly path's own clarity measure and the doorway needs
                // one. Without it a belly user who paced 6/min for three
                // minutes scored ZERO breath while a passive wrist user doing
                // exactly the same earned the full 45%.
                var concs: [Double] = []
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
                        concs.append(conc)
                        let depth = (wp.max() ?? 0) - (wp.min() ?? 0)
                        breathDepthTimeseries.append(depth)
                    } else {
                        rates.append(0)
                        concs.append(0)
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
                    breathingRegularity = regularity(signal: breathBP, times: times)
                    breathClarityTimeseries = concs
                    // The belly path uses concentrationMin as its floor, its
                    // own long-validated readability threshold, rather than the
                    // wrist's clarity scale. The whole-session gate above
                    // (amp + concentration) already ran, so this is the same
                    // two-tier shape the wrist path has.
                    let doorway = breathDoorway(rates: rates, clarities: concs,
                                                windowSec: windowSec, hopSec: hopSec,
                                                clarityFloor: concentrationMin)
                    breathDoorwayRate = doorway?.rate
                    breathDoorwayHeldSec = doorway?.heldSec
                    breathDoorwayStartSec = doorway?.startSec
                    resonanceMatchScore = (doorway?.rate).map(resonanceMatch)
                        ?? resonanceMatch(meanBreathingRate!)
                    scoredDoorway = doorway
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
            // Both tunings are evaluated on EVERY window and the clearer one
            // wins that window. Running one pass for the whole session was
            // wrong: a verified capture went 12 → 8 → 6.5 breaths/min across
            // five minutes (counted at three points), so whichever tuning you
            // pick for the session is wrong for part of it. Per window reads
            // 78% of that session against 64% and 44% for the passes alone.
            let windowAccel = windows.map { win in
                rms(indices(times, in: win).map { motion[$0].userAccel })
            }
            let gate = median(windowAccel) * wristAccelGateRatio

            if let r = readWrist(motion: motion, times: times, windows: windows,
                                 windowAccel: windowAccel, gate: gate,
                                 windowSec: windowSec, hopSec: hopSec) {
                breathingReadable = true
                breathingRateTimeseries = r.rates
                breathDepthTimeseries = r.depths
                meanBreathingRate = r.meanRate
                breathClarityTimeseries = r.clarity
                breathingRegularity = regularity(signal: r.axis, times: times)
                // What reaches the score is the opening, and only when the
                // session as a whole was clearly read. Clarity is the entire
                // gate now: a 4/min postural sway once read at clarity 0.76 in
                // a single window, but junk cannot hold a clear SESSION mean.
                // The doorway IS the gate now. Everything that decides whether
                // it may score lives inside `breathDoorway`: contiguity, the
                // per-window clarity floor, the rate ceiling, and the start
                // rules (trusted first 90 s; after that only unmistakable
                // clarity; after five minutes nothing). There is no
                // session-level test left.
                scoredDoorway = r.doorway
                // The PERSISTED doorway is the scored one, not the computed
                // one. A doorway the gate refused is a claim we declined to
                // back, and the results graph highlights this stretch as the
                // thing that earned credit — showing one that earned none would
                // be the graph contradicting the score above it. The confirmed
                // no-breathing capture computes a tidy 6.1/min doorway and must
                // display nothing at all.
                breathDoorwayRate = scoredDoorway?.rate
                breathDoorwayHeldSec = scoredDoorway?.heldSec
                breathDoorwayStartSec = scoredDoorway?.startSec
                // Rebased on the DOORWAY, not the session mean. A session that
                // held 5.5/min for three minutes and then breathed 12 used to
                // report "resonance 2%", which described neither the practice
                // nor the score built from it.
                resonanceMatchScore = (scoredDoorway?.rate).map(resonanceMatch)
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
                                 breathDoorway: scoredDoorway,
                                 durationSec: Int(totalSec.rounded()))

        return SignalResult(
            heartRateTimeseries: heartRateTimeseries, meanHR: meanHR,
            startHR: startHR, endHR: endHR, hrDecline: hrDecline,
            stillnessTimeseries: stillnessTimeseries, stillnessScore: stillnessScore,
            stillnessMethod: stillnessMethod,
            breathingRateTimeseries: breathingRateTimeseries, breathDepthTimeseries: breathDepthTimeseries,
            meanBreathingRate: meanBreathingRate, breathingRegularity: breathingRegularity,
            resonanceMatchScore: resonanceMatchScore,
            breathDoorwayRate: breathDoorwayRate, breathDoorwayHeldSec: breathDoorwayHeldSec,
            breathDoorwayStartSec: breathDoorwayStartSec,
            breathClarityTimeseries: breathClarityTimeseries,
            overallScore: overallScore,
            windowSec: windowSec, hopSec: hopSec, algorithmVersion: version
        ).sanitized()   // guarantee finite values — JSONEncoder throws on NaN/Inf
    }

    // MARK: - HR resampling

    /// Per-window mean BPM, gaps filled by nearest-known window so the series has no
    /// holes (length == window count).
    private static func resampleHR(_ hr: [HRSample], windows: [(lo: Double, hi: Double)]) -> [Double] {
        // No heart data at all means no series, NOT a series of zeros. Zeros
        // would draw a flat line pinned to the axis and a domain of -2...2,
        // which reads as "your heart rate was zero" rather than "the Watch did
        // not report one".
        guard !hr.isEmpty else { return [] }
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
    ///
    /// **SELECTION ONLY as of 5.0.0. This no longer scores anything.** The
    /// score's breath term is binary: a doorway exists or it does not (see
    /// `depth`). This still decides WHICH qualifying stretch becomes the
    /// doorway, and that job matters — "closest to 6 wins" means a 4/min
    /// postural sway loses to a real 6/min breath on the same session, which is
    /// free anti-artefact defence. Keep it for that even though the winner is
    /// now worth the same 1.0 whatever its rate.
    ///
    /// The two were the same thing until Aziz asked for breath to count at any
    /// rate. Resonance is a narrow bell on 6/min, which is correct as a
    /// measurement and brutal as a score: at 14/min it is essentially zero, so
    /// reading a normal breath would cost 45% of the total and someone
    /// breathing normally would score worse than someone whose breath was never
    /// read at all.
    ///
    /// This is the same idea with a heavy tail (Lorentzian, half-width 5.5/min).
    /// Slower always scores better and 6/min still tops it out, but nobody is
    /// zeroed for breathing the way people breathe:
    ///
    ///     6/min 1.00   8/min 0.88   10/min 0.65   14/min 0.32   20/min 0.13
    ///
    /// Modelled on a real session (heart .8, stillness .6, 20 min) that is
    /// 85 / 79 / 68 / 55 out of 100, against 72 for a breath never read.
    static func breathCredit(rate: Double) -> Double {
        let x = (rate - resonanceHz * 60) / breathCreditWidth
        return 1 / (1 + x * x)
    }

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
    private struct WristRead {
        let rates: [Double]
        let depths: [Double]
        /// Session mean over readable windows. DISPLAYED, never scored: the
        /// curve beneath it shows 5 then 11, so a headline claiming 5.2 would
        /// contradict its own picture.
        let meanRate: Double
        /// Per-window path clarity, aligned with `rates`. Persisted so a
        /// migration can recompute the score from stored fields alone.
        let clarity: [Double]
        /// The slow opening, if the session had one. This is what reaches the
        /// score.
        let doorway: BreathDoorway?
        let axis: [Double]
    }

    /// The two wrist tunings, evaluated per window.
    ///
    /// `slow` is the shipped calibration for deliberate slow breathing. `natural`
    /// suppresses postural drift instead (tighter band-pass, per-window linear
    /// detrend) so quiet automatic breathing, which sits 6–15× under that drift,
    /// can win its own peak. Neither is right for a whole session: a verified
    /// capture ran 12 → 6.5 breaths/min in five minutes.
    private struct WristTuning {
        let slowSec: Double, bandLo: Double, minRate: Double, detrend: Bool
    }
    private static let slowTuning = WristTuning(slowSec: 12, bandLo: wristBandLo,
                                                minRate: wristMinRate, detrend: false)
    private static let naturalTuning = WristTuning(slowSec: naturalSlowSec, bandLo: naturalBandLo,
                                                   minRate: naturalMinRate, detrend: true)

    /// Reads wrist breathing, taking whichever tuning is clearer in each window.
    ///
    /// Returns nil unless the curve is coherent: either tight, or a genuine
    /// trajectory. Verified against four captures, three of them with counted
    /// rates.
    private static func readWrist(
        motion: [MotionSample], times: [Double],
        windows: [(lo: Double, hi: Double)],
        windowAccel: [Double], gate: Double,
        windowSec: Int, hopSec: Int
    ) -> WristRead? {
        let tunings = [slowTuning, naturalTuning]
        // Band-pass once per tuning, not once per window.
        let banded = tunings.map { t in
            (pitch: bandPass(motion.map(\.pitch), times: times, slowSec: t.slowSec),
             roll:  bandPass(motion.map(\.roll),  times: times, slowSec: t.slowSec))
        }
        // The axis for regularity comes from the slow tuning, which spans the
        // whole band; it is descriptive only and gates nothing.
        let axis = selectBreathingAxis(pitchBP: banded[0].pitch, rollBP: banded[0].roll,
                                       times: times, floor: wristAmpFloor, fMin: wristBandLo)

        var rates: [Double] = []
        var depths: [Double] = []
        var pool: [[(rate: Double, clarity: Double)]] = []
        for (i, win) in windows.enumerated() {
            let idx = indices(times, in: win)
            guard idx.count >= 8 && windowAccel[i] <= gate else {
                rates.append(0); depths.append(0); pool.append([]); continue
            }
            let wt = idx.map { times[$0] }
            var bestRate = 0.0, bestConc = 0.0, bestDepth = 0.0
            var candidates: [(rate: Double, clarity: Double)] = []

            for (t, band) in zip(tunings, banded) {
                var wp = idx.map { band.pitch[$0] }
                var wr = idx.map { band.roll[$0] }
                // A straight line removed per window takes out the slow ramp a
                // band-pass alone leaves behind. At these amplitudes that is
                // the difference between a breath peak and a drift peak: on the
                // counted capture it lifted clarity from ~0.40 to ~0.55.
                if t.detrend {
                    wp = linearDetrended(wp, times: wt)
                    wr = linearDetrended(wr, times: wt)
                }
                let sP = scanSpectrum(times: wt, values: wp, fMin: t.bandLo, fMax: breathBandHi)
                let sR = scanSpectrum(times: wt, values: wr, fMin: t.bandLo, fMax: breathBandHi)
                let (fP, pP) = peakOf(sP), (fR, pR) = peakOf(sR)
                let cP = sP.total > 0 ? 2 * pP / (sP.total * Double(wp.count)) : 0
                let cR = sR.total > 0 ? 2 * pR / (sR.total * Double(wr.count)) : 0
                let (f, conc, chosen) = cP >= cR ? (fP, cP, wp) : (fR, cR, wr)
                let amp = max(stddev(wp), stddev(wr))
                let agree = fP > 0 && fR > 0 && abs(fP - fR) <= 0.25 * max(fP, fR)
                let readable = amp >= wristAmpFloor && f * 60 >= t.minRate
                    && (conc >= wristSoloConc || (conc >= concentrationMin && agree))
                if readable && conc > bestConc {
                    bestConc = conc
                    bestRate = f * 60
                    bestDepth = (chosen.max() ?? 0) - (chosen.min() ?? 0)
                }
                // Everything below feeds the tracker, and only for a window
                // this tuning would already have read. Offering candidates from
                // rejected windows raises the readable fraction, which is what
                // the display and score gates are made of: the tracker would be
                // loosening two thresholds as a side effect of choosing better.
                guard readable else { continue }
                for (scan, n) in [(sP, wp.count), (sR, wr.count)] where scan.total > 0 {
                    for (pf, pp) in topPeaks(scan, count: wristTrackPeaks) {
                        let clarity = 2 * pp / (scan.total * Double(n))
                        if pf * 60 >= t.minRate && clarity >= wristTrackFloor {
                            candidates.append((pf * 60, clarity))
                        }
                    }
                }
            }
            // Candidates a third of a breath apart are one peak seen twice,
            // through two tunings or two axes. Keep the clearer sighting.
            candidates.sort { $0.clarity > $1.clarity }
            var merged: [(rate: Double, clarity: Double)] = []
            for c in candidates where merged.allSatisfy({ abs($0.rate - c.rate) > wristCandidateMerge }) {
                merged.append(c)
            }
            pool.append(merged)
            rates.append(bestRate)
            depths.append(bestDepth)
        }

        // The path-clarity MEAN is deliberately unused: gating on it punished
        // a real doorway for the natural breathing that followed it. Per-window
        // clarity is still very much used — it decides which windows a doorway
        // may be built from. See `breathDoorwayMaxStartSec`.
        let (tracked, _, perWindowClarity) = trackRates(pool, fallback: rates)
        rates = medianFiltered5(tracked)

        let readable = rates.filter { $0 > 0 }
        let fraction = rates.isEmpty ? 0 : Double(readable.count) / Double(rates.count)
        let doorway = breathDoorway(rates: rates, clarities: perWindowClarity,
                                    windowSec: windowSec, hopSec: hopSec)

        // A doorway is its own grounds to return a read. Coverage alone used to
        // decide this, and a three-minute opening inside a twenty-minute sit is
        // 0.15 coverage — every session the doorway model exists to rescue
        // exited here before anything else could run.
        guard fraction >= wristDisplayFraction || doorway != nil else { return nil }

        return WristRead(rates: rates, depths: depths,
                         meanRate: readable.isEmpty
                             ? 0 : readable.reduce(0, +) / Double(readable.count),
                         clarity: perWindowClarity,
                         doorway: doorway,
                         axis: axis)
    }

    /// Picks the rate curve as a whole instead of one window at a time.
    ///
    /// Windows advance by 5 s and span 30, so consecutive windows share 25 s of
    /// signal: a real rhythm is nearly forced to give the same answer twice, and
    /// a spurious peak is not. Reading each window alone spends none of that
    /// redundancy, and it shows. Across the counted captures a candidate sits at
    /// the counted rate in about 95% of windows but is the single clearest peak
    /// in only about half, so the answer was usually present and usually
    /// discarded.
    ///
    /// Viterbi over the per-window candidates, scoring clarity minus a cost per
    /// breath/min of jump. This is what pitch trackers do, for the same reason:
    /// winner-takes-all on a single frame produces exactly this kind of error.
    ///
    /// Measured on the eleven captures: the displayed curve's spread falls
    /// sharply on five of them (one from 4.55 to 1.25 breaths/min), the three
    /// verified paced sessions come back bit-identical (6.1, 6.1, 5.2), and the
    /// readable fraction does not move anywhere. It does NOT improve accuracy
    /// against the counted rates, and nothing else tried did either.
    ///
    /// Returns the curve and the mean clarity along it, which is what decides
    /// whether the read may touch the score. **The tracker cannot inflate that
    /// number.** Picking each window's clearest peak maximises mean clarity by
    /// construction, so every other path scores lower: the tracker only ever
    /// spends clarity to buy continuity. A measure an estimator can only push
    /// down is safe to gate on, which is exactly what the curve's spread was
    /// not.
    ///
    /// `pathClarity` reports the same number per window rather than averaged,
    /// which is what `breathDoorway` needs to decide where a clear stretch
    /// starts and stops. Off-path windows are 0.
    private static func trackRates(
        _ windows: [[(rate: Double, clarity: Double)]], fallback: [Double]
    ) -> (rates: [Double], clarity: Double, pathClarity: [Double]) {
        var dp: [[Double]] = [], back: [[(Int, Int)?]] = []
        for (i, cands) in windows.enumerated() {
            guard !cands.isEmpty else { dp.append([]); back.append([]); continue }
            let prev = (0..<i).reversed().first { !dp[$0].isEmpty }
            var row: [Double] = [], ptr: [(Int, Int)?] = []
            for c in cands {
                guard let p = prev else { row.append(c.clarity); ptr.append(nil); continue }
                // A gated stretch costs one hop, not one per window skipped:
                // missing evidence is not evidence of a jump.
                var best = -Double.greatestFiniteMagnitude, arg = 0
                for (k, q) in windows[p].enumerated() {
                    let v = dp[p][k] - wristTrackJumpCost * abs(c.rate - q.rate)
                    if v > best { best = v; arg = k }
                }
                row.append(c.clarity + best)
                ptr.append((p, arg))
            }
            dp.append(row); back.append(ptr)
        }

        guard let last = dp.indices.reversed().first(where: { !dp[$0].isEmpty })
        else { return (fallback, 0, [Double](repeating: 0, count: windows.count)) }

        var out = [Double](repeating: 0, count: windows.count)
        var perWindow = [Double](repeating: 0, count: windows.count)
        var clarities: [Double] = []
        var i = last
        var j = dp[last].indices.max(by: { dp[last][$0] < dp[last][$1] }) ?? 0
        while true {
            out[i] = windows[i][j].rate
            perWindow[i] = windows[i][j].clarity
            clarities.append(windows[i][j].clarity)
            guard let step = back[i][j] else { break }
            (i, j) = step
        }
        let clarity = clarities.isEmpty
            ? 0 : clarities.reduce(0, +) / Double(clarities.count)
        return (out, clarity, perWindow)
    }

    // MARK: - The doorway
    //
    // Deliberate slow breathing is an ENTRY technique: a few minutes at ~6/min
    // to shift into parasympathetic dominance, after which attention moves
    // elsewhere and the breath returns to its own pace. Nobody paces 6/min for
    // twenty minutes; that is HRV biofeedback, not meditation.
    //
    // So the session mean was the wrong statistic, and it punished correct
    // practice twice over: if the natural phase was readable the mean dragged
    // from 5 to ~11 and credit collapsed, and if it wasn't, whole-session
    // coverage failed and breath left the score entirely.
    //
    // Breath now scores the DOORWAY. What came through it is already measured,
    // for the whole session, by heart settling and stillness.

    /// The stretch of slow breathing a session was opened with, if there was one.
    struct BreathDoorway: Equatable {
        /// Breaths per minute, averaged over the stretch.
        let rate: Double
        /// How long it was held, in seconds.
        let heldSec: Double
        /// Seconds from the start of the session to the start of the stretch.
        /// Drives the results graph's highlight, and is what the opening
        /// constraint is applied to.
        let startSec: Double
    }

    /// Finds the clearest case that this person deliberately slowed their breath.
    ///
    /// Every contiguous run of eligible windows is searched for the sub-run that
    /// best answers "how slow did you get", subject to being held long enough to
    /// be two independent observations rather than one smeared across indices.
    ///
    /// **This is not "slowest wins", it is "closest to 6 wins."** `breathCredit`
    /// peaks at 6 and falls away on both sides, so a 4/min postural sway scores
    /// 0.88 against a real 6/min doorway's 1.00. That asymmetry is free defence
    /// and the reason the search is safe to run at all.
    ///
    /// **Stretch clarity is one-sided evidence, and both halves are measured.**
    /// As a refusal test it fails: real doorways span clarity 0.58–0.96 and
    /// sway's forged ones span 0.57–0.79, interleaved — one confirmed-real
    /// session sits BELOW the confirmed no-breathing one, so any bar that
    /// refuses junk refuses real practice with it. (An earlier design gated
    /// here at 0.65 and produced a "doorway" inside a session with no
    /// breathing in it: searching sub-runs finds a good-looking stretch in
    /// junk.) As an ADMISSION test it works: sway has never produced 0.85
    /// across 227 Monte-Carlo drift runs. Hence the start rules — a doorway
    /// beginning in the trusted first 90 s needs no proof, a later one must
    /// clear the bar sway cannot forge, and past five minutes nothing scores.
    ///
    /// `maxStartSec` is a diagnostics override for tools sweeping the start
    /// rules; it bypasses the late-clarity test too. Never pass it from
    /// product code.
    static func breathDoorway(rates: [Double], clarities: [Double],
                              windowSec: Int, hopSec: Int,
                              clarityFloor: Double? = nil,
                              maxStartSec: Double? = nil) -> BreathDoorway? {
        guard rates.count == clarities.count, hopSec > 0 else { return nil }
        let floor = clarityFloor ?? breathStretchFloorClarity
        // Two windows are fully disjoint observations only when they are far
        // enough apart not to share signal: (n-1)*hop + window >= dwellMin.
        let minWindows = max(2, Int(((breathDwellMinSec - Double(windowSec))
                                     / Double(hopSec)).rounded(.up)) + 1)

        var best: (credit: Double, rate: Double, held: Double, start: Double)?
        var i = 0
        while i < rates.count {
            guard rates[i] > 0, clarities[i] >= floor else {
                i += 1; continue
            }
            var j = i
            while j + 1 < rates.count,
                  rates[j + 1] > 0, clarities[j + 1] >= floor {
                j += 1
            }
            // Prefix sums so every sub-run's rate and clarity means are O(1).
            var prefix = [0.0], cprefix = [0.0]
            for k in i...j {
                prefix.append(prefix[prefix.count - 1] + rates[k])
                cprefix.append(cprefix[cprefix.count - 1] + clarities[k])
            }
            for a in i...j where a + minWindows - 1 <= j {
                // A window is centred on its span, so window `a` begins
                // windowSec/2 before its centre.
                let startSec = max(0, Double(a) * Double(hopSec))
                guard startSec <= (maxStartSec ?? breathDoorwayMaxStartSec) else { break }
                for b in (a + minWindows - 1)...j {
                    let n = b - a + 1
                    let mean = (prefix[b - i + 1] - prefix[a - i]) / Double(n)
                    guard mean <= breathDoorwayMaxRate else { continue }
                    // Late start: only the clarity sway cannot forge admits it.
                    if maxStartSec == nil, startSec > breathDoorwayTrustedStartSec {
                        let clarityMean = (cprefix[b - i + 1] - cprefix[a - i]) / Double(n)
                        guard clarityMean >= breathDoorwayLateClarity else { continue }
                    }
                    let credit = breathCredit(rate: mean)
                    if best == nil || credit > best!.credit {
                        best = (credit, mean,
                                Double(b - a) * Double(hopSec) + Double(windowSec),
                                startSec)
                    }
                }
            }
            i = j + 1
        }
        return best.map { BreathDoorway(rate: $0.rate, heldSec: $0.held, startSec: $0.start) }
    }

    // The score gate used to ask whether the rate curve was one rhythm, by its
    // spread and, failing that, by how well a straight line fit it. That is
    // gone. It carried two documented errors: it refused a counted 4.5/min
    // session the engine had read correctly at 4.6, and it passed a session
    // Aziz confirmed had no breathing in it at all. Mean clarity along the
    // tracked path separates the same fourteen captures without either error.
    //
    // The deeper reason is that spread is the wrong thing to measure once a
    // tracker exists: the tracker minimises spread, so the gate was reading its
    // own output. Clarity runs the other way, since the tracker can only spend
    // it. Keep that asymmetry in mind before gating on anything else.

    private static func mean(_ y: [Double]) -> Double {
        y.isEmpty ? 0 : y.reduce(0, +) / Double(y.count)
    }

    /// Removes the best-fit straight line. Ordinary least squares on (t, y).
    private static func linearDetrended(_ y: [Double], times t: [Double]) -> [Double] {
        guard y.count >= 3 else { return y }
        let mt = mean(t), my = mean(y)
        var num = 0.0, den = 0.0
        for i in 0..<y.count {
            let dt = t[i] - mt
            num += dt * (y[i] - my)
            den += dt * dt
        }
        guard den > 0 else { return y }
        let slope = num / den
        return (0..<y.count).map { y[$0] - (my + slope * (t[$0] - mt)) }
    }

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
        let s = scanSpectrum(times: times, values: values, fMin: fMin, fMax: fMax)
        guard s.total > 0 else { return (0, 0, 0) }
        let (f, p) = peakOf(s)
        return (f, p, s.total)
    }

    private struct Spectrum {
        let freqs: [Double]
        let power: [Double]
        let total: Double
    }

    /// The band-limited DFT scan, kept whole rather than reduced to its peak.
    ///
    /// The wrist reader needs the runners-up as well as the winner, so it can
    /// track a rhythm across windows instead of re-electing one each time. The
    /// scan itself is unchanged and runs exactly once per channel per window.
    private static func scanSpectrum(
        times: [Double], values: [Double], fMin: Double, fMax: Double
    ) -> Spectrum {
        guard values.count >= 8 else { return Spectrum(freqs: [], power: [], total: 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let x = values.map { $0 - mean }
        let total = x.reduce(0) { $0 + $1 * $1 }
        guard total > 0 else { return Spectrum(freqs: [], power: [], total: 0) }
        let steps = 120
        var freqs = [Double](repeating: 0, count: steps + 1)
        var power = [Double](repeating: 0, count: steps + 1)
        for k in 0...steps {
            let f = fMin + (fMax - fMin) * Double(k) / Double(steps)
            var re = 0.0, im = 0.0
            for i in 0..<x.count {
                let ang = 2 * Double.pi * f * times[i]
                re += x[i] * cos(ang)
                im -= x[i] * sin(ang)
            }
            freqs[k] = f
            power[k] = re * re + im * im
        }
        return Spectrum(freqs: freqs, power: power, total: total)
    }

    private static func peakOf(_ s: Spectrum) -> (freq: Double, power: Double) {
        guard let k = s.power.indices.max(by: { s.power[$0] < s.power[$1] })
        else { return (0, 0) }
        return (s.freqs[k], s.power[k])
    }

    /// The strongest local maxima, strongest first. Local maxima rather than the
    /// top N bins, which would return one peak's shoulders N times over.
    private static func topPeaks(_ s: Spectrum, count: Int) -> [(Double, Double)] {
        guard s.power.count >= 3 else { return [] }
        var peaks: [(Double, Double)] = []
        for k in 1..<(s.power.count - 1)
        where s.power[k] >= s.power[k - 1] && s.power[k] > s.power[k + 1] {
            peaks.append((s.freqs[k], s.power[k]))
        }
        if peaks.isEmpty { peaks = [peakOf(s)] }
        peaks.sort { $0.1 > $1.1 }
        return Array(peaks.prefix(count))
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

    /// Minutes over which the linear ceiling rises from 50 to 100.
    private static let durationLinearFullMinutes = 10.0
    /// Minutes at which the long-sit bonus plateaus; past this, more time
    /// buys nothing.
    private static let durationBonusFullMinutes = 40.0
    /// The plateau of the long-sit bonus: +15% (Aziz, 2026-08-14).
    private static let durationMaxBonus = 0.15

    /// Time's shape, redesigned by Aziz (2026-08-14, replacing the v3 sqrt
    /// ceiling): a linear CEILING to ten minutes, then a small S-shaped BONUS.
    ///
    /// Under ten minutes: cap = 50 + 5·minutes, so a two-minute sit can reach
    /// 60 and an excellent ten-minute sit can reach 100. (The old curve capped
    /// 10 min at 82 and needed 20+ for 100 — this deliberately moves value
    /// toward shorter sessions.)
    ///
    /// Past ten minutes: 1 + 0.15·smoothstep, flat leaving 10 (the two arms
    /// join with matching slope-zero, no kink), accelerating through the
    /// inflection at 25, plateaued at +15% from 40 on.
    ///
    ///     2 min → 0.60   5 → 0.75   10 → 1.00   15 → 1.01   20 → 1.04
    ///     25 → 1.075   30 → 1.11   40+ → 1.15
    ///
    /// The bonus MULTIPLIES depth rather than adding points, which preserves
    /// the principle this factor has carried since v3: thirty restless minutes
    /// still lose to five settled ones. A restless 40-minute sit gains ~2
    /// points from the bonus; a settled one gains ~12. `score` clamps the
    /// product at 1.0, so a near-perfect long sit pins to 100 rather than
    /// overflowing.
    static func durationFactor(seconds: Int) -> Double {
        let minutes = max(0, Double(seconds)) / 60
        if minutes <= durationLinearFullMinutes {
            return 0.5 + 0.05 * minutes
        }
        let u = min(1, (minutes - durationLinearFullMinutes)
                       / (durationBonusFullMinutes - durationLinearFullMinutes))
        let s = u * u * (3 - 2 * u)              // smoothstep — the S shape
        return 1 + durationMaxBonus * s
    }

    /// THE score, from the same stored components a persisted row carries.
    ///
    /// `analyze` and the v3 back-fill both go through here on purpose: every
    /// input is a value `MeditationStats` already stores, so rescoring an old
    /// session is exactly equivalent to computing it fresh rather than an
    /// approximation of it. One code path means the two can never drift.
    static func score(stillnessScore: Double?,
                      heartRateTimeseries: [Double],
                      breathDoorway: BreathDoorway?,
                      durationSec: Int) -> Double? {
        let d = depth(stillness: stillnessScore.map(spreadStillness),
                      hrSettling: heartSettling(heartRateTimeseries),
                      breath: breathDoorway.map { _ in 1.0 })
        return d.map { min(1, $0 * durationFactor(seconds: durationSec)) }
    }

    /// Weighted depth (0–1) across whichever signals were actually read.
    ///
    /// **Breath is binary and weighted least (2026-08-14).** It was .45, the
    /// largest term, scored on how close the doorway rate sat to 6/min. Two
    /// measurements killed that:
    ///
    /// 1. **The rate curve was doing almost nothing.** A doorway can only exist
    ///    between 3.5 and 9 breaths/min, and across that whole reachable slice
    ///    `breathCredit` spans 0.77 to 1.00. For any realistic doorway of 5 to
    ///    7.5 it moved a 20-minute score by under two points. The gate had
    ///    already made the decision; the bell was decoration on top of it.
    /// 2. **We grade the binary far better than the rate.** Across all fourteen
    ///    calibration captures "did they deliberately slow their breath" was
    ///    right 14 out of 14. The rate itself carries about ±0.3/min on slow
    ///    breathing and ±1.9/min on natural. Score what the instrument
    ///    measures well.
    ///
    /// The weight moved because breath is also the least reliable of the three
    /// and covers the smallest part of the session. At .45 a restless sit with
    /// a CLIMBING heart rate scored 51 for a minute of pacing; at .20 it scores
    /// 28, which reads as the poor session it was. And there is no literature
    /// establishing how long the parasympathetic shift persists after you stop
    /// pacing, so paying breath for the whole session was never supportable.
    /// Heart settling and stillness run the whole session, so if the doorway
    /// really did open the state, those two already measure it.
    ///
    /// Absent breath keeps the hardcoded 0.60/0.40 rather than renormalising
    /// 0.50/0.30, deliberately: silent sessions then score EXACTLY what they
    /// scored before this change, so nothing in an existing history moves
    /// except the sessions that actually found a doorway.
    private static func depth(stillness: Double?, hrSettling: Double?, breath: Double?) -> Double? {
        var terms: [(value: Double, weight: Double)] = []
        let hasBreath = breath != nil
        if let r = breath                   { terms.append((r, 0.20)) }
        if let h = hrSettling               { terms.append((h, hasBreath ? 0.50 : 0.60)) }
        if let s = stillness                { terms.append((s, hasBreath ? 0.30 : 0.40)) }

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
