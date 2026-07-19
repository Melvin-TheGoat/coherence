import XCTest
// SignalEngine + its input types are compiled into this test target via the
// Shared/ sources (see project.yml: CoherenceTests sources = [CoherenceTests, Shared]),
// so they're used directly without importing the app module.

final class SignalEngineTests: XCTestCase {

    // MARK: - Synthetic-signal builders

    /// Motion samples at `fs` Hz over `[0, dur]` (end inclusive).
    private func motion(
        dur: Double, fs: Double = 20,
        pitch: (Double) -> Double,
        roll: (Double) -> Double = { _ in 0 },
        accel: (Double) -> Double = { _ in 0 }
    ) -> [MotionSample] {
        let dt = 1 / fs
        var out: [MotionSample] = []
        var t = 0.0
        while t <= dur + 1e-9 {
            out.append(MotionSample(t: t, pitch: pitch(t), roll: roll(t), userAccel: accel(t)))
            t += dt
        }
        return out
    }

    /// HR samples at `fs` Hz over `[0, dur]` (end inclusive).
    private func hr(dur: Double, fs: Double = 1, bpm: (Double) -> Double) -> [HRSample] {
        let dt = 1 / fs
        var out: [HRSample] = []
        var t = 0.0
        while t <= dur + 1e-9 {
            out.append(HRSample(t: t, bpm: bpm(t)))
            t += dt
        }
        return out
    }

