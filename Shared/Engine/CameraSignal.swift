import Foundation

// MARK: - Camera vision: the no-Watch session engine
//
// Pure Foundation. Turns the per-frame numbers the camera collector records
// (`CameraSignalRecorder` in the app, `tools/camera_probe.swift` offline) into
// the same `SignalResult` the Watch produces, minus heart rate: a stillness
// curve, a breathing-rate curve with per-window clarity, a doorway, and a score.
//
// Everything in here was proven in `tools/camera_probe.swift` against two real
// propped-phone videos before it was ported (branch notes, CAMERA VISION ROUND
// 2), and the port is checked against those same captures by
// `tools/camera_harness.swift`. The pieces, in order:
//
//   1. Six channels of sub-pixel body shift (whole-frame dy/dx/luma and the
//      same three inside the torso ROI), each high-passed against a 15 s
//      moving average so postural and lighting drift stop owning the spectrum.
//   2. Per window (30 s, hop 5 s): a straight line out, then a band-limited
//      DFT scan over 3.5–26 breaths/min. Clarity is the peak's power over the
//      sum of INDEPENDENT bins (spacing 60/windowSec), not over the fine scan,
//      which would count the same power many times and dilute every peak.
//      A peak on either scan edge is leakage, not a read, and gets clarity 0.
//   3. The top three peaks of every channel are POOLED into one candidate set
//      per window, and a Viterbi tracker with a jump cost of 0.45 per natural-log unit of rate RATIO (was per
//      breath/min picks the curve as a whole. The path may switch channel for
//      free: six views of the same chest, not six hypotheses. This is what
//      resolved the harmonics (a paced 6/min opening read 12 whole-frame and
//      5 in the ROI; continuity picks the fundamental).
//   4. Stillness is the mean |frame difference| inside the ROI per window,
//      normalised to the session's own floor (10th percentile of 5 s means),
//      because absolute motion is 0.21 at 2 m / 4K and 0.50 at 0.5 m / 1080p
//      for the same stillness.
//
// The doorway and the time factor are the Watch engine's own
// (`SignalEngine.breathDoorway`, `SignalEngine.durationFactor`,
// `SignalEngine.spreadStillness`), so the two instruments share one
// definition of "slowed the breath at the start" and one time ceiling. What
// the camera cannot share is the heart term; see `score`.

/// One processed camera frame: nine numbers, no pixels. The recorder reduces
/// every frame to these before it is released, and this module never sees
/// anything else. `t` is seconds from the SESSION start (the collector pins
/// t = 0 to the Watch's started-ack; the offline harness solves the offset).
struct CameraFrame {
    let t: Double
    /// Whole frame: mean |luma diff| vs the previous frame, integrated vertical
    /// and horizontal profile shift (downsampled px), mean luma of the central
    /// third.
    let motion: Double
    let dy: Double
    let dx: Double
    let luma: Double
    /// The same four inside the torso ROI. Equal to the whole-frame values
    /// while no ROI is fixed.
    let rmotion: Double
    let rdy: Double
    let rdx: Double
    let rluma: Double

    init(t: Double, motion: Double, dy: Double, dx: Double, luma: Double,
         rmotion: Double, rdy: Double, rdx: Double, rluma: Double) {
        self.t = t
        self.motion = motion; self.dy = dy; self.dx = dx; self.luma = luma
        self.rmotion = rmotion; self.rdy = rdy; self.rdx = rdx; self.rluma = rluma
    }
}

/// A parsed capture file: the frames plus the header facts the analysis needs.
struct CameraCapture {
    var frames: [CameraFrame]
    /// Seconds into the capture at which the ROI was fixed, when the file says.
    var roiFixedAtSec: Double?
    var hasROI: Bool

