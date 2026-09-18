import XCTest
// CameraSignal is compiled into this target via Shared/ (project.yml), like
// SignalEngine: no app import needed.

/// The camera engine on synthetic frames. Every constant in the module was
/// fixed against the two real captures (tools/camera_harness.swift); these
/// lock the SHAPE of the behaviour so a later change cannot quietly move it.
final class CameraSignalTests: XCTestCase {

    // MARK: - Synthetic frame builders

    /// Deterministic noise (SplitMix64) so a failing test fails the same way twice.
    private struct Noise {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53) * 2 - 1   // -1..1
        }
    }

    /// Frames at `fps` over `[0, dur]`. `rate(t)` is breaths/min (0 = no
    /// breathing), integrated into a phase so rate changes are continuous.
    /// `harmonic` adds a second harmonic at that fraction of the amplitude
    /// (deep breathing is asymmetric). `motion(t)` is the frame difference
    /// (x1 = a quiet body; the floor comes from the noise). `drift` is the
    /// step size of a leaky random walk added to every shift channel: the
    /// camera's postural sway, in-band and wandering, never white.
    private func frames(dur: Double, fps: Double = 10, seed: UInt64 = 7,
                        rate: (Double) -> Double,
                        amplitude: Double = 0.6, harmonic: Double = 0,
                        motion: (Double) -> Double = { _ in 1 },
                        drift: Double = 0, nan: Set<Int> = []) -> [CameraFrame] {
        var noise = Noise(state: seed)
        var out: [CameraFrame] = []
        let dt = 1 / fps
        var phase = 0.0, walk = 0.0, i = 0
        // t from the index, not accumulated: accumulated 0.1s steps drift a
        // few microseconds short of `dur` and the grid loses its last window.
        while Double(i) * dt <= dur + 1e-9 {
            let t = Double(i) * dt
            phase += 2 * Double.pi * (rate(t) / 60) * dt
            walk = 0.995 * walk + drift * noise.next()
            let breath = amplitude * (sin(phase) + harmonic * sin(2 * phase))
            let dy = breath + walk + 0.02 * noise.next()
            let dx = 0.3 * walk + 0.02 * noise.next()
            let luma = 150 + 0.4 * breath + 0.5 * walk + 0.05 * noise.next()
            let m = 0.25 * motion(t) * (1 + 0.1 * noise.next())
            let bad = nan.contains(i) ? Double.nan : 0
            out.append(CameraFrame(t: t, motion: m + bad, dy: dy + bad, dx: dx, luma: luma,
                                   rmotion: m * 1.8 + bad, rdy: dy * 1.5 + bad, rdx: dx * 1.5, rluma: luma))
            i += 1
        }
        return out
    }

    private func centre(_ i: Int) -> Double { 15 + 5 * Double(i) }

    private func readable(_ r: SignalResult) -> [Double] { r.breathingRateTimeseries.filter { $0 > 0 } }

    // MARK: - Breathing

    func test_pacedSixPerMinute_readsSixWithAnEarlyDoorwayAndAScore() {
        let r = CameraSignal.analyze(frames: frames(dur: 180, rate: { _ in 6 }, drift: 0.01))
        XCTAssertEqual(r.breathingRateTimeseries.count, 31)
        XCTAssertNotNil(r.meanBreathingRate)
        XCTAssertEqual(r.meanBreathingRate ?? 0, 6.0, accuracy: 0.3)
        let fraction = Double(readable(r).count) / Double(r.breathingRateTimeseries.count)
        XCTAssertGreaterThanOrEqual(fraction, 0.8, "a clean paced signal reads nearly every window")
        XCTAssertNotNil(r.breathDoorwayRate)
        XCTAssertEqual(r.breathDoorwayRate ?? 0, 6.0, accuracy: 0.5)
        XCTAssertLessThanOrEqual(r.breathDoorwayStartSec ?? 999, 90, "pacing from the start opens the doorway inside the trusted window")
        XCTAssertNotNil(r.overallScore)
        XCTAssertEqual(r.breathClarityTimeseries.count, r.breathingRateTimeseries.count)
    }

    func test_rateChange_curveFollowsSixThenTwelve() {
        let r = CameraSignal.analyze(frames: frames(dur: 240, rate: { $0 < 120 ? 6 : 12 }, drift: 0.01))
        for (i, rate) in r.breathingRateTimeseries.enumerated() where rate > 0 {
            if centre(i) < 95 { XCTAssertEqual(rate, 6, accuracy: 0.6, "window at \(centre(i)) s") }
            if centre(i) > 150 { XCTAssertEqual(rate, 12, accuracy: 0.8, "window at \(centre(i)) s") }
        }
        XCTAssertGreaterThan(readable(r).count, 30)
    }

    /// Deep breathing puts real power at twice the rate (measured on the wrist:
    /// the second harmonic carried 0.74 of the fundamental's power). There is
    /// no harmonic rule; continuity resolves it, because only the fundamental
    /// is present in every window.
    func test_deepBreathing_readsTheFundamentalNotItsHarmonic() {
        let r = CameraSignal.analyze(frames: frames(dur: 180, rate: { _ in 6 }, harmonic: 0.86, drift: 0.01))
        let rates = readable(r)
        XCTAssertGreaterThan(rates.count, 20)
        XCTAssertTrue(rates.filter { $0 >= 9 }.isEmpty,
                      "no window may sit on the 12/min harmonic: \(rates.map { String(format: "%.1f", $0) })")
        XCTAssertEqual(rates.reduce(0, +) / Double(rates.count), 6, accuracy: 0.5)
        XCTAssertEqual(r.breathDoorwayRate ?? 0, 6, accuracy: 0.7)
    }

    /// The motion gate: a window moving far above the session's median offers
    /// no breathing candidates, and its stillness says so too.
    func test_largeMovement_closesBreathingAndLowersStillness() {
        let burst = { (t: Double) -> Double in (100..<130).contains(t) ? 20 : 1 }
        let r = CameraSignal.analyze(frames: frames(dur: 240, rate: { _ in 6 }, motion: burst, drift: 0.01))
        for i in r.breathingRateTimeseries.indices {
            let c = centre(i)
            // Windows containing the whole burst: [lo, hi) with lo <= 100, hi >= 130.
            if c - 15 <= 100 && c + 15 >= 130 {
                XCTAssertEqual(r.breathingRateTimeseries[i], 0, "window at \(c) s is moving x20")
                XCTAssertLessThan(r.stillnessTimeseries[i], 0.3)
            }
            if c > 180 || c < 60 {
                XCTAssertGreaterThan(r.stillnessTimeseries[i], 0.85, "quiet window at \(c) s")
            }
        }
        let quietRates = r.breathingRateTimeseries.enumerated().filter { centre($0.offset) > 180 }.map(\.element).filter { $0 > 0 }
        XCTAssertGreaterThan(quietRates.count, 5)
        for q in quietRates { XCTAssertEqual(q, 6, accuracy: 0.6) }
    }

    /// Sway with NO breathing in it. A leaky random walk is the honest junk
    /// (white noise sits above the band and the filter removes it). The
    /// module makes no promise to read nothing from it; what it promises is
    /// that junk reads LESS than a breath and can never score without a
    /// doorway inside the first 90 s.
    func test_driftWithoutBreath_readsLessThanBreathing() {
        let junk = CameraSignal.analyze(frames: frames(dur: 240, seed: 11, rate: { _ in 0 }, amplitude: 0, drift: 0.06))
        let real = CameraSignal.analyze(frames: frames(dur: 240, seed: 11, rate: { _ in 6 }, drift: 0.06))
        let junkFraction = Double(readable(junk).count) / Double(max(1, junk.stillnessTimeseries.count))
        let realFraction = Double(readable(real).count) / Double(max(1, real.stillnessTimeseries.count))
        XCTAssertLessThan(junkFraction, realFraction)
        XCTAssertEqual(real.meanBreathingRate ?? 0, 6, accuracy: 0.5, "the same drift under a real breath still reads it")
    }

    // MARK: - Stillness

    func test_settleSpike_readsLowThenTheQuietSitReadsHigh() {
        let settle = { (t: Double) -> Double in t < 30 ? 18 : 1 }
        let r = CameraSignal.analyze(frames: frames(dur: 180, rate: { _ in 6 }, motion: settle))
        XCTAssertLessThan(r.stillnessTimeseries[0], 0.2, "x18 the floor is a settle, not a sit")
        XCTAssertGreaterThan(r.stillnessTimeseries.last ?? 0, 0.9)
        XCTAssertGreaterThan(r.stillnessScore ?? 0, 0.8)
    }

    /// The floor is read from frames after the ROI was fixed, because before
    /// that the ROI columns hold whole-frame values on a different scale.
    func test_stillnessFloor_ignoresThePreROIStretch() {
        let f = frames(dur: 120, rate: { _ in 6 })
        let times = f.map(\.t)
        // Pretend the first 30 s were whole-frame (much quieter than the ROI).
        let motion = f.map { $0.t < 30 ? $0.rmotion * 0.2 : $0.rmotion }
        let whole = CameraSignal.stillnessFloor(motion: motion, times: times, fromSec: 0)
        let after = CameraSignal.stillnessFloor(motion: motion, times: times, fromSec: 30)
        XCTAssertGreaterThan(after, whole * 2, "the quiet pre-ROI stretch must not set the floor")
    }

    // MARK: - Result shape and score

    func test_result_hasNoHeartAndTheCameraVersion() {
        let r = CameraSignal.analyze(frames: frames(dur: 150, rate: { _ in 6 }))
        XCTAssertTrue(r.heartRateTimeseries.isEmpty, "no series, not a series of zeros")
        XCTAssertEqual(r.meanHR, 0)
        XCTAssertNil(r.startHR); XCTAssertNil(r.endHR); XCTAssertNil(r.hrDecline)
        XCTAssertEqual(r.stillnessTimeseries.count, 25)
        XCTAssertEqual(r.breathingRateTimeseries.count, 25)
        XCTAssertEqual(r.stillnessMethod, "camera")
        XCTAssertEqual(r.windowSec, 30); XCTAssertEqual(r.hopSec, 5)
        XCTAssertTrue(r.algorithmVersion.hasPrefix(CameraSignal.versionPrefix))
        XCTAssertNil(r.breathingRegularity, "regularity is not read from a camera and is never scored")
    }

    func test_score_isBreathTwentyStillnessEightyWithADoorwayAndStillnessAloneWithout() {
        let door = SignalEngine.BreathDoorway(rate: 6, heldSec: 60, startSec: 5)
        let spread = SignalEngine.spreadStillness(0.90)
        XCTAssertEqual(CameraSignal.score(stillnessScore: 0.90, breathDoorway: door, durationSec: 600) ?? -1,
                       0.2 + 0.8 * spread, accuracy: 1e-9)
        XCTAssertEqual(CameraSignal.score(stillnessScore: 0.90, breathDoorway: nil, durationSec: 600) ?? -1,
                       spread, accuracy: 1e-9)
        XCTAssertNil(CameraSignal.score(stillnessScore: nil, breathDoorway: door, durationSec: 600))
        // The Watch's time factor, unchanged: two minutes caps at 0.6. Perfect
        // stillness so the depth term is exactly 1 whatever shape
        // `spreadStillness` takes (0.98 used to saturate under the old floor
        // rescale; under the v5.3.0 cube it is 0.941, and this line was
        // reading the rescale, not the factor).
        XCTAssertEqual(CameraSignal.score(stillnessScore: 1.0, breathDoorway: door, durationSec: 120) ?? -1,
                       0.6, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(CameraSignal.score(stillnessScore: 1.0, breathDoorway: door, durationSec: 3600) ?? 2, 1.0)
    }

    /// The worth of a forged doorway on this instrument is breathWeight times
    /// (1 - stillness): four points on a settled sit. The reason the split is
    /// not the .40/.60 a renormalised heart-less Watch formula would give.
    func test_forgedDoorway_isWorthAtMostBreathWeight() {
        for s in [0.85, 0.90, 0.95] {
            let with = CameraSignal.score(stillnessScore: s, breathDoorway: .init(rate: 6, heldSec: 60, startSec: 5), durationSec: 1200)!
            let without = CameraSignal.score(stillnessScore: s, breathDoorway: nil, durationSec: 1200)!
            XCTAssertLessThanOrEqual(with - without, CameraSignal.breathWeight * 1.02 + 1e-9)
        }
    }

    func test_tooShortSession_isBlank() {
        let r = CameraSignal.analyze(frames: frames(dur: 20, rate: { _ in 6 }))
        XCTAssertTrue(r.stillnessTimeseries.isEmpty)
        XCTAssertTrue(r.breathingRateTimeseries.isEmpty)
        XCTAssertNil(r.overallScore)
        XCTAssertNil(r.stillnessScore)
    }

    func test_nonFiniteFrames_neverReachTheResult() {
        let r = CameraSignal.analyze(frames: frames(dur: 120, rate: { _ in 6 }, nan: [400, 401, 402]))
        for v in r.stillnessTimeseries + r.breathingRateTimeseries + r.breathClarityTimeseries {
            XCTAssertTrue(v.isFinite)
        }
        XCTAssertTrue((r.stillnessScore ?? 0).isFinite)
        XCTAssertTrue((r.overallScore ?? 0).isFinite)
    }

    // MARK: - The doorway on this instrument

    /// The Watch admits a doorway starting after 90 s when its clarity clears
    /// 0.85, a bar wrist sway never reached. Camera sway reaches 1.00, so the
    /// camera refuses every late start however clear. Locked here because the
    /// Watch's own function, given the same series, would admit it.
    func test_lateDoorway_isRefusedOnTheCameraHoweverClear() {
        func series(startWindow: Int) -> (rates: [Double], clarity: [Double]) {
            var r = [Double](repeating: 0, count: 60), c = [Double](repeating: 0, count: 60)
            for i in startWindow..<(startWindow + 20) { r[i] = 6.0; c[i] = 1.0 }
            return (r, c)
        }
        let late = series(startWindow: 24)     // starts at 120 s
        XCTAssertNil(CameraSignal.doorway(rates: late.rates, clarities: late.clarity, windowSec: 30, hopSec: 5))
        XCTAssertNotNil(SignalEngine.breathDoorway(rates: late.rates, clarities: late.clarity, windowSec: 30, hopSec: 5),
                        "control: the Watch's late-clarity rule would admit this")
        let early = series(startWindow: 12)    // starts at 60 s
        let d = CameraSignal.doorway(rates: early.rates, clarities: early.clarity, windowSec: 30, hopSec: 5)
        XCTAssertEqual(d?.startSec, 60)
        XCTAssertEqual(d?.rate ?? 0, 6, accuracy: 1e-9)
    }

    func test_doorway_needsTheCameraReadFloorNotTheWristsProvisionalOne() {
        // Seven windows at clarity 0.35: above the camera's 0.30 read floor,
        // below the wrist's provisional 0.45 stretch floor.
        var r = [Double](repeating: 0, count: 30), c = [Double](repeating: 0, count: 30)
        for i in 0..<7 { r[i] = 6.0; c[i] = 0.35 }
        XCTAssertNotNil(CameraSignal.doorway(rates: r, clarities: c, windowSec: 30, hopSec: 5))
        XCTAssertNil(SignalEngine.breathDoorway(rates: r, clarities: c, windowSec: 30, hopSec: 5))
    }

    // MARK: - The ported pieces on their own

    /// Per-window winner-takes-all would hop between two peaks whose clarity
    /// alternates; the tracker holds one line, because a 6/min jump costs
    /// 2.7 and the clarity difference is 0.05.
    func test_trackRates_holdsOneLineAcrossAlternatingWinners() {
        var windows: [[CameraSignal.Peak]] = []
        for i in 0..<20 {
            let a = i % 2 == 0 ? 0.55 : 0.50, b = i % 2 == 0 ? 0.50 : 0.55
            windows.append([.init(rate: 6, clarity: a), .init(rate: 12, clarity: b)])
        }
        let (rates, clarity) = CameraSignal.trackRates(windows)
        XCTAssertEqual(Set(rates).count, 1, "one line, not a zigzag: \(rates)")
        XCTAssertEqual(clarity.filter { $0 > 0 }.count, 20)
    }

    /// THE RATE CEILING, as it appeared on Aziz's phone (2026-09-17/18, two
    /// paired sits): the path is on a slow rate, then the camera sees a
    /// clear fast peak, 18.0/min at clarity 0.85 against 5.6 at 0.39, and the
    /// old per-breath/min cost (0.45 x 12.4 = 5.6) made it refuse the jump
    /// every window for the rest of the sit. With the cost per log-ratio the
    /// jump is a third of a point and the clear peak wins.
    func test_trackRates_takesAClearFastPeakHoweverFarAway() {
        var windows: [[CameraSignal.Peak]] = []
        for _ in 0..<10 { windows.append([.init(rate: 5.6, clarity: 0.45)]) }
        for _ in 0..<10 { windows.append([.init(rate: 5.6, clarity: 0.39), .init(rate: 18.0, clarity: 0.85)]) }
        let (rates, _) = CameraSignal.trackRates(windows)
        for i in 0..<10 { XCTAssertEqual(rates[i], 5.6, "window \(i) should stay slow") }
        for i in 10..<20 { XCTAssertEqual(rates[i], 18.0, "window \(i) refused the clear fast peak: \(rates)") }
    }

    /// Breathing rates are ratio-like: a doubling costs the same wherever it
    /// happens, and 5 → 18 costs what 5 → 1.4 does. This is the property that
    /// removed the ceiling, so it is pinned.
    func test_jumpCost_isPerLogRatioNotPerDifference() {
        let d = CameraSignal.jumpCost(from: 3, to: 6)
        XCTAssertEqual(CameraSignal.jumpCost(from: 6, to: 12), d, accuracy: 1e-9)
        XCTAssertEqual(CameraSignal.jumpCost(from: 9, to: 18), d, accuracy: 1e-9)
        XCTAssertEqual(CameraSignal.jumpCost(from: 18, to: 9), d, accuracy: 1e-9, "symmetric")
        XCTAssertEqual(d, 0.45 * log(2), accuracy: 1e-9, "0.45 per nat, about a third of a point per doubling")
        XCTAssertLessThan(CameraSignal.jumpCost(from: 5, to: 18), 1.0,
                          "a clarity difference must be able to pay for any plausible jump")
    }

    /// A gap costs one hop, not one per window skipped.
    func test_trackRates_bridgesAGapWithoutStackingJumpCosts() {
        var windows: [[CameraSignal.Peak]] = []
        for i in 0..<30 {
            if (10..<20).contains(i) { windows.append([]); continue }
            windows.append([.init(rate: 6, clarity: 0.5), .init(rate: 9, clarity: 0.45)])
        }
        let (rates, clarity) = CameraSignal.trackRates(windows)
        for i in 10..<20 { XCTAssertEqual(rates[i], 0); XCTAssertEqual(clarity[i], 0) }
        XCTAssertEqual(Set(rates.filter { $0 > 0 }).count, 1)
    }

    func test_pool_dropsTheFloorAndMergesNearDuplicatesKeepingTheClearer() {
        let a = CameraSignal.WindowRead(rate: 6, clarity: 0.4, amplitude: 1,
                                        peaks: [.init(rate: 6.0, clarity: 0.4), .init(rate: 3.0, clarity: 0.05)])
        let b = CameraSignal.WindowRead(rate: 6.2, clarity: 0.6, amplitude: 1,
                                        peaks: [.init(rate: 6.2, clarity: 0.6), .init(rate: 12.0, clarity: 0.3)])
        let pooled = CameraSignal.pool([a, b])
        XCTAssertEqual(pooled, [.init(rate: 6.2, clarity: 0.6), .init(rate: 12.0, clarity: 0.3)])
    }

    /// The clarity denominator sums INDEPENDENT bins, so a clean sinusoid
    /// reads near 1 and a peak on the scan edge reads 0.
    func test_windowReads_cleanSinusoidIsClearAndEdgePeakIsZeroed() {
        let f = frames(dur: 60, rate: { _ in 6 })
        let times = f.map(\.t)
        let windows = CameraSignal.windows(totalSec: 60, windowSec: 30, hopSec: 5)
        let reads = CameraSignal.windowReads(signal: f.map(\.rdy), times: times, windows: windows, windowSec: 30)
        XCTAssertEqual(reads.count, 7)
        for r in reads {
            XCTAssertEqual(r.rate, 6, accuracy: 0.3)
            XCTAssertGreaterThan(r.clarity, 0.7)
        }
        // A 3.5/min wave sits ON the low edge: leakage by definition.
        let edge = frames(dur: 60, rate: { _ in 3.5 })
        let edgeReads = CameraSignal.windowReads(signal: edge.map(\.rdy), times: edge.map(\.t), windows: windows, windowSec: 30)
        for r in edgeReads where r.rate <= CameraSignal.loRate + CameraSignal.edgeMargin {
            XCTAssertEqual(r.clarity, 0)
        }
    }

    func test_windows_matchTheWatchGrid() {
        XCTAssertEqual(CameraSignal.windows(totalSec: 29, windowSec: 30, hopSec: 5).count, 0)
        XCTAssertEqual(CameraSignal.windows(totalSec: 30, windowSec: 30, hopSec: 5).count, 1)
        XCTAssertEqual(CameraSignal.windows(totalSec: 600, windowSec: 30, hopSec: 5).count, 115)
        let w = CameraSignal.windows(totalSec: 60, windowSec: 30, hopSec: 5)
        XCTAssertEqual(w[3].lo, 15); XCTAssertEqual(w[3].hi, 45)
    }

    func test_parseCSV_readsTheCollectorsFile() {
        let csv = """
        # session_id=ABC
        # fps=10 grid=240 camera=front preset=vga640x480
        # roi x=0.1200 y=0.2000 w=0.6000 h=0.5000
        # roi_fixed_at_sec=25.0
        t,motion,dy,dx,luma,rmotion,rdy,rdx,rluma
        0.000,0.30000,0.00000,0.00000,150.000,0.50000,0.00000,0.00000,160.000
        0.100,0.31000,0.01000,-0.00200,150.100,0.52000,0.01500,-0.00300,160.100
        garbage line
        """
        let c = CameraCapture.parse(csv: csv)
        XCTAssertEqual(c.frames.count, 2)
        XCTAssertTrue(c.hasROI)
        XCTAssertEqual(c.roiFixedAtSec, 25)
        XCTAssertEqual(c.frames[1].rdy, 0.015, accuracy: 1e-9)
        XCTAssertEqual(c.frames[1].t, 0.1, accuracy: 1e-9)
    }
}
