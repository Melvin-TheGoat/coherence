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

    /// A body that drifts but never breathes, optionally with a breath on top.
    ///
    /// A leaky random walk, which is what postural sway actually is: in-band,
    /// wandering, no stable rhythm. White noise is the wrong model, because its
    /// power sits above the breathing band and the filter removes it, so a
    /// "noisy" test built from white noise reads exactly as clean as a silent
    /// one. This is the signal that produces a plausible rate out of nothing.
    private func wander(dur: Double, step: Double, seed: UInt64,
                        breath: Double = 0, hz: Double = 0.1) -> [MotionSample] {
        var g = LCG(s: seed)
        var out: [MotionSample] = []
        var wp = 0.0, wr = 0.0, t = 0.0
        while t <= dur + 1e-9 {
            wp += (g.unit() - 0.5) * step
            wr += (g.unit() - 0.5) * step
            wp *= 0.999                    // a leak, so it cannot wander away
            wr *= 0.999
            out.append(MotionSample(t: t,
                                    pitch: breath * sin(2 * Double.pi * hz * t) + wp,
                                    roll: wr, userAccel: 0))
            t += 0.05
        }
        return out
    }

    /// The score this session would have had if breath had never been read.
    /// Comparing against it is how we assert "breath did not count", now that
    /// resonance is always reported as its own honest measurement and can no
    /// longer stand in for "was it scored".
    /// A little steady motion, so stillness lands mid-scale instead of a
    /// perfect 1.0.
    ///
    /// Fixtures used to pass `accel: 0`, which scores a flawless stillness, and
    /// **a binary breath term worth 1.0 cannot raise a session already at 1.0
    /// on everything else.** Three "breath reaches the score" tests were
    /// therefore comparing a number to itself and passing only because breath
    /// used to be a continuous 0.77–1.00. Any test asserting that a signal
    /// moved the score has to leave the score room to move.
    private let restingAccel: (Double) -> Double = { _ in 0.022 }   // → stillness ≈ 0.90

    /// Guards the above: fails loudly if a fixture drifts back to a perfect
    /// score, where "breath counted" is unprovable rather than false.
    private func assertNotAlreadyPerfect(_ r: SignalResult,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) {
        XCTAssertLessThan(SignalEngine.spreadStillness(r.stillnessScore ?? 1), 0.999,
                          "fixture has nothing left to gain; the assertion below is vacuous",
                          file: file, line: line)
    }

    private func scoreWithoutBreath(_ r: SignalResult, durationSec: Int) -> Double? {
        SignalEngine.score(stillnessScore: r.stillnessScore,
                           heartRateTimeseries: r.heartRateTimeseries,
                           breathDoorway: nil,
                           durationSec: durationSec)
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
    // MARK: - Wrist breathing (posture-free, calibrated from the 2026-08-07 pilot)

    /// The behavior this replaces: `test_regularSessionHasNoBreathing` asserted
    /// that a clean 6/min wave in a non-belly session was IGNORED. Since the
    /// wrist path, the same session reads it — no mode, no placement. Stillness
    /// stays "total" and the score stays 2-signal: wrist breath is evidence,
    /// never a grade.
    func test_wristSession_readsCleanSlowBreathing() {
        let m = motion(dur: 120, pitch: sine(0.1, amp: 0.1))
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNotNil(r.meanBreathingRate)
        XCTAssertEqual(r.meanBreathingRate ?? 0, 6.0, accuracy: 0.8)
        XCTAssertEqual(r.stillnessMethod, "total")
    }

    /// Wrist amplitudes are millirads and shrink WITH stillness: the pilot's
    /// cleanest wave was 2.6 mrad sd, but a genuinely settled user breathing
    /// gently measured ~1.2 mrad (live session 3) and a 1.5 mrad floor threw
    /// the session away. The floor must read the quietest real breath observed.
    func test_wristSession_readsMilliradAmplitude() {
        let m = motion(dur: 120, pitch: { _ in 0 }, roll: sine(0.1, amp: 0.0017))  // ≈1.2 mrad sd
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNotNil(r.meanBreathingRate, "the quietest observed real breath must clear the floor")
        XCTAssertEqual(r.meanBreathingRate ?? 0, 6.0, accuracy: 0.8)
    }

    // MARK: Natural-breathing second pass (provisional tuning, 2026-08-08)

    /// The case that prompted this: quiet breathing at 14/min buried under a
    /// 2.1/min drift ten times its amplitude. The first pass declines because
    /// the drift owns the peak; the second must recover the rate.
    func test_naturalBreathing_underDrift_isRecovered() {
        let breath = sine(14.0 / 60, amp: 0.0012)      // 14/min, ~0.85 mrad sd
        let drift  = sine(0.035, amp: 0.012)           // 2.1/min, 10x larger
        let m = motion(dur: 180, pitch: { breath($0) + drift($0) })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNotNil(r.meanBreathingRate, "natural breathing under drift must be read")
        XCTAssertEqual(r.meanBreathingRate ?? 0, 14.0, accuracy: 2.0)
    }

    /// Normal breathing now COUNTS, on Aziz's call. What it must not do is
    /// crater the score: resonance is a narrow bell on 6/min and would score a
    /// 14/min breath at essentially zero across 45% of the total, so someone
    /// breathing normally would rank below someone whose breath was never read.
    /// The score's curve is wide instead; resonance stays narrow and honest as
    /// its own displayed measurement.
    func test_normalBreathing_countsWithoutCrateringTheScore() {
        XCTAssertEqual(SignalEngine.breathCredit(rate: 6), 1.0, accuracy: 0.01)
        XCTAssertEqual(SignalEngine.breathCredit(rate: 10), 0.65, accuracy: 0.05)
        XCTAssertEqual(SignalEngine.breathCredit(rate: 14), 0.32, accuracy: 0.05)
        XCTAssertGreaterThan(SignalEngine.breathCredit(rate: 6),
                             SignalEngine.breathCredit(rate: 10),
                             "slower must always be worth more")
        XCTAssertGreaterThan(SignalEngine.breathCredit(rate: 10),
                             SignalEngine.breathCredit(rate: 14))
    }

    /// Deliberate slow breathing still earns resonance exactly as before. The
    /// second pass must only ever add readings the first one refused.
    func test_slowBreathing_stillEarnsResonance() {
        let m = motion(dur: 120, pitch: sine(0.1, amp: 0.1))       // 6/min
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertEqual(r.meanBreathingRate ?? 0, 6.0, accuracy: 0.8)
        XCTAssertNotNil(r.resonanceMatchScore)
        XCTAssertGreaterThan(r.resonanceMatchScore ?? 0, 0.8)
    }

    /// The guard that matters most. Drift with NO breath in it must still read
    /// as nothing after the second pass, or this change has traded honesty for
    /// coverage. Detrending removes the ramp; it must not manufacture a rhythm.
    func test_driftWithNoBreath_stillReadsNothing() {
        let m = motion(dur: 180, pitch: sine(0.035, amp: 0.02))    // drift only
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNil(r.meanBreathingRate,
                     "the natural pass must not invent a rate out of pure drift")
    }

    /// A real session that SLOWS DOWN must still be read. Verified against a
    /// capture where Aziz counted 12, 8 and 6.5 breaths a minute at minutes 1,
    /// 3 and 5: the per-window curve tracked it (12.2 → 10.4 → 8.0 → 6.6) but
    /// the old spread-only gate threw the whole session away, because a spread
    /// of 3.7 looks identical to junk if you only measure spread.
    func test_breathingThatSlowsDown_isStillRead() {
        // A chirp from 12/min down to 6/min, the shape of a real settle.
        let f0 = 12.0 / 60, f1 = 6.0 / 60, dur = 300.0
        let m = motion(dur: dur, pitch: { t in
            let k = (f1 - f0) / dur
            let phase = 2 * Double.pi * (f0 * t + 0.5 * k * t * t)
            return 0.004 * sin(phase)
        })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNotNil(r.meanBreathingRate,
                        "a breath that slows from 12 to 6 is one rhythm, not scatter")
        XCTAssertEqual(r.meanBreathingRate ?? 0, 9.0, accuracy: 2.5)
    }

    /// Aziz's call: show the user a rate even when it is only roughly right,
    /// because an empty tile is worse than an approximate number. A jumpy curve
    /// that the strict gate would have thrown away is now displayed.
    func test_jumpyCurve_isShownToTheUser() {
        let plan: [Double] = [12, 5, 14, 6, 13, 4, 15, 5, 12, 6]   // per 30 s, /min
        var phase = 0.0, last = 0.0
        func value(_ t: Double) -> Double {
            let f = plan[min(plan.count - 1, Int(t / 30))] / 60
            phase += 2 * Double.pi * f * (t - last)
            last = t
            return 0.004 * sin(phase)
        }
        let r = SignalEngine.analyze(motion: motion(dur: 300, pitch: value),
                                     hr: [], bellyBreathing: false)

        XCTAssertNotNil(r.meanBreathingRate, "a rough reading is still shown")
    }

    /// Breath counts at any RATE now, but not at any confidence. This is the
    /// guard that survives: a reading the engine does not trust must leave the
    /// score exactly where an unread breath would.
    ///
    /// The input is a body that drifts and never breathes. It still produces a
    /// number, because a wandering signal always has a strongest frequency
    /// somewhere, and this is not hypothetical: a real session Aziz confirmed
    /// had no breathing in it reads 8.5/min. Two seeds, because one lucky draw
    /// proves nothing about a random walk.
    func test_driftWithNoBreathIsShownButNeverScored() {
        for seed in [UInt64(7), 3] {
            let m = wander(dur: 240, step: 0.0005, seed: seed)
            let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

            XCTAssertNotNil(r.meanBreathingRate,
                            "the curve is still shown, so a bad read stays visible")
            XCTAssertEqual(r.overallScore ?? -1,
                           scoreWithoutBreath(r, durationSec: 240) ?? -2, accuracy: 0.0001,
                           "seed \(seed): a rhythm read out of drift must not move the score")
        }
    }

    /// The same drift, with a real breath in it, must still score.
    ///
    /// Together with the test above this is the whole claim: the gate rejects
    /// the absence of breathing, not the presence of movement. A gate that
    /// refused both would be safe and useless.
    func test_breathUnderHeavyDriftStillScores() {
        let m = wander(dur: 240, step: 0.0005, seed: 7, breath: 0.004)
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertEqual(r.meanBreathingRate ?? 0, 6.0, accuracy: 0.5)
        XCTAssertNotEqual(r.overallScore ?? -1,
                          scoreWithoutBreath(r, durationSec: 240) ?? -1,
                          "a real breath under drift must reach the score")
    }

    /// A clean, coherent, deliberately slow breath still earns its resonance.
    func test_confidentSlowBreathing_stillScores() {
        let r = SignalEngine.analyze(motion: motion(dur: 180, pitch: sine(0.1, amp: 0.1)),
                                     hr: [], bellyBreathing: false)

        XCTAssertEqual(r.meanBreathingRate ?? 0, 6.0, accuracy: 0.8)
        XCTAssertNotNil(r.resonanceMatchScore, "a confident slow read must still score")
    }

    /// Sensor noise alone is not breathing at any tuning.
    func test_noiseAlone_readsNothing() {
        var seed = 20260808
        func noise() -> Double {
            seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
            return (Double(seed) / Double(0x7fffffff) - 0.5) * 0.0004
        }
        let m = motion(dur: 180, pitch: { _ in noise() })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNil(r.meanBreathingRate, "noise must never read as a breath")
    }

    /// Settling drift (~2/min) was the dominant slow signal in every pilot
    /// capture. The wrist band's 0.05 Hz floor excludes it: drift alone must
    /// produce NO breathing, not a fake slow rate.
    func test_wristSession_settlingDriftReadsNothing() {
        let m = motion(dur: 120, pitch: sine(0.035, amp: 0.02))   // 2.1/min "drift"
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNil(r.meanBreathingRate, "settling drift must not read as breath")
        XCTAssertTrue(r.breathingRateTimeseries.isEmpty)
    }

    /// A slow arm reposition mid-session: elevated (but not spiky) accel with a
    /// big slow tilt excursion. Measured in the pilot at only ~1.6× the median
    /// window accel — the relative gate must zero those windows while the
    /// surrounding breath keeps its rate.
    func test_wristSession_armShiftIsGatedNotMisread() {
        let shift: (Double) -> Bool = { (60...80).contains($0) }
        let m = motion(
            dur: 180,
            pitch: { t in sine(0.1, amp: 0.006)(t) + (shift(t) ? 0.08 * sin((t - 60) / 20 * .pi) : 0) },
            accel: { t in shift(t) ? 0.012 : 0.004 }
        )
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNotNil(r.meanBreathingRate)
        XCTAssertEqual(r.meanBreathingRate ?? 0, 6.0, accuracy: 0.9,
                       "the shift must be excluded, not averaged into the rate")
    }

    /// A breath whose rate DRIFTS must still read. Regression for the first
    /// live session after the pilot: a real user's slow breathing sped from
    /// ~6.5 to ~9.5/min across one minute, every window read cleanly, and the
    /// whole-file concentration gate — which assumes a stationary rate — threw
    /// the session away because the drifting peak was smeared. That gate is
    /// gone; this pins its absence.
    func test_wristSession_driftingRateStillReads() {
        // Linear chirp 0.1 → 0.16 Hz (6 → 9.6/min): phase = 2π(f0·t + k/2·t²).
        let f0 = 0.1, k = (0.16 - 0.1) / 120.0
        let m = motion(dur: 120, pitch: { t in 0.006 * sin(2 * .pi * (f0 * t + k / 2 * t * t)) })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNotNil(r.meanBreathingRate, "a drifting breath must not be rejected wholesale")
        XCTAssertEqual(r.meanBreathingRate ?? 0, 7.8, accuracy: 1.2,
                       "mean should land mid-drift")
    }

    /// Breath readable in only part of the session is shown, because seeing the
    /// curve is what lets us tune the engine. It does not reach the score.
    /// THE POINT OF THE DOORWAY MODEL. Three minutes of slow breathing at the
    /// start of a five-minute sit, silence after. Coverage is well under the
    /// old 60% bar, so this used to score nothing at all — the app punished
    /// someone for doing exactly what it asks.
    func test_slowOpeningThenSilence_scoresTheDoorway() {
        let m = motion(dur: 300, pitch: { t in t < 180 ? sine(0.1, amp: 0.006)(t) : 0 },
                       accel: restingAccel)
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertEqual(r.breathDoorwayRate ?? 0, 6.0, accuracy: 1.0,
                       "the opening is the doorway")
        assertNotAlreadyPerfect(r)
        XCTAssertGreaterThan(r.overallScore ?? -1,
                             scoreWithoutBreath(r, durationSec: 300) ?? 2,
                             "a real slow opening must reach the score")
    }

    /// Too brief to be a rhythm.
    ///
    /// Note the bleed: a 30 s window centred on a burst still contains it, so
    /// a stretch of breathing reads across roughly `windowSec` more than it
    /// lasted. 45 s of breath therefore yields the seven windows the floor
    /// asks for, quite legitimately — two disjoint 30 s observations really do
    /// exist inside it. Twenty seconds cannot reach that however it is sliced.
    func test_briefSlowStretch_isShownButTooShortToScore() {
        let m = motion(dur: 180, pitch: { t in t < 20 ? sine(0.1, amp: 0.006)(t) : 0 })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNil(r.breathDoorwayRate, "20 s is not a held rhythm")
        XCTAssertEqual(r.overallScore ?? -1,
                       scoreWithoutBreath(r, durationSec: 180) ?? -2, accuracy: 0.0001)
    }

    /// The founder's insight, as an assertion: a session that opens slow and
    /// then breathes naturally is scored on the opening, not on the average of
    /// the two. The mean here is ~9; the doorway is ~6.
    func test_doorwayIsTheSlowStretchNotTheSessionMean() {
        let m = motion(dur: 420, pitch: { t in
            t < 180 ? sine(0.1, amp: 0.006)(t)      // 6/min doorway
                    : sine(0.2, amp: 0.006)(t)      // 12/min natural
        })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertEqual(r.breathDoorwayRate ?? 0, 6.0, accuracy: 1.2)
        XCTAssertGreaterThan(r.meanBreathingRate ?? 0, r.breathDoorwayRate ?? 99,
                             "the session mean must sit above the doorway here")
    }

    /// Breathing normally after the doorway must never cost anything. If it
    /// could, the app would be asking people to pace themselves for the whole
    /// session, which is biofeedback rather than meditation.
    func test_naturalPhaseAfterTheDoorwayNeverLowersTheScore() {
        let opening = motion(dur: 240, pitch: sine(0.1, amp: 0.006))
        let both = motion(dur: 600, pitch: { t in
            t < 240 ? sine(0.1, amp: 0.006)(t) : sine(0.2, amp: 0.006)(t)
        })
        let a = SignalEngine.analyze(motion: opening, hr: [], bellyBreathing: false)
        let b = SignalEngine.analyze(motion: both, hr: [], bellyBreathing: false)

        XCTAssertNotNil(a.breathDoorwayRate)
        XCTAssertNotNil(b.breathDoorwayRate)
        XCTAssertEqual(SignalEngine.score(stillnessScore: 0.9, heartRateTimeseries: [],
                                          breathDoorway: a.breathDoorwayRate.map { _ in
                                              SignalEngine.BreathDoorway(rate: a.breathDoorwayRate!,
                                                                         heldSec: 120, startSec: 0) },
                                          durationSec: 600) ?? -1,
                       SignalEngine.score(stillnessScore: 0.9, heartRateTimeseries: [],
                                          breathDoorway: b.breathDoorwayRate.map { _ in
                                              SignalEngine.BreathDoorway(rate: b.breathDoorwayRate!,
                                                                         heldSec: 120, startSec: 0) },
                                          durationSec: 600) ?? -2,
                       accuracy: 0.0001,
                       "the doorway's worth cannot depend on what followed it")
    }

    /// Above 9/min nobody is deliberately slowing down, so there is no doorway
    /// and breath simply leaves the score. Crucially it must not LOWER it:
    /// detecting someone's ordinary breathing is not a fault of theirs.
    func test_naturalBreathingOnlyEarnsNothingAndCostsNothing() {
        let m = motion(dur: 300, pitch: sine(0.2, amp: 0.006))   // 12/min throughout
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNil(r.breathDoorwayRate, "12/min is not a doorway")
        XCTAssertEqual(r.overallScore ?? -1,
                       scoreWithoutBreath(r, durationSec: 300) ?? -2, accuracy: 0.0001)
    }

    /// Not "slowest wins" but "closest to 6 wins". A postural sway is slower
    /// than a real doorway, and `breathCredit` peaking at 6 is what stops the
    /// search rewarding it.
    func test_swayAtFourAMinuteDoesNotOutscoreBreathAtSix() {
        XCTAssertLessThan(SignalEngine.breathCredit(rate: 4.0),
                          SignalEngine.breathCredit(rate: 6.0))
        XCTAssertLessThan(SignalEngine.breathCredit(rate: 2.0),
                          SignalEngine.breathCredit(rate: 4.0))
    }

    /// Held, not accumulated. Four twenty-second touches of 6/min total eighty
    /// seconds of breathing and are still not a doorway.
    ///
    /// The gaps have to exceed one window or the bleed described above merges
    /// the bursts into a single continuous read — which would be the honest
    /// answer anyway, since a window straddling two bursts genuinely contains
    /// breathing throughout.
    func test_doorwayRequiresContiguityNotTotalReadableTime() {
        let m = motion(dur: 480, pitch: { t in
            t.truncatingRemainder(dividingBy: 120) < 20 ? sine(0.1, amp: 0.006)(t) : 0
        })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)
        XCTAssertNil(r.breathDoorwayRate, "scattered bursts are not a held rhythm")
    }

    /// A belly user who paces 6/min must earn what a wrist user earns for the
    /// same practice. Until the doorway rework the belly path never assigned a
    /// scored rate at all, so opting into the mode silently cost 45% of the
    /// score.
    func test_bellySession_doorwayReachesTheScore() {
        let m = motion(dur: 240, pitch: sine(0.1, amp: 0.1), accel: restingAccel)
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: true)

        XCTAssertEqual(r.breathDoorwayRate ?? 0, 6.0, accuracy: 1.0)
        assertNotAlreadyPerfect(r)
        XCTAssertGreaterThan(r.overallScore ?? -1,
                             scoreWithoutBreath(r, durationSec: 240) ?? 2,
                             "belly breathing must reach the score like wrist does")
    }

    /// Slow breathing late in a long session earns nothing.
    ///
    /// **No capture can test this** — every one we own is under five minutes,
    /// so the constraint is a design decision rather than a measured one, and
    /// this is the only thing pinning it. The reasoning: slow breathing is an
    /// entry technique, so pacing at minute fourteen is someone managing a
    /// number rather than meditating, and the effort of doing it costs them
    /// the state being scored.
    func test_lateSlowBreathingIsNotADoorway() {
        let m = motion(dur: 1200, pitch: { t in
            t > 720 && t < 900 ? sine(0.1, amp: 0.006)(t) : 0
        }, accel: restingAccel)
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNil(r.breathDoorwayRate,
                     "a stretch beginning at minute 12 is not an opening")
        XCTAssertEqual(r.overallScore ?? -1,
                       scoreWithoutBreath(r, durationSec: 1200) ?? -2, accuracy: 0.0001,
                       "late pacing must not reach the score")
    }

    /// The identical breathing, moved to the start, must score. Without this
    /// the test above could pass because the fixture never reads at all.
    func test_theSameStretchAtTheStartIsADoorway() {
        let m = motion(dur: 1200, pitch: { t in
            t < 180 ? sine(0.1, amp: 0.006)(t) : 0
        }, accel: restingAccel)
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertEqual(r.breathDoorwayRate ?? 0, 6.0, accuracy: 1.0)
        assertNotAlreadyPerfect(r)
        XCTAssertGreaterThan(r.overallScore ?? -1,
                             scoreWithoutBreath(r, durationSec: 1200) ?? 2)
    }

    /// Breath is BINARY: a doorway is worth the same whatever its rate.
    ///
    /// A doorway can only exist between 3.5 and 9 breaths/min, and across that
    /// whole reachable slice the old curve spanned 0.77 to 1.00 — under two
    /// points of a 20-minute score for any realistic rate. Meanwhile the binary
    /// "did they deliberately slow down" was right on 14 of 14 captures while
    /// the rate itself carries ±0.3/min at best. Score what the instrument
    /// measures well.
    func test_doorwayRateDoesNotChangeWhatItIsWorth() {
        let hr = (0..<20).map { 78.0 - Double($0) * 0.4 }
        let scores = [4.0, 5.0, 6.0, 7.5, 8.9].map {
            SignalEngine.score(stillnessScore: 0.9, heartRateTimeseries: hr,
                               breathDoorway: .init(rate: $0, heldSec: 90, startSec: 10),
                               durationSec: 1200) ?? -1
        }
        for v in scores {
            XCTAssertEqual(v, scores[0], accuracy: 0.0001,
                           "every legal doorway rate is worth the same")
        }
        XCTAssertGreaterThan(scores[0],
                             SignalEngine.score(stillnessScore: 0.9, heartRateTimeseries: hr,
                                                breathDoorway: nil,
                                                durationSec: 1200) ?? 2)
    }

    /// Breath is the SMALLEST term, and absent breath is unchanged.
    ///
    /// Two properties, both deliberate. A session with a doorway but a climbing
    /// heart and poor stillness must still read as the poor session it was: at
    /// the old .45 it scored 51, which looks mediocre rather than bad. And a
    /// silent session must score EXACTLY what it scored before breath was
    /// demoted, so that demoting it moves nothing in an existing history except
    /// the sessions that actually found a doorway.
    func test_breathCannotCarryASessionTheOtherSignalsRefuse() {
        let climbing = (0..<20).map { 70.0 + Double($0) * 0.26 }
        let withDoorway = SignalEngine.score(
            stillnessScore: 0.82, heartRateTimeseries: climbing,
            breathDoorway: .init(rate: 6, heldSec: 90, startSec: 5),
            durationSec: 1200) ?? -1
        XCTAssertLessThan(withDoorway, 0.35,
                          "a restless sit with a rising heart stays a bad session")

        // Absent breath: 0.60 heart / 0.40 stillness, the split it always had.
        let calm = (0..<20).map { 74.0 - Double($0) * 0.5 }
        let silent = SignalEngine.score(stillnessScore: 0.9, heartRateTimeseries: calm,
                                        breathDoorway: nil, durationSec: 1200) ?? -1
        let expected = 0.60 * (SignalEngine.heartSettling(calm) ?? 0)
                     + 0.40 * SignalEngine.spreadStillness(0.9)
        XCTAssertEqual(silent, expected, accuracy: 0.0001,
                       "silent sessions must not move when breath is demoted")
    }

    /// The score must be recomputable from what a stats row stores, or no
    /// migration can ever reproduce it. This is why per-window clarity is
    /// persisted rather than recomputed.
    func test_scoreIsRecomputableFromStoredFields() {
        let m = motion(dur: 300, pitch: sine(0.1, amp: 0.006))
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        let rebuilt = SignalEngine.breathDoorway(rates: r.breathingRateTimeseries,
                                                 clarities: r.breathClarityTimeseries,
                                                 windowSec: r.windowSec, hopSec: r.hopSec)
        XCTAssertEqual(rebuilt?.rate ?? -1, r.breathDoorwayRate ?? -2, accuracy: 0.0001,
                       "stored fields must rebuild the doorway exactly")
    }

    /// A rate that genuinely changes, read clearly throughout, now DOES score.
    ///
    /// This reverses an earlier rule and the reversal is deliberate. Disjoint
    /// plateaus were treated as the signature of a misread, and the score gate
    /// refused any curve too spread out to be one steady rate. But a verified
    /// capture ran 12 to 6.5 breaths/min inside five minutes, so "the rate
    /// moved" is not evidence of anything, and the rule was refusing real
    /// sessions to catch bad ones. What actually separates them is clarity, so
    /// that is what the gate reads now. A misread is unclear, whatever shape it
    /// draws: see test_driftWithNoBreathIsShownButNeverScored.
    func test_wristSession_clearlyChangingRateStillScores() {
        let m = motion(dur: 180, pitch: { t in
            let hz = t < 60 ? 0.075 : (t < 120 ? 0.145 : 0.075)   // 4.5 vs 8.7/min
            return 0.004 * sin(2 * .pi * hz * t)
        }, accel: restingAccel)
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNotNil(r.meanBreathingRate)
        assertNotAlreadyPerfect(r)
        XCTAssertGreaterThan(r.overallScore ?? -1,
                             scoreWithoutBreath(r, durationSec: 180) ?? 2,
                             "a clear read is a read, whether or not the rate held still")
    }

    /// The 9/min case (live session 5): faster deliberate breathing is
    /// shallower, so sub-millirad amplitude with only-moderate clarity on one
    /// axis must still read — the counted rate was dead on the pitch track.
    func test_wristSession_nineAMinuteShallowReads() {
        let m = motion(dur: 120, pitch: sine(0.15, amp: 0.0009))   // 9/min, ~0.6 mrad sd
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNotNil(r.meanBreathingRate, "shallow 9/min must clear the floor")
        XCTAssertEqual(r.meanBreathingRate ?? 0, 9.0, accuracy: 1.0)
    }

    /// A steady breath under an intermittent louder intruder.
    ///
    /// This is the failure the tracker exists for. A 6/min breath runs the whole
    /// session; a stronger 11/min oscillation cuts in and out. Window by window
    /// the intruder is the clearest peak wherever it is present, so an argmax
    /// read hops onto it and the curve reports two rhythms. Reading the sequence
    /// as a whole, the breath is the only candidate that is there every window,
    /// and continuity is what makes that count as evidence.
    func test_wristSession_steadyBreathBeatsAnIntermittentLouderRhythm() {
        let m = motion(dur: 240, pitch: { t in
            let breath = 0.003 * sin(2 * .pi * 0.1 * t)
            let bursts = (t > 40 && t < 80) || (t > 130 && t < 170)
            return breath + (bursts ? 0.006 * sin(2 * .pi * 0.183 * t) : 0)
        })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertEqual(r.meanBreathingRate ?? 0, 6.0, accuracy: 1.0,
                       "the rhythm present throughout is the breath, "
                       + "even where a louder one is briefly clearer")
    }

    /// Deep slow breathing is not a sine wave, and its second harmonic is loud.
    ///
    /// Measured on a counted 2-minute session at 4.5/min: the harmonic reached
    /// 0.74 of the fundamental's power in the first half, and the per-window
    /// argmax hopped onto it for five straight windows, reporting 5.7/min
    /// against a counted 4.5 then 5. The tracker reads 4.6, because only the
    /// fundamental is there in every window. Note there is no harmonic rule in
    /// the engine: continuity alone resolves it, which is why this is not the
    /// camera path's explicit octave guard.
    func test_wristSession_deepBreathIsReadAtItsFundamentalNotItsHarmonic() {
        // Asymmetric breath: quick in, slow out. The shape that puts energy at
        // 2f, with the harmonic deliberately louder than the fundamental.
        let f = 0.075                                     // 4.5/min
        let m = motion(dur: 180,
                       pitch: { t in 0.003 * sin(2 * .pi * f * t) },
                       roll: { t in 0.003 * sin(2 * .pi * f * t)
                                  + 0.005 * sin(4 * .pi * f * t) })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertEqual(r.meanBreathingRate ?? 0, 4.5, accuracy: 1.0,
                       "a loud second harmonic must not be mistaken for the rate")
    }

    /// A smooth curve is not evidence, and the gate must not treat it as any.
    ///
    /// The drift-only signals produce tidy curves: one holds 7/min for fifteen
    /// windows then 4/min for twenty, the other sits on 8/min almost
    /// throughout. Under a gate that asked how little the rate moved, both
    /// scored, and so did a real session with no breathing in it. They cannot
    /// now, and the reason they cannot is worth stating: the tracker's own job
    /// is to make the curve as smooth as the evidence allows, so smoothness is
    /// partly its output and gating on it would be circular. Clarity runs the
    /// other way. Choosing each window's clearest peak maximises mean clarity
    /// by construction, so the tracker can only ever spend it.
    func test_smoothnessAloneDoesNotReachTheScore() {
        let m = wander(dur: 240, step: 0.001, seed: 3)
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        let live = r.breathingRateTimeseries.filter { $0 > 0 }.sorted()
        XCTAssertFalse(live.isEmpty, "this input does produce a curve")
        let spread = live[(live.count * 3) / 4] - live[live.count / 4]
        XCTAssertLessThan(spread, 2.0, "and the curve really is tidy")

        XCTAssertEqual(r.overallScore ?? -1,
                       scoreWithoutBreath(r, durationSec: 240) ?? -2, accuracy: 0.0001,
                       "tidy is not the same as true")
    }

    /// Breath now counts (45% when read), so the old "never moves the score"
    /// rule is gone by design. What replaces it is the property that rule
    /// existed to protect: **absence must not penalise.** A session with no
    /// readable breath is scored on the two signals it did produce, via
    /// renormalised weights, not docked 45 points for a measurement we
    /// couldn't take.
    func test_wristBreathing_absenceRenormalisesRatherThanPenalises() {
        // A heart that settles for half the session and drifts back up for the
        // rest, so neither session sits at the ceiling — with everything
        // perfect there is no headroom left for breath to show in.
        // Twenty minutes, so the duration ceiling is 1.0 and this test is
        // isolating depth rather than re-testing the time multiplier.
        let hrs = hr(dur: 1200) { t in t < 600 ? 70 : 76 }
        // Same heart, same near-total stillness. One breathes at resonance;
        // the other's breath is simply unreadable.
        let withBreath = SignalEngine.analyze(
            motion: motion(dur: 1200, pitch: sine(0.1, amp: 0.004), accel: { _ in 0.002 }),
            hr: hrs, bellyBreathing: false)
        let withoutBreath = SignalEngine.analyze(
            motion: motion(dur: 1200, pitch: { _ in 0 }, accel: { _ in 0.002 }),
            hr: hrs, bellyBreathing: false)

        XCTAssertNotNil(withBreath.meanBreathingRate)
        XCTAssertNil(withoutBreath.meanBreathingRate)

        // The no-breath session must still score like the good sit it is.
        XCTAssertGreaterThan(withoutBreath.overallScore ?? 0, 0.5,
                             "a missing signal must not be scored as a failed one")
        // And resonance breathing is real evidence of settling, so it earns more.
        XCTAssertGreaterThan(withBreath.overallScore ?? 0, withoutBreath.overallScore ?? 0)
    }
}