    /// Reads the collector's CSV (and the probe's, which is the same nine
    /// columns). `#` lines are headers; `# roi_fixed_at_sec=` is honoured.
    static func parse(csv text: String) -> CameraCapture {
        var frames: [CameraFrame] = []
        var fixedAt: Double?
        var hasROI = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("#") {
                if line.hasPrefix("# roi x=") { hasROI = true }
                if line.hasPrefix("# roi_fixed_at_sec="),
                   let v = Double(line.dropFirst("# roi_fixed_at_sec=".count)), v >= 0 {
                    fixedAt = v
                }
                continue
            }
            if line.hasPrefix("t,") { continue }
            let f = line.split(separator: ",").compactMap { Double($0) }
            if f.count == 9 {
                frames.append(CameraFrame(t: f[0], motion: f[1], dy: f[2], dx: f[3], luma: f[4],
                                          rmotion: f[5], rdy: f[6], rdx: f[7], rluma: f[8]))
            } else if f.count == 5 {
                frames.append(CameraFrame(t: f[0], motion: f[1], dy: f[2], dx: f[3], luma: f[4],
                                          rmotion: f[1], rdy: f[2], rdx: f[3], rluma: f[4]))
            }
        }
        return CameraCapture(frames: frames, roiFixedAtSec: fixedAt, hasROI: hasROI)
    }
}

enum CameraSignal {

    /// Prefixed so a stats row can be told apart from a Watch row by its
    /// version string alone. `ScoreMigration` must skip rows with this prefix:
    /// the Watch formula given an empty heart series renormalises to
    /// breath .40 / stillness .60, which is not this instrument's score.
    /// 1.1.0: the tracker's jump cost is per log-ratio, not per breath/min,
    /// which removed a hard ceiling near 7.5/min (see `jumpCost`).
    static let version = "camera-1.1.0"
    static let versionPrefix = "camera-"

    // MARK: Constants. Each one is a measurement; the capture is named.

    /// Seconds of the centred moving average subtracted from every channel.
    /// The probe's value throughout both rounds; drift lives well below it.
    static let highpassSec = 15.0
    /// Scan band, breaths/min. 26 rather than 20: the ROI was reporting 19.9
    /// on IMG_9543 with a 20 ceiling, which was the ceiling, not the breath.
    static let loRate = 3.5
    static let hiRate = 26.0
    static let scanStep = 0.1
    /// A peak this close to either scan edge is leakage and gets clarity 0.
    static let edgeMargin = 0.15
    /// Continuity tracker. Swept 0.45 down to 0.03 on IMG_9543: 0.45 is best or
    /// tied and error climbs monotonically below it (1.68 to 2.71/min). The
    /// same flat-then-cliff the wrist path found, so the same constant.
    static let trackJumpCost = 0.45
    static let trackPeaks = 3
    static let trackFloor = 0.10
    static let candidateMerge = 0.35
    /// Tracked clarity at or above which a window is READ (its rate is shown
    /// and may join a doorway). The probe's bar for every number in the notes.
    static let readClarity = 0.30
    /// Enough read windows to show a curve at all. The Watch's product rule
    /// (`SignalEngine.wristDisplayFraction`), not a tuning: a doorway is its
    /// own grounds to show the curve.
    static let displayFraction = 0.20
    /// Per-window ROI motion above this multiple of the session's median
    /// window motion makes the window unreadable for breathing. MEASURED on
    /// both captures (harness, `--gate off --dump`), and NOT the wrist's 1.5:
    /// that ratio closed 29 of 114 windows on IMG_7635, fifteen of them
    /// correct reads through Melvin's minute-2 and minute-6 shifts (camera
    /// 5.3 and 5.3 against the wrist's 6.3 and 5.2, at x2.0 to x3.6 the
    /// median), and pushed median error from 1.27 to 1.52 breaths/min. What
    /// the gate exists for sits far above that: Melvin's 2.5-minute settle
    /// runs x11 to x53 and reads a "6/min" at clarity 0.35 to 0.62 while he
    /// is still climbing onto the bed; Aziz's sit-down runs x5.7 and reads
    /// 3.9/min, the slow-movement fake the wrist path documented. x4 closes
    /// every one of those and keeps every correct read on both captures; one
    /// sit-down window at x3.4 (IMG_9543, 20 s, reads 4.0) slips under it.
    /// Aziz's minute-19 sway, a rock-steady 4.5/min at clarity 0.93, sits at
    /// x1.1 and is NOT a motion-gate problem at any ratio: that is why late
    /// doorways are refused on this instrument (see `doorway`).
    static let motionGateRatio = 4.0
    /// The floor a session's stillness is read against: this percentile of
    /// its 5 s motion means. The probe's rule from round 2.
    static let stillnessFloorPercentile = 0.10
    static let stillnessFloorSpanSec = 5.0
    /// stillness = 1 / (1 + gain * (ratio - 1)), ratio = window motion over
    /// the floor. Gain pins the settled 90th percentile of IMG_7635 (x1.31 the
    /// floor, 2 m, chest-up) to 0.90, the middle of the Watch's measured range
    /// for a genuine sit (0.84 to 0.97), so `SignalEngine.spreadStillness`
    /// applies to both instruments unchanged. The settle spike on the same
    /// capture (x18) then reads 0.14 and getting up (x64) reads 0.04.
    static let stillnessGain = 0.36
    /// Breath's share of depth when a doorway exists. Kept at the Watch's
    /// weight, NOT renormalised upward, because that is the weight at which a
    /// forged early doorway was measured to move a session about three
    /// points and accepted. See `score`.
    static let breathWeight = 0.20