    /// Deterministic PRNG so "noisy" tests are reproducible.
    private struct LCG {
        var s: UInt64
        mutating func unit() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double(s >> 11) / Double(1 << 53)   // [0, 1)
        }
    }

    private func sine(_ hz: Double, amp: Double) -> (Double) -> Double {
        { amp * sin(2 * Double.pi * hz * $0) }
    }

    // MARK: - Tests

    /// A clean 0.1 Hz pitch (6 breaths/min) over 120 s reads ≈ 6 breaths/min with a
    /// high resonance match.
    func test_pointOneHzPitch_readsSixBreaths() {
        let m = motion(dur: 120, pitch: sine(0.1, amp: 0.1))
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: true)

        let rate = try? XCTUnwrap(r.meanBreathingRate)
        XCTAssertNotNil(rate)
        XCTAssertEqual(r.meanBreathingRate ?? 0, 6, accuracy: 0.5,
                       "0.1 Hz pitch must read ~6 breaths/min (check FFT bin→Hz mapping)")
        XCTAssertGreaterThan(r.resonanceMatchScore ?? 0, 0.9)
    }

    /// Palm-on-belly puts the oscillation in ROLL, not pitch. The engine must still
    /// read it — it analyzes the PCA axis of (pitch, roll), not pitch alone. (This
    /// is the on-device belly-nil bug: pitch-only would return nil here.)
    func test_breathingInRoll_readsSixBreaths() {
        let m = motion(dur: 120, pitch: { _ in 0 }, roll: sine(0.1, amp: 0.1))
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: true)
        XCTAssertNotNil(r.meanBreathingRate, "breathing in roll must be read, not just pitch")
        XCTAssertEqual(r.meanBreathingRate ?? 0, 6, accuracy: 0.5)
    }

    /// Oscillation split across pitch+roll (wrist at an angle) — PCA recombines the
    /// two half-amplitude axes into one full-amplitude breathing signal.
    func test_breathingDiagonalAxis_readsSixBreaths() {
        let s = sine(0.1, amp: 0.07)
        let m = motion(dur: 120, pitch: s, roll: s)
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: true)
        XCTAssertNotNil(r.meanBreathingRate)
        XCTAssertEqual(r.meanBreathingRate ?? 0, 6, accuracy: 0.5)
    }

    /// The on-device "sitting up" failure: a clean 6/min breath lands in ROLL while a
    /// large, broadband (low-concentration) postural sway dominates PITCH. PCA
    /// maximizes variance, so it locks onto the noisy pitch axis and would return nil
    /// — but the engine selects the breathing axis by *concentration*, so it reads the
    /// clean roll peak. (Reproduces the 2:34 session: pitch amp high / conc 0.26,
    /// roll conc 0.43, pca rejected.)
    func test_cleanRollUnderNoisyPitch_selectsRollAxis() {
        // Pitch: four in-band sines → high variance, power smeared across peaks (low
        // concentration). Roll: one clean 0.1 Hz breath (high concentration).
        let pitchSway: (Double) -> Double = { t in
            0.08 * (sin(2 * .pi * 0.06 * t) + sin(2 * .pi * 0.13 * t)
                  + sin(2 * .pi * 0.22 * t) + sin(2 * .pi * 0.35 * t))
        }
        let m = motion(dur: 120, pitch: pitchSway, roll: sine(0.1, amp: 0.05))
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: true)

        XCTAssertNotNil(r.meanBreathingRate,
                        "clean roll breath must be read even when pitch variance dominates (axis-by-concentration)")
        XCTAssertEqual(r.meanBreathingRate ?? 0, 6, accuracy: 0.7)
    }

    /// A slow held breath (~2/min, 0.033 Hz) is below the naive 3/min band floor —
    /// the engine must still read it, not throw it away (Phase-2 constraint).
    func test_slowHeldBreath_readsAboutTwo() {
        let m = motion(dur: 180, pitch: sine(0.0333, amp: 0.12))
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: true)
        XCTAssertNotNil(r.meanBreathingRate, "slow held breaths must not be discarded")
        XCTAssertEqual(r.meanBreathingRate ?? 0, 2, accuracy: 0.7)
    }

    /// Random pitch either fails the readability gate (weak fallback) or reads a low
    /// regularity — never a confident, regular breath.
    func test_noisyPitch_lowRegularity() {
        var rng = LCG(s: 42)
        let noise = (0...2400).map { _ in (rng.unit() - 0.5) * 0.2 }   // ±0.1 rad
        let m = motion(dur: 120, pitch: { t in noise[min(Int(t * 20), noise.count - 1)] })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: true)

        let fellBack = r.meanBreathingRate == nil
        let lowRegularity = (r.breathingRegularity ?? 1) < 0.6
        XCTAssertTrue(fellBack || lowRegularity,
                      "noise must not produce a confident, regular breathing read")
    }

    /// Strong belly oscillation with no gross movement → high stillness (the
    /// breathing band is excluded, so it isn't counted as restlessness).
    func test_bellyBreathingHighStillness() {
        let m = motion(dur: 120, pitch: sine(0.1, amp: 0.15))   // userAccel = 0
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: true)

        XCTAssertEqual(r.stillnessMethod, "breathingExcluded")
        XCTAssertGreaterThan(r.stillnessScore ?? 0, 0.8,
                             "deep belly breathing (no other motion) should score very still")
    }

    /// The SAME oscillation in regular mode scores LOWER stillness — proof the branch
    /// actually changes the calculation (total motion counts the oscillation).
    func test_sameSignalRegularModeLowerStillness() {
        let pitch = sine(0.1, amp: 0.15)
        let belly = SignalEngine.analyze(motion: motion(dur: 120, pitch: pitch), hr: [], bellyBreathing: true)
        let regular = SignalEngine.analyze(motion: motion(dur: 120, pitch: pitch), hr: [], bellyBreathing: false)

        XCTAssertEqual(regular.stillnessMethod, "total")
        XCTAssertLessThan(regular.stillnessScore ?? 1, belly.stillnessScore ?? 0,
                          "the two stillness methods must differ; belly must not be penalized")
    }

    /// A regular session has no breathing output and scores stillness the total way.
    func test_regularSessionHasNoBreathing() {
        let m = motion(dur: 120, pitch: sine(0.1, amp: 0.1))
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertTrue(r.breathingRateTimeseries.isEmpty)
        XCTAssertTrue(r.breathDepthTimeseries.isEmpty)
        XCTAssertNil(r.meanBreathingRate)
        XCTAssertEqual(r.stillnessMethod, "total")
    }

    /// Belly mode with a flat/near-zero pitch degrades cleanly to a 2-signal result —
    /// no fabricated breathing number.
    func test_weakBellySignalFallsBack() {
        let m = motion(dur: 120, pitch: { _ in 0 })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: true)

        XCTAssertNil(r.meanBreathingRate)
        XCTAssertTrue(r.breathingRateTimeseries.isEmpty)
        XCTAssertEqual(r.stillnessMethod, "total",
                       "weak belly signal must fall back to total-motion stillness")
    }

    /// HR sliding from 75 → 60 over the session yields a ~+15 bpm decline.
    func test_hrDecline() {
        let dur = 600.0
        let h = hr(dur: dur) { 75 - 15 * ($0 / dur) }
        let m = motion(dur: dur, pitch: { _ in 0 })
        let r = SignalEngine.analyze(motion: m, hr: h, bellyBreathing: false)

        XCTAssertEqual(r.startHR ?? 0, 75, accuracy: 2.5)
        XCTAssertEqual(r.endHR ?? 0, 60, accuracy: 2.5)
        XCTAssertEqual(r.hrDecline ?? 0, 15, accuracy: 2.5)
    }

    /// The three timeseries share one length/index (breathing populated here because
    /// it's a readable belly session).
    func test_timeseriesAlignment() {
        let m = motion(dur: 120, pitch: sine(0.1, amp: 0.1))
        let h = hr(dur: 120) { 70 - 5 * ($0 / 120) }
        let r = SignalEngine.analyze(motion: m, hr: h, bellyBreathing: true)

        XCTAssertEqual(r.heartRateTimeseries.count, r.stillnessTimeseries.count)
        XCTAssertFalse(r.breathingRateTimeseries.isEmpty, "expected a readable belly session")
        XCTAssertEqual(r.breathingRateTimeseries.count, r.heartRateTimeseries.count)
    }

    /// A belly result with non-finite values (as messy real motion can produce)
    /// FAILS to JSON-encode raw — reproducing the silent belly-send bug — but the
    /// sanitized copy encodes cleanly with finite values.
    func test_sanitizeMakesResultEncodable() throws {
        var r = SignalEngine.analyze(motion: motion(dur: 120, pitch: sine(0.1, amp: 0.1)),
                                     hr: [], bellyBreathing: true)
        r.meanBreathingRate = .nan
        r.breathDepthTimeseries = [0.1, .infinity, 0.1]
        r.stillnessScore = -.infinity

        XCTAssertThrowsError(try JSONEncoder().encode(r), "raw NaN/Inf must break encoding")

        let clean = r.sanitized()
        XCTAssertNoThrow(try JSONEncoder().encode(clean))
        XCTAssertNil(clean.meanBreathingRate)                              // non-finite optional → nil
        XCTAssertNil(clean.stillnessScore)
        XCTAssertTrue(clean.breathDepthTimeseries.allSatisfy { $0.isFinite })
    }

    /// The engine's output is always finite (it sanitizes before returning), so the
    /// payload always encodes.
    func test_analyzeOutputIsFinite() {
        let r = SignalEngine.analyze(
            motion: motion(dur: 120, pitch: sine(0.1, amp: 0.1), roll: sine(0.1, amp: 0.05)),
            hr: [], bellyBreathing: true)
        let scalars = [r.meanHR] + [r.startHR, r.endHR, r.hrDecline, r.stillnessScore,
                                    r.meanBreathingRate, r.breathingRegularity,
                                    r.resonanceMatchScore, r.overallScore].compactMap { $0 }
        let all = r.heartRateTimeseries + r.stillnessTimeseries
            + r.breathingRateTimeseries + r.breathDepthTimeseries + scalars
        XCTAssertTrue(all.allSatisfy { $0.isFinite })
        XCTAssertNoThrow(try JSONEncoder().encode(r))
    }

    /// Window count = floor((totalSec - windowSec) / hopSec) + 1.
    func test_windowCount() {
        let dur = 600.0
        let m = motion(dur: dur, pitch: { _ in 0 })
        let h = hr(dur: dur) { _ in 65 }
        let r = SignalEngine.analyze(motion: m, hr: h, bellyBreathing: false, windowSec: 30, hopSec: 5)

        let expected = Int(((dur - 30) / 5).rounded(.down)) + 1   // 115
        XCTAssertEqual(expected, 115)
        XCTAssertEqual(r.heartRateTimeseries.count, expected)
    }
}
