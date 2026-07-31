import XCTest

/// Synthetic-PPG verification of the camera-coherence engine, in the same
/// spirit as SignalEngineTests: generate waveforms whose ground truth is
/// known, assert the analyzer reads them correctly, and assert it refuses
/// signals it shouldn't trust.
final class CoherenceAnalyzerTests: XCTestCase {

    private let fs = 30.0   // camera frame rate

    /// Deterministic pseudo-random source (tests must not use Math.random).
    private struct LCG {
        var state: UInt64
        mutating func next() -> Double {   // uniform [0,1)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    /// Builds a PPG waveform from a beat-interval rule: each beat adds a
    /// gaussian pulse; slow baseline wander and sensor noise are layered on
    /// top so detection has to work through realistic dirt.
    private func syntheticPPG(
        durationSec: Double,
        rrForBeat: (Double) -> Double,
        noiseAmp: Double = 0.05,
        wanderAmp: Double = 0.4,
        dicrotic: Bool = false,
        alternatingAmplitude: Bool = false
    ) -> [Double] {
        var beatTimes: [Double] = []
        var t = 0.3
        while t < durationSec {
            beatTimes.append(t)
            t += rrForBeat(t)
        }
        let n = Int(durationSec * fs)
        var noise = LCG(state: 42)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let ti = Double(i) / fs
            var v = 0.0
            for (k, b) in beatTimes.enumerated() where abs(b - ti) < 0.7 {
                let amp = alternatingAmplitude && k % 2 == 1 ? 0.65 : 1.0
                let d = (ti - b) / 0.06
                v += amp * exp(-d * d)
                if dicrotic {
                    // Secondary bump ~0.35 s after systole at 40% amplitude —
                    // the real-pulse feature that double-fired the detector on
                    // device before the smoothing + merge fix.
                    let d2 = (ti - (b + 0.35)) / 0.07
                    v += amp * 0.4 * exp(-d2 * d2)
                }
            }
            v += wanderAmp * sin(2 * .pi * 0.05 * ti)          // finger-pressure drift
            v += noiseAmp * (noise.next() - 0.5)               // sensor noise
            out[i] = v
        }
        return out
    }

    /// A rhythm breathing-modulated at exactly 0.1 Hz (resonance) must score
    /// high, and the mean HR must be read accurately.
    func test_coherentRhythmScoresHigh() throws {
        let ppg = syntheticPPG(durationSec: 90, rrForBeat: { t in
            1.0 + 0.08 * sin(2 * .pi * 0.1 * t)                // 60 bpm, strong 0.1 Hz sway
        })
        let snap = try XCTUnwrap(CoherenceAnalyzer.analyze(ppg: ppg, sampleRate: fs))
        XCTAssertGreaterThan(snap.coherenceScore, 0.5)
        XCTAssertEqual(snap.meanHR, 60, accuracy: 3)
        XCTAssertGreaterThan(snap.rmssdMs, 10)                 // real variability present
    }

    /// A jittery, unmodulated rhythm must score clearly lower than the
    /// coherent one — the differential is the product.
    func test_scatteredRhythmScoresLow() throws {
        var jitter = LCG(state: 7)
        let coherent = try XCTUnwrap(CoherenceAnalyzer.analyze(
            ppg: syntheticPPG(durationSec: 90, rrForBeat: { t in
                1.0 + 0.08 * sin(2 * .pi * 0.1 * t)
            }), sampleRate: fs))
        let scattered = try XCTUnwrap(CoherenceAnalyzer.analyze(
            ppg: syntheticPPG(durationSec: 90, rrForBeat: { _ in
                0.9 + 0.2 * jitter.next()                      // broadband variability
            }), sampleRate: fs))
        XCTAssertLessThan(scattered.coherenceScore, coherent.coherenceScore - 0.15)
    }