    /// Fewest frames a window needs to be scanned. Half a second at the
    /// collector's 10 fps is too few for anything; eight matches the Watch.
    static let minWindowSamples = 8

    // MARK: - The whole thing

    /// The camera's `SignalResult`. Heart fields are empty (no series, not a
    /// series of zeros: the results screen draws no heart panel for an empty
    /// series, which is the truth). `roiFixedAtSec` limits the stillness floor
    /// to frames after the ROI was fixed, since before that the ROI columns
    /// carry whole-frame values on a different scale.
    static func analyze(frames: [CameraFrame],
                        roiFixedAtSec: Double? = nil,
                        windowSec: Int = 30, hopSec: Int = 5,
                        gateRatio: Double = motionGateRatio) -> SignalResult {
        let totalSec = frames.last?.t ?? 0
        let windows = windows(totalSec: totalSec, windowSec: windowSec, hopSec: hopSec)

        guard !windows.isEmpty else {
            return SignalResult(
                heartRateTimeseries: [], meanHR: 0, startHR: nil, endHR: nil, hrDecline: nil,
                stillnessTimeseries: [], stillnessScore: nil, stillnessMethod: "camera",
                breathingRateTimeseries: [], breathDepthTimeseries: [],
                meanBreathingRate: nil, breathingRegularity: nil, resonanceMatchScore: nil,
                breathDoorwayRate: nil, breathDoorwayHeldSec: nil,
                breathDoorwayStartSec: nil, breathClarityTimeseries: [],
                overallScore: nil, windowSec: windowSec, hopSec: hopSec, algorithmVersion: version)
        }

        let times = frames.map(\.t)
        let read = breathing(frames: frames, times: times, windows: windows,
                             windowSec: windowSec, hopSec: hopSec, gateRatio: gateRatio)
        let still = stillness(motion: frames.map(\.rmotion), times: times, windows: windows,
                              floorFromSec: roiFixedAtSec ?? 0)
        let stillnessScore = still.isEmpty ? nil : still.reduce(0, +) / Double(still.count)

        let showBreath = read.fraction >= displayFraction || read.doorway != nil
        let readable = read.rates.filter { $0 > 0 }

        return SignalResult(
            heartRateTimeseries: [], meanHR: 0, startHR: nil, endHR: nil, hrDecline: nil,
            stillnessTimeseries: still, stillnessScore: stillnessScore, stillnessMethod: "camera",
            breathingRateTimeseries: showBreath ? read.rates : [],
            breathDepthTimeseries: [],
            meanBreathingRate: showBreath && !readable.isEmpty
                ? readable.reduce(0, +) / Double(readable.count) : nil,
            breathingRegularity: nil,
            resonanceMatchScore: nil,
            breathDoorwayRate: read.doorway?.rate,
            breathDoorwayHeldSec: read.doorway?.heldSec,
            breathDoorwayStartSec: read.doorway?.startSec,
            breathClarityTimeseries: showBreath ? read.clarity : [],
            overallScore: score(stillnessScore: stillnessScore,
                                breathDoorway: read.doorway,
                                durationSec: Int(totalSec.rounded())),
            windowSec: windowSec, hopSec: hopSec, algorithmVersion: version
        ).sanitized()
    }

