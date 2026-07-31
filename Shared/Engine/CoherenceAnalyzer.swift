import Foundation

/// Heart-rhythm coherence from a short camera-PPG snapshot (finger on the
/// iPhone camera, torch on, 60–120 s) taken BEFORE and AFTER a session. The
/// before/after differential is the no-Watch evidence path.
///
/// WHY THIS ISN'T THE DEAD-END CLAUDE.md DOCUMENTS: continuous in-session
/// coherence died because the Watch gives no beat-to-beat stream and camera
/// PPG can't run for 25 minutes. A 1–2 minute *snapshot* has neither problem:
/// short-window finger PPG recovers beat-to-beat intervals with few-ms error
/// (validated against ECG in the literature, e.g. Plews et al. 2017), and the
/// torch runs for a couple of minutes, not a session.
///
/// What is measured: how concentrated the heart-rhythm's spectral power is
/// around a single low-frequency peak (0.04–0.26 Hz). Slow regular breathing
/// near resonance (~0.1 Hz) drives the rhythm into one narrow peak → score
/// rises toward 1. An irregular, scattered rhythm spreads power → score falls
/// toward 0. This is the standard "coherence ratio" construction, described
/// by what it is (rhythm regularity at one frequency), never as a medical
/// measurement — the SCIENCE.md honesty line applies.
///
/// Pure Foundation, same conventions as SignalEngine: deterministic, no UI,
/// no sensors, and it REFUSES to emit a number from a bad signal (nil) rather
/// than inventing one.
enum CoherenceAnalyzer {

    /// One measured snapshot. All fields finite; Codable for storage.
    struct Snapshot: Codable, Equatable {
        /// 0–1: fraction of low-frequency rhythm power concentrated at the
        /// dominant peak. Higher = more coherent.
        let coherenceScore: Double
        /// Mean heart rate over the snapshot, bpm.
        let meanHR: Double
        /// Root mean square of successive beat-interval differences, ms —
        /// the standard short-window parasympathetic HRV measure.
        let rmssdMs: Double
        /// Fraction of detected beats that survived artifact rejection.
        /// Surfaced so the UI can show measurement confidence.
        let validBeatFraction: Double
    }

    // Tunables (one place, so tests and capture agree).
    // Sized for a 45 s capture: enough for ~4.5 cycles of the 0.1 Hz rhythm.
    // Shorter than ~30 s of usable beats and the LF band can't be resolved.
    static let minDurationSec = 28.0
    static let minValidBeats = 20
    static let minValidFraction = 0.7
    /// Physiologic beat-interval bounds (33–180 bpm).
    static let rrBounds = 0.33...1.8
    /// LF window searched for the dominant peak.
    static let peakBand = 0.04...0.26
    /// Integration half-width around the found peak. Matched to the spectral
    /// resolution of a ~45 s Hann-windowed snapshot (mainlobe ~0.045 Hz).
    static let peakHalfWidth = 0.025
    /// Total band the peak power is compared against.
    static let totalBand = 0.0033...0.4