// MARK: - Score v3

/// The score's contract, in the words the app uses: how deep the body got, and
/// how long it held it. These lock the properties that make that sentence true.
extension SignalEngineTests {

    /// Time is a CEILING, never a bonus — the property Aziz asked for by name.
    /// Sitting restless for half an hour must score worse than five settled
    /// minutes, so duration can only ever multiply depth downward.
    func test_score_timeCapsButNeverRescues() {
        let short = SignalEngine.durationFactor(seconds: 5 * 60)
        let long = SignalEngine.durationFactor(seconds: 30 * 60)
        XCTAssertEqual(long, 1.0, accuracy: 0.001, "past 20 min the ceiling stops rising")
        XCTAssertEqual(short, 0.70, accuracy: 0.02, "a flawless 5-minute sit tops out near 70")

        // A great short session beats a poor long one.
        XCTAssertGreaterThan(0.90 * short, 0.30 * long)
    }

    func test_score_durationFloorKeepsShortSessionsCounting() {
        // "Two minutes still counts": a brief sit is scored, not crushed.
        let two = SignalEngine.durationFactor(seconds: 120)
        XCTAssertEqual(two, 0.59, accuracy: 0.03)
        XCTAssertGreaterThan(SignalEngine.durationFactor(seconds: 1), 0.39)
    }