    /// The same window grid as `SignalEngine.analyze`: window `i` covers
    /// `[i*hop, i*hop + window)`, count = floor((total - window) / hop) + 1.
    static func windows(totalSec: Double, windowSec: Int, hopSec: Int) -> [(lo: Double, hi: Double)] {
        let w = Double(windowSec), h = Double(hopSec)
        guard hopSec > 0, windowSec > 0, totalSec >= w else { return [] }
        let count = Int(((totalSec - w) / h).rounded(.down)) + 1
        return (0..<count).map { (Double($0) * h, Double($0) * h + w) }
    }

    // MARK: - Score

    /// THE camera score. Same shape as the Watch's: depth times the shared
    /// time factor, clamped at 1.
    ///
    /// **No heart, so the split is breath .20 / stillness .80 with a doorway,
    /// stillness alone without one.** Not the .40 / .60 the Watch's `depth`
    /// would produce by renormalising around a missing heart term, and the
    /// reason is a measurement already on file: the Watch accepted that 62%
    /// of pure-drift sits forge an early doorway BECAUSE breath is .20 and a
    /// forgery therefore moves a session about three points. On this
    /// instrument a forged doorway is worth `breathWeight * (1 - stillness)`,
    /// so at .20 it buys four points on a settled sit and ten on a restless
    /// one; at .40 it would buy twenty on the restless one, and that is the
    /// trade the wrist refused at .45. Every other number is a guess.
    ///
    /// Stillness carrying .80 is the cost, stated plainly: on the Watch it was
    /// demoted to .20 because it saturated (0.84 to 0.97 on every genuine sit).
    /// The camera's does not saturate the same way. The settle is unmistakable
    /// (x18 to x64 the floor on both captures), the ROI resolves a 2.5-minute
    /// settle where whole-frame saw one minute, and getting up reads as
    /// getting up. What it cannot resolve at 2 m is a wrist fidget (x1.1 to
    /// x1.5 against a settled x1.31). So this score answers "did you settle
    /// and stay settled" well and "how deep" poorly, which is what a camera at
    /// two metres can honestly say. Rows carry `algorithmVersion` "camera-"
    /// so the history never compares this number to a Watch score as if they
    /// were the same formula.
    static func score(stillnessScore: Double?,
                      breathDoorway: SignalEngine.BreathDoorway?,
                      durationSec: Int) -> Double? {
        guard let s = stillnessScore else { return nil }
        let stillness = SignalEngine.spreadStillness(s)
        let depth = breathDoorway == nil
            ? stillness
            : breathWeight * 1.0 + (1 - breathWeight) * stillness
        return min(1, depth * SignalEngine.durationFactor(seconds: durationSec))
    }

    // MARK: - Breathing

    struct Peak: Equatable {
        let rate: Double      // breaths/min
        let clarity: Double   // peak power over the sum of independent bins
    }

    /// One channel's read of one window.
    struct WindowRead {
        let rate: Double
        let clarity: Double
        let amplitude: Double      // rms of the detrended window
        /// Top local maxima, clearest first, for the tracker.
        let peaks: [Peak]
        static let empty = WindowRead(rate: 0, clarity: 0, amplitude: 0, peaks: [])
    }

    struct BreathRead {
        /// Tracked rate per window; 0 = unreadable (gated, or clarity under
        /// `readClarity`). Zero means "could not read", never "zero breaths".
        let rates: [Double]
        /// The tracker's path before the clarity floor zeroes it (0 only where
        /// no candidate existed). Diagnostics: lets the harness sweep the floor.
        let tracked: [Double]
        /// Tracked path clarity per window, 0 off the path.
        let clarity: [Double]
        /// Fraction of windows read.
        let fraction: Double
        /// Windows the motion gate closed.
        let gated: [Bool]
        let doorway: SignalEngine.BreathDoorway?
    }