    /// Analyze a raw PPG waveform (camera red-channel means) sampled uniformly.
    /// Returns nil when the signal is too short, too noisy, or too sparse to
    /// trust — the capture UI should coach and retry, never fake it.
    static func analyze(ppg: [Double], sampleRate: Double) -> Snapshot? {
        guard sampleRate > 10, ppg.count > Int(minDurationSec * sampleRate),
              ppg.allSatisfy({ $0.isFinite }) else { return nil }

        let beats = beatTimes(ppg: ppg, sampleRate: sampleRate)
        guard beats.count >= minValidBeats + 1 else { return nil }

        // Beat-to-beat intervals with artifact rejection. Each interval is
        // judged against a ROLLING MEDIAN, not its neighbor: at 30 fps one
        // slightly mis-timed peak makes one interval long and the next short,
        // and neighbor-comparison rejected both (field: 63% kept at a correct
        // beat count). Against the median, timing wobble passes while real
        // artifacts (missed beat ≈ 2×, split beat ≈ ½×) still fail loudly.
        let (rr, rejected) = filteredIntervals(beats: beats)
        let validFraction = rr.count + rejected > 0
            ? Double(rr.count) / Double(rr.count + rejected) : 0
        guard rr.count >= minValidBeats, validFraction >= minValidFraction else { return nil }

        let meanRR = rr.reduce(0) { $0 + $1.v } / Double(rr.count)
        let meanHR = 60.0 / meanRR

        // RMSSD over successive kept intervals.
        var sumSq = 0.0, nDiff = 0
        for i in 1..<rr.count {
            let d = (rr[i].v - rr[i - 1].v) * 1000
            sumSq += d * d; nDiff += 1
        }
        let rmssd = nDiff > 0 ? (sumSq / Double(nDiff)).squareRoot() : 0

        guard let score = coherenceRatio(rr: rr) else { return nil }

        let snap = Snapshot(coherenceScore: score, meanHR: meanHR,
                            rmssdMs: rmssd, validBeatFraction: validFraction)
        guard snap.coherenceScore.isFinite, snap.meanHR.isFinite,
              snap.rmssdMs.isFinite else { return nil }
        return snap
    }

    /// Shared by analyze() and diagnose(): physiologic-bounds check, then
    /// deviation-from-rolling-median (±30%) artifact rejection.
    static func filteredIntervals(beats: [Double]) -> (kept: [(t: Double, v: Double)], rejected: Int) {
        guard beats.count > 1 else { return ([], 0) }
        var raw: [(t: Double, v: Double)] = []
        var rejected = 0
        for i in 1..<beats.count {
            let v = beats[i] - beats[i - 1]
            if rrBounds.contains(v) { raw.append((beats[i], v)) } else { rejected += 1 }
        }
        guard !raw.isEmpty else { return ([], rejected) }
        let globalMedian = raw.map(\.v).sorted()[raw.count / 2]

        var kept: [(t: Double, v: Double)] = []
        var window: [Double] = []
        for (t, v) in raw {
            let median = window.isEmpty ? globalMedian : window.sorted()[window.count / 2]
            if abs(v - median) <= 0.3 * median {
                kept.append((t, v))
                window.append(v)
                if window.count > 5 { window.removeFirst() }
            } else {
                rejected += 1
            }
        }
        return (kept, rejected)
    }

    // MARK: - Beat detection

