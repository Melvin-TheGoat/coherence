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

    /// Breath readable in under half the windows (quiet automatic breathing in
    /// the pilot: 55–68% at best, often less) → the whole signal is dropped
    /// rather than shipping a flickering half-curve. Here: a breath that simply
    /// stops a third of the way in.
    func test_wristSession_sparseReadabilityDropsOut() {
        let m = motion(dur: 180, pitch: { t in t < 60 ? sine(0.1, amp: 0.006)(t) : 0 })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNil(r.meanBreathingRate,
                     "a breath readable in a minority of windows must say nothing")
        XCTAssertTrue(r.breathingRateTimeseries.isEmpty)
    }

    /// A session carrying two different rhythms in different stretches is not a
    /// breath track, it's junk assembling plateaus — the signature of the one
    /// live session that misread (counted 11/min, would have displayed 6.8).
    /// The rate-IQR gate must refuse it even though every window reads cleanly.
    func test_wristSession_incoherentPlateausRefused() {
        let m = motion(dur: 180, pitch: { t in
            let hz = t < 60 ? 0.075 : (t < 120 ? 0.145 : 0.075)   // 4.5 vs 8.7/min
            return 0.004 * sin(2 * .pi * hz * t)
        })
        let r = SignalEngine.analyze(motion: m, hr: [], bellyBreathing: false)

        XCTAssertNil(r.meanBreathingRate,
                     "two disjoint rhythms must not average into one fake rate")
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