    /// The six channels, pooled and tracked. Exposed for the harness.
    /// `gateRatio` is a diagnostics override for the harness sweeping the
    /// gate; product code takes the default.
    static func breathing(frames: [CameraFrame], times: [Double],
                          windows: [(lo: Double, hi: Double)],
                          windowSec: Int, hopSec: Int,
                          gateRatio: Double = motionGateRatio) -> BreathRead {
        let channels: [[Double]] = [frames.map(\.dy), frames.map(\.dx), frames.map(\.luma),
                                    frames.map(\.rdy), frames.map(\.rdx), frames.map(\.rluma)]
        let reads = channels.map { windowReads(signal: $0, times: times, windows: windows, windowSec: windowSec) }

        // Movement rejection, the wrist's rule: a window moving more than
        // 1.5x the session's median window offers no candidates at all.
        let motionWin = windowMeans(frames.map(\.rmotion), times: times, windows: windows)
        let gate = median(motionWin) * gateRatio
        let gated = motionWin.map { $0 > gate }

        var pooled: [[Peak]] = []
        for w in windows.indices {
            pooled.append(gated[w] ? [] : pool(reads.map { $0[w] }))
        }
        let (tracked, clarity) = trackRates(pooled)
        let rates = zip(tracked, clarity).map { $1 >= readClarity ? $0 : 0 }
        let fraction = rates.isEmpty ? 0 : Double(rates.filter { $0 > 0 }.count) / Double(rates.count)
        let door = doorway(rates: rates, clarities: clarity, windowSec: windowSec, hopSec: hopSec)
        return BreathRead(rates: rates, tracked: tracked, clarity: clarity, fraction: fraction,
                          gated: gated, doorway: door)
    }

    /// The Watch's doorway over the camera's curve, with ONE difference: a
    /// doorway must begin inside the trusted first 90 s. The Watch also admits
    /// a later start when the stretch's clarity clears 0.85, a bar wrist sway
    /// never reached across 227 drift sessions. Camera sway does reach it:
    /// IMG_9543 minute 19 read a rock-steady 4.5/min at clarity 1.00 that the
    /// wrist beside it did not see. The admission bar was a wrist measurement
    /// and does not transfer, so it is switched off here (`lateClarity:
    /// .infinity`), and the five-minute cap becomes moot.
    static func doorway(rates: [Double], clarities: [Double],
                        windowSec: Int, hopSec: Int) -> SignalEngine.BreathDoorway? {
        SignalEngine.breathDoorway(rates: rates, clarities: clarities,
                                   windowSec: windowSec, hopSec: hopSec,
                                   clarityFloor: readClarity,
                                   lateClarity: .infinity)
    }

    /// Per-window DFT scan over one channel: high-pass the whole series, then
    /// per window take a straight line out and scan the band. Ported from the
    /// probe's `analyze`, windowed by TIME rather than sample index so dropped
    /// frames cannot slide the grid.
    static func windowReads(signal raw: [Double], times: [Double],
                            windows: [(lo: Double, hi: Double)],
                            windowSec: Int) -> [WindowRead] {
        guard raw.count == times.count, raw.count > 4 else {
            return windows.map { _ in .empty }
        }
        let signal = highpass(raw, samplesPerSec: sampleRate(times), seconds: highpassSec)
        let binStep = 60.0 / Double(windowSec)

        var out: [WindowRead] = []
        out.reserveCapacity(windows.count)
        var cursor = 0
        for win in windows {
            // Windows advance monotonically, so the first index can be found
            // by moving a cursor forward rather than filtering every time.
            while cursor < times.count, times[cursor] < win.lo { cursor += 1 }
            var end = cursor
            while end < times.count, times[end] < win.hi { end += 1 }
            let n = end - cursor
            guard n >= minWindowSamples else { out.append(.empty); continue }

            let t = (cursor..<end).map { times[$0] - win.lo }
            let seg = linearDetrended(Array(signal[cursor..<end]), times: t)

            func power(_ rate: Double) -> Double {
                let f = rate / 60
                var re = 0.0, im = 0.0
                for i in 0..<n {
                    let ph = 2 * Double.pi * f * t[i]
                    re += seg[i] * cos(ph); im += seg[i] * sin(ph)
                }
                return re * re + im * im
            }

            var scanRates: [Double] = [], scanPow: [Double] = []
            var rate = loRate
            while rate <= hiRate + 1e-9 { scanRates.append(rate); scanPow.append(power(rate)); rate += scanStep }
            var total = 0.0
            var bin = loRate
            while bin <= hiRate + 1e-9 { total += power(bin); bin += binStep }
            let rms = (seg.reduce(0) { $0 + $1 * $1 } / Double(n)).squareRoot()

            var maxima: [Peak] = []
            for k in scanRates.indices {
                let p = scanPow[k]
                let left = k == 0 ? -1.0 : scanPow[k - 1]
                let right = k == scanRates.count - 1 ? -1.0 : scanPow[k + 1]
                guard p > left && p >= right else { continue }
                let edge = scanRates[k] <= loRate + edgeMargin || scanRates[k] >= hiRate - edgeMargin
                maxima.append(Peak(rate: scanRates[k], clarity: edge ? 0 : (total > 0 ? p / total : 0)))
            }
            maxima.sort { $0.clarity > $1.clarity }
            let peaks = Array(maxima.prefix(trackPeaks))
            let best = peaks.first ?? Peak(rate: loRate, clarity: 0)
            out.append(WindowRead(rate: best.rate, clarity: best.clarity, amplitude: rms, peaks: peaks))
        }
        return out
    }