    /// Stillness saturated in the old formula: every real session measured
    /// 0.84–0.97 while a fidgety one measured 0.22, so 55% of the score was a
    /// constant. The rescale has to restore the spread.
    func test_score_stillnessRescaleRestoresSpread() {
        let typical = SignalEngine.spreadStillness(0.86)
        let excellent = SignalEngine.spreadStillness(0.96)
        XCTAssertGreaterThan(excellent - typical, 0.4,
                             "a good sit and a great one must be far apart now")
        XCTAssertEqual(SignalEngine.spreadStillness(0.31), 0, "fidgety floors at zero")
        XCTAssertEqual(SignalEngine.spreadStillness(0.99), 1)
    }

    /// The fairness fix: start-minus-end measured how wound up someone was at
    /// minute zero. A flat 68→68 session is a good sit with no room to fall and
    /// used to score zero on the heart term.
    func test_score_heartSettlingRewardsStayingCalmNotJustFalling() {
        let flat = SignalEngine.heartSettling([68, 68, 68, 68, 68, 68])
        let falling = SignalEngine.heartSettling([74, 72, 70, 67, 65, 63])
        let rising = SignalEngine.heartSettling([72, 75, 78, 81, 83, 84])

        // Flat-calm earns the fairness floor but not the headroom; a real
        // settle earns nearly all of it; climbing earns almost none.
        XCTAssertEqual(flat ?? 0, 0.6, accuracy: 0.02, "calm and staying calm still scores")
        XCTAssertGreaterThan(falling ?? 0, 0.9, "agitated and settling scores highest")
        XCTAssertLessThan(rising ?? 1, 0.15, "climbing does not")
        XCTAssertGreaterThan(falling ?? 0, flat ?? 1,
                             "the term must still discriminate a real drop from a flat line")
    }

    /// End to end: a restless 20-minute session must still score badly, and a
    /// settled one must beat it decisively.
    func test_score_restlessLongSessionStillScoresBadly() {
        let dur = 1200.0
        var rng = LCG(s: 7)
        let restless = motion(dur: dur, pitch: { _ in (rng.unit() - 0.5) * 0.25 },
                              accel: { _ in 0.05 })
        let settled = motion(dur: dur, pitch: sine(0.1, amp: 0.006), accel: { _ in 0.002 })
        let climbing = hr(dur: dur) { t in 72 + 12 * (t / dur) }
        let dropping = hr(dur: dur) { t in 74 - 11 * (t / dur) }

        let bad = SignalEngine.analyze(motion: restless, hr: climbing, bellyBreathing: false)
        let good = SignalEngine.analyze(motion: settled, hr: dropping, bellyBreathing: false)

        XCTAssertLessThan(bad.overallScore ?? 1, 0.35,
                          "twenty restless minutes must not buy a good score")
        XCTAssertGreaterThan(good.overallScore ?? 0, 0.65)
        XCTAssertGreaterThan((good.overallScore ?? 0) - (bad.overallScore ?? 1), 0.35)
    }
}
