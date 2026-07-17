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