    /// One window's candidates from every channel: drop the floor, merge near
    /// duplicates keeping the clearer sighting.
    static func pool(_ reads: [WindowRead]) -> [Peak] {
        var all = reads.flatMap(\.peaks).filter { $0.clarity >= trackFloor }
        all.sort { $0.clarity > $1.clarity }
        var out: [Peak] = []
        for c in all where !out.contains(where: { abs($0.rate - c.rate) < candidateMerge }) {
            out.append(c)
        }
        return out
    }

    /// The price of moving the path from one rate to another between hops:
    /// `trackJumpCost` per natural-log unit of the RATIO, so a doubling costs
    /// the same wherever it happens.
    ///
    /// **It was per breath/min of DIFFERENCE, and that was the rate ceiling
    /// (Aziz's first two paired sits, 2026-09-17/18).** Moving from 5 to 18
    /// cost 5.85 against a clarity that cannot exceed 1, so the tracker
    /// refused a clear fast peak every time: at one window the camera saw
    /// 18.0/min at clarity 0.85 and chose 5.6 at 0.39. The fast rate was
    /// offered in almost every natural-breathing window; it was never taken.
    /// Breathing rates are ratio-like, not difference-like, and with the
    /// ratio cost the error in the >11/min band fell from 9.8 to 0.93 while
    /// the paced bands (0.17, 0.23) and both doorways were untouched. The
    /// result is flat across constants from 0.1 to 0.6 per nat, which says
    /// the shape was wrong, not the number; 0.45 per nat is about a third of
    /// a point per doubling. Measured in `tools/camera_lab.py`.
    static func jumpCost(from a: Double, to b: Double) -> Double {
        trackJumpCost * abs(log(max(b, 0.1) / max(a, 0.1)))
    }

    /// Viterbi over the pooled candidates: clarity minus `jumpCost` between
    /// consecutive states. A gated or empty window costs one hop, not one per
    /// window skipped: missing evidence is not evidence of a jump. Windows
    /// with no path get rate 0 and clarity 0.
    static func trackRates(_ windows: [[Peak]]) -> (rates: [Double], clarity: [Double]) {
        var dp: [[Double]] = [], back: [[(Int, Int)?]] = []
        for (i, cands) in windows.enumerated() {
            guard !cands.isEmpty else { dp.append([]); back.append([]); continue }
            let prev = (0..<i).reversed().first { !dp[$0].isEmpty }
            var row: [Double] = [], ptr: [(Int, Int)?] = []
            for c in cands {
                guard let p = prev else { row.append(c.clarity); ptr.append(nil); continue }
                var best = -Double.greatestFiniteMagnitude, arg = 0
                for (k, q) in windows[p].enumerated() {
                    let v = dp[p][k] - jumpCost(from: q.rate, to: c.rate)
                    if v > best { best = v; arg = k }
                }
                row.append(c.clarity + best)
                ptr.append((p, arg))
            }
            dp.append(row); back.append(ptr)
        }
        var rates = [Double](repeating: 0, count: windows.count)
        var clar = [Double](repeating: 0, count: windows.count)
        guard let last = dp.indices.reversed().first(where: { !dp[$0].isEmpty }) else { return (rates, clar) }
        var i = last
        var j = dp[last].indices.max(by: { dp[last][$0] < dp[last][$1] }) ?? 0
        while true {
            rates[i] = windows[i][j].rate
            clar[i] = windows[i][j].clarity
            guard let step = back[i][j] else { break }
            (i, j) = step
        }
        return (rates, clar)
    }