    /// Detects pulse peaks in the raw waveform: detrend with a centered moving
    /// average (kills baseline wander from finger pressure), threshold on the
    /// residual, then refine each peak with parabolic interpolation for
    /// sub-frame timing (30 fps frames are ~33 ms apart; the spectral analysis
    /// wants better than that).
    static func beatTimes(ppg: [Double], sampleRate: Double) -> [Double] {
        let n = ppg.count
        let half = max(1, Int(0.5 * sampleRate))     // ~1 s detrend window

        var prefix = [0.0]; prefix.reserveCapacity(n + 1)
        for v in ppg { prefix.append(prefix[prefix.count - 1] + v) }
        func detrended(_ i: Int) -> Double {
            let lo = max(0, i - half), hi = min(n - 1, i + half)
            let mean = (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
            return ppg[i] - mean
        }

        var resid = [Double](repeating: 0, count: n)
        for i in 0..<n { resid[i] = detrended(i) }

        // Light smoothing (~0.1 s) to knock down frame noise. Kept narrow so
        // the systolic peak stays sharp for timing — the dicrotic notch is
        // handled by the autocorrelation refractory below, not by smoothing.
        let smoothWin = max(1, Int(0.1 * sampleRate))
        if smoothWin > 1 {
            var sPrefix = [0.0]; sPrefix.reserveCapacity(n + 1)
            for v in resid { sPrefix.append(sPrefix[sPrefix.count - 1] + v) }
            for i in 0..<n {
                let lo = max(0, i - smoothWin / 2), hi = min(n - 1, i + smoothWin / 2)
                resid[i] = (sPrefix[hi + 1] - sPrefix[lo]) / Double(hi - lo + 1)
            }
        }

        let sd = standardDeviation(resid)
        guard sd > 0 else { return [] }
        let threshold = 0.3 * sd

        // Refractory from the signal's own periodicity. The dicrotic notch
        // repeats with every beat, so a fixed 0.33 s refractory can't beat it —
        // but autocorrelation sees the TRUE beat period regardless (the whole
        // waveform repeats at the heart period, echoes included). 70% of that
        // period as dead time swallows any within-beat echo no matter its
        // amplitude. Falls back to 0.33 s (≤180 bpm) when no clear period.
        let minGap: Int
        if let period = dominantPeriod(resid, sampleRate: sampleRate) {
            minGap = Int(min(1.3, max(0.33, 0.7 * period)) * sampleRate)
        } else {
            minGap = Int(0.33 * sampleRate)
        }
        var times: [Double] = []
        var lastPeak = -minGap
        var i = 1
        while i < n - 1 {
            if resid[i] > threshold, resid[i] >= resid[i - 1], resid[i] > resid[i + 1],
               i - lastPeak >= minGap {
                // Parabolic refinement around the sample-peak.
                let y0 = resid[i - 1], y1 = resid[i], y2 = resid[i + 1]
                let denom = y0 - 2 * y1 + y2
                let delta = denom != 0 ? 0.5 * (y0 - y2) / denom : 0
                times.append((Double(i) + max(-0.5, min(0.5, delta))) / sampleRate)
                lastPeak = i
            }
            i += 1
        }

        // False-peak merge: an interval far shorter than the local rhythm
        // whose neighbor sums back to one normal interval is a single beat
        // split by a spurious detection — remove the intruding peak instead
        // of letting the artifact filter discard both halves downstream.
        if times.count >= 4 {
            let rrs = zip(times.dropFirst(), times).map { $0 - $1 }
            let median = rrs.sorted()[rrs.count / 2]
            if median > 0 {
                var k = 0
                while k < times.count - 2 {
                    let a = times[k + 1] - times[k]
                    let b = times[k + 2] - times[k + 1]
                    if (a < 0.6 * median || b < 0.6 * median),
                       abs((a + b) - median) < 0.35 * median {
                        times.remove(at: k + 1)
                    } else {
                        k += 1
                    }
                }
            }
        }
        return times
    }

    // MARK: - Spectral coherence

    /// Coherence ratio: resample the RR tachogram to an even 4 Hz grid, Hann
    /// window, scan the spectrum by direct DFT (same approach as
    /// SignalEngine's fractional-rate scan), and return peak-band power over
    /// total-band power.
    private static func coherenceRatio(rr: [(t: Double, v: Double)]) -> Double? {
        guard let first = rr.first?.t, let last = rr.last?.t, last - first > 20 else { return nil }
        let fs = 4.0
        let count = Int((last - first) * fs)
        guard count > 64 else { return nil }

        // Linear interpolation of RR(t) onto the even grid.
        var series = [Double](repeating: 0, count: count)
        var j = 0
        for k in 0..<count {
            let t = first + Double(k) / fs
            while j < rr.count - 2 && rr[j + 1].t < t { j += 1 }
            let (t0, v0) = rr[j], (t1, v1) = rr[j + 1]
            let frac = t1 > t0 ? (t - t0) / (t1 - t0) : 0
            series[k] = v0 + (v1 - v0) * max(0, min(1, frac))
        }

        // Remove mean, Hann window.
        let mean = series.reduce(0, +) / Double(count)
        for k in 0..<count {
            let w = 0.5 - 0.5 * cos(2 * .pi * Double(k) / Double(count - 1))
            series[k] = (series[k] - mean) * w
        }

        // Direct DFT power scan.
        func power(at f: Double) -> Double {
            var re = 0.0, im = 0.0
            for k in 0..<count {
                let phase = 2 * .pi * f * Double(k) / fs
                re += series[k] * cos(phase)
                im -= series[k] * sin(phase)
            }
            return re * re + im * im
        }

        let step = 0.002
        var freqs: [Double] = []
        var f = totalBand.lowerBound
        while f <= totalBand.upperBound { freqs.append(f); f += step }
        let powers = freqs.map(power)
        let total = powers.reduce(0, +)
        guard total > 0 else { return nil }

        // Dominant peak within the LF search band.
        var peakF = peakBand.lowerBound, peakP = -1.0
        for (idx, freq) in freqs.enumerated() where peakBand.contains(freq) {
            if powers[idx] > peakP { peakP = powers[idx]; peakF = freq }
        }
        guard peakP > 0 else { return nil }

        var peakPower = 0.0
        for (idx, freq) in freqs.enumerated() where abs(freq - peakF) <= peakHalfWidth {
            peakPower += powers[idx]
        }
        return max(0, min(1, peakPower / total))
    }

    /// Walks the same pipeline as `analyze` and reports what each gate saw —
    /// so a failed read on a device can say WHY without a debugger attached.
    static func diagnose(ppg: [Double], sampleRate: Double) -> String {
        guard sampleRate > 10 else { return "fps too low (\(String(format: "%.1f", sampleRate)))" }
        guard ppg.allSatisfy({ $0.isFinite }) else { return "non-finite samples" }
        let dur = Double(ppg.count) / sampleRate
        guard dur >= minDurationSec else {
            return String(format: "too short: %.0fs < %.0fs", dur, minDurationSec)
        }
        let beats = beatTimes(ppg: ppg, sampleRate: sampleRate)
        let (rr, rejected) = filteredIntervals(beats: beats)
        let kept = rr.count
        let frac = kept + rejected > 0 ? Double(kept) / Double(kept + rejected) : 0
        let hr = kept > 0 ? 60.0 / (rr.reduce(0) { $0 + $1.v } / Double(kept)) : 0
        let base = String(format: "%.0fs @ %.1ffps · beats %d · kept %d (%.0f%%) · ~%.0f bpm",
                          dur, sampleRate, beats.count, kept, frac * 100, hr)
        if beats.count < minValidBeats + 1 { return base + " → too few beats" }
        if kept < minValidBeats { return base + " → too few clean intervals" }
        if frac < minValidFraction { return base + " → intervals too irregular (artifacts)" }
        return base + " → spectral stage"
    }

    /// Dominant periodicity of the detrended waveform within physiologic
    /// heart-rate bounds, via normalized autocorrelation. Nil when nothing in
    /// the band correlates convincingly (e.g. torch noise with no pulse).
    private static func dominantPeriod(_ x: [Double], sampleRate: Double) -> Double? {
        let n = x.count
        var energy = 0.0
        for v in x { energy += v * v }
        guard energy > 0 else { return nil }

        let minLag = Int(rrBounds.lowerBound * sampleRate)
        let maxLag = min(n - 1, Int(rrBounds.upperBound * sampleRate))
        guard maxLag > minLag else { return nil }

        var rs = [Double](repeating: 0, count: maxLag - minLag + 1)
        var bestLag = 0, bestR = 0.0
        for lag in minLag...maxLag {
            var s = 0.0
            var i = 0
            while i < n - lag { s += x[i] * x[i + lag]; i += 1 }
            let r = s / energy
            rs[lag - minLag] = r
            if r > bestR { bestR = r; bestLag = lag }
        }
        // A real pulse autocorrelates strongly at its own period; noise doesn't.
        guard bestR > 0.15, bestLag > 0 else { return nil }

        // Octave-error guard (field-found: a period of TWO beats won the scan,
        // halving the detected heart rate to ~37 bpm). If half the winning
        // period also correlates well, the half is the true beat period —
        // repeat until it no longer does.
        var lag = bestLag
        while lag / 2 >= minLag {
            let rHalf = rs[lag / 2 - minLag]
            if rHalf >= 0.6 * bestR { lag = lag / 2 } else { break }
        }
        return Double(lag) / sampleRate
    }

    private static func standardDeviation(_ x: [Double]) -> Double {
        guard x.count > 1 else { return 0 }
        let mean = x.reduce(0, +) / Double(x.count)
        let varSum = x.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (varSum / Double(x.count - 1)).squareRoot()
    }
}