    /// Regression for the on-device failure of 2026-07-31: a realistic pulse
    /// with a dicrotic notch (secondary bump after each systole) must not be
    /// double-counted — beat count right but 40% of intervals rejected was
    /// the exact field signature.
    func test_dicroticNotchDoesNotDoubleCount() throws {
        let ppg = syntheticPPG(durationSec: 60, rrForBeat: { t in
            0.95 + 0.05 * sin(2 * .pi * 0.1 * t)               // ~63 bpm
        }, dicrotic: true)
        let snap = try XCTUnwrap(CoherenceAnalyzer.analyze(ppg: ppg, sampleRate: fs))
        XCTAssertEqual(snap.meanHR, 63, accuracy: 4)
        XCTAssertGreaterThan(snap.validBeatFraction, 0.85)
    }

    /// Regression for the second on-device failure: alternating pulse
    /// amplitude (odd/even beats differ) made the TWO-beat lag win the
    /// autocorrelation scan — an octave error that halved the detected rate
    /// to ~37 bpm. The subharmonic check must recover the true period.
    func test_alternatingAmplitudeDoesNotHalveRate() throws {
        var rrNoise = LCG(state: 5)
        var beatIndex = 0
        let ppg = syntheticPPG(durationSec: 60, rrForBeat: { t in
            beatIndex += 1
            return 0.81 + 0.04 * sin(2 * .pi * 0.1 * t) + 0.02 * (rrNoise.next() - 0.5)
        }, dicrotic: true, alternatingAmplitude: true)
        let snap = try XCTUnwrap(CoherenceAnalyzer.analyze(ppg: ppg, sampleRate: fs))
        XCTAssertEqual(snap.meanHR, 74, accuracy: 5)
        XCTAssertGreaterThan(snap.validBeatFraction, 0.85)
    }

    /// Faster heart rate is read correctly too (80 bpm).
    func test_readsFasterHeartRate() throws {
        let ppg = syntheticPPG(durationSec: 90, rrForBeat: { t in
            0.75 + 0.05 * sin(2 * .pi * 0.1 * t)
        })
        let snap = try XCTUnwrap(CoherenceAnalyzer.analyze(ppg: ppg, sampleRate: fs))
        XCTAssertEqual(snap.meanHR, 80, accuracy: 4)
    }

    /// No pulse in the signal (noise + wander only) → nil, never a number.
    func test_pulselessSignalRefused() {
        var noise = LCG(state: 99)
        let n = Int(90 * fs)
        let junk = (0..<n).map { i -> Double in
            0.4 * sin(2 * .pi * 0.05 * Double(i) / fs) + 0.3 * (noise.next() - 0.5)
        }
        XCTAssertNil(CoherenceAnalyzer.analyze(ppg: junk, sampleRate: fs))
    }

    /// The capture window the phone actually uses (45 s) must still resolve
    /// the differential: coherent clearly above scattered.
    func test_fortyFiveSecondWindowStillDiscriminates() throws {
        var jitter = LCG(state: 7)
        let coherent = try XCTUnwrap(CoherenceAnalyzer.analyze(
            ppg: syntheticPPG(durationSec: 45, rrForBeat: { t in
                1.0 + 0.08 * sin(2 * .pi * 0.1 * t)
            }), sampleRate: fs))
        let scattered = try XCTUnwrap(CoherenceAnalyzer.analyze(
            ppg: syntheticPPG(durationSec: 45, rrForBeat: { _ in
                0.9 + 0.2 * jitter.next()
            }), sampleRate: fs))
        XCTAssertGreaterThan(coherent.coherenceScore, 0.4)
        XCTAssertGreaterThan(coherent.coherenceScore, scattered.coherenceScore + 0.1)
    }

    /// Too short to resolve the low-frequency band → nil.
    func test_shortSignalRefused() {
        let ppg = syntheticPPG(durationSec: 20, rrForBeat: { _ in 1.0 })
        XCTAssertNil(CoherenceAnalyzer.analyze(ppg: ppg, sampleRate: fs))
    }

    /// Non-finite samples (a broken capture) → nil, not a crash or a guess.
    func test_nonFiniteInputRefused() {
        var ppg = syntheticPPG(durationSec: 90, rrForBeat: { _ in 1.0 })
        ppg[100] = .nan
        XCTAssertNil(CoherenceAnalyzer.analyze(ppg: ppg, sampleRate: fs))
    }
}