    // MARK: - Stillness

    /// Per-window stillness from the ROI frame difference, read against the
    /// session's own floor. `floorFromSec` excludes the pre-ROI stretch from
    /// the floor (its values are whole-frame, a different scale).
    static func stillness(motion: [Double], times: [Double],
                          windows: [(lo: Double, hi: Double)],
                          floorFromSec: Double = 0) -> [Double] {
        let floor = stillnessFloor(motion: motion, times: times, fromSec: floorFromSec)
        let means = windowMeans(motion, times: times, windows: windows)
        return means.map { m in
            let ratio = floor > 0 ? m / floor : (m > 0 ? Double.infinity : 1)
            return 1 / (1 + stillnessGain * max(0, ratio - 1))
        }
    }

    /// The `stillnessFloorPercentile` of the 5 s motion means from `fromSec`
    /// on. Falls back to the whole session when the tail is too short to
    /// hold a percentile.
    static func stillnessFloor(motion: [Double], times: [Double], fromSec: Double) -> Double {
        func fives(from start: Double) -> [Double] {
            guard let end = times.last else { return [] }
            var out: [Double] = []
            var lo = start
            var cursor = 0
            while lo + stillnessFloorSpanSec <= end + 1e-9 {
                let hi = lo + stillnessFloorSpanSec
                while cursor < times.count, times[cursor] < lo { cursor += 1 }
                var s = 0.0, n = 0
                var k = cursor
                while k < times.count, times[k] < hi { s += motion[k]; n += 1; k += 1 }
                if n > 0 { out.append(s / Double(n)) }
                lo = hi
            }
            return out
        }
        var spans = fives(from: fromSec)
        if spans.count < 10 { spans = fives(from: 0) }
        guard !spans.isEmpty else { return 0 }
        let sorted = spans.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * stillnessFloorPercentile))]
    }

    // MARK: - Filtering / stats (Foundation only)

    /// Subtract a centred moving average of `seconds`: the cheap high-pass the
    /// wrist engine uses too. Drift lives below the breathing band and would
    /// otherwise own every spectrum.
    static func highpass(_ x: [Double], samplesPerSec: Double, seconds: Double) -> [Double] {
        guard !x.isEmpty else { return x }
        let half = max(1, Int(seconds * samplesPerSec / 2))
        var out = [Double](repeating: 0, count: x.count)
        // Running sum so the whole pass is O(n) rather than O(n * window).
        var prefix = [0.0]
        prefix.reserveCapacity(x.count + 1)
        for v in x { prefix.append(prefix[prefix.count - 1] + v) }
        for i in 0..<x.count {
            let lo = max(0, i - half), hi = min(x.count - 1, i + half)
            out[i] = x[i] - (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
        return out
    }

    static func linearDetrended(_ y: [Double], times t: [Double]) -> [Double] {
        guard y.count >= 3, y.count == t.count else { return y }
        let n = Double(y.count)
        let mt = t.reduce(0, +) / n, my = y.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for i in 0..<y.count {
            let dt = t[i] - mt
            num += dt * (y[i] - my)
            den += dt * dt
        }
        guard den > 0 else { return y.map { $0 - my } }
        let slope = num / den
        return (0..<y.count).map { y[$0] - (my + slope * (t[$0] - mt)) }
    }

    static func windowMeans(_ y: [Double], times: [Double],
                            windows: [(lo: Double, hi: Double)]) -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(windows.count)
        var cursor = 0
        for win in windows {
            while cursor < times.count, times[cursor] < win.lo { cursor += 1 }
            var s = 0.0, n = 0
            var k = cursor
            while k < times.count, times[k] < win.hi { s += y[k]; n += 1; k += 1 }
            out.append(n > 0 ? s / Double(n) : 0)
        }
        return out
    }

    static func median(_ y: [Double]) -> Double {
        guard !y.isEmpty else { return 0 }
        let s = y.sorted()
        return s[s.count / 2]
    }

    static func sampleRate(_ times: [Double]) -> Double {
        guard let first = times.first, let last = times.last, last > first, times.count > 1
        else { return 10 }
        return Double(times.count - 1) / (last - first)
    }
}
