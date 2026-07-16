import Foundation
import CoreMotion

/// One CoreMotion device-motion sample, timestamped from the start of recording.
/// `pitch`/`roll` are attitude angles (radians); `userAccel` is the magnitude of
/// user acceleration (g), gravity removed by CoreMotion's sensor fusion.
struct MotionSample {
    let t: TimeInterval     // seconds since recording start
    let pitch: Double
    let roll: Double
    let userAccel: Double
}

/// Captures `CMDeviceMotion` on the Watch at ~20 Hz. The gravity-tilt pitch is
/// the belly-breathing signal; userAcceleration feeds stillness. Watch-only.
///
/// Runs alongside the `HKWorkoutSession` (which keeps the app foregrounded so
/// updates keep flowing). Thread-safe: the CoreMotion handler appends on a
/// background queue under a lock; `snapshot()` reads a copy.
final class MotionRecorder {

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var startTime: Date?
    private var buffer: [MotionSample] = []

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    /// Begins device-motion updates at ~20 Hz. Clears any prior buffer.
    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        lock.lock()
        buffer.removeAll(keepingCapacity: true)
        startTime = Date()
        lock.unlock()

        queue.maxConcurrentOperationCount = 1
        manager.deviceMotionUpdateInterval = 1.0 / 20.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion, let start = self.startTime else { return }
            let a = motion.userAcceleration
            let sample = MotionSample(
                t: Date().timeIntervalSince(start),
                pitch: motion.attitude.pitch,
                roll: motion.attitude.roll,
                userAccel: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            )
            self.lock.lock()
            self.buffer.append(sample)
            self.lock.unlock()
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// A thread-safe copy of all samples captured so far.
    func snapshot() -> [MotionSample] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

/// Lightweight breathing-rate estimate from the pitch signal — a Phase-2 debug
/// aid to prove the wrist-on-belly motion is real. The rigorous Accelerate-based
/// band-pass FFT lives in the Phase-3 signal engine; this is deliberately simple.
enum BreathingEstimator {

    /// Estimates breaths/min from the trailing `windowSec` of pitch samples, or
    /// nil when there's no clear oscillation (flat signal / bad placement).
    static func breathsPerMinute(_ samples: [MotionSample], windowSec: Double = 30) -> Double? {
        guard let last = samples.last else { return nil }
        let window = samples.filter { $0.t >= last.t - windowSec }
        guard window.count >= 20 else { return nil }

        let times = window.map(\.t)
        let span = times.last! - times.first!
        guard span > 10 else { return nil }   // need a few breaths' worth of time

        var pitch = window.map(\.pitch)
        detrend(&pitch, times: times)
        let smoothed = movingAverage(pitch, window: 10)   // ~0.5 s at 20 Hz

        // Amplitude guard: too flat = no breathing signal to read.
        guard standardDeviation(smoothed) > 0.01 else { return nil }   // radians

        // Count upward zero-crossings of the detrended, smoothed signal.
        var crossings = 0
        for i in 1..<smoothed.count where smoothed[i - 1] <= 0 && smoothed[i] > 0 {
            crossings += 1
        }
        guard crossings >= 1 else { return nil }

        let bpm = (Double(crossings) / span) * 60
        guard (3...30).contains(bpm) else { return nil }   // plausible breathing band
        return bpm
    }

    /// Breaths/min estimated per sliding window (0 where unreadable) — the shape
    /// of the Phase-3 `breathingRateTimeseries`, using this crude estimator.
    static func rateSeries(_ samples: [MotionSample], windowSec: Double, hopSec: Double) -> [Double] {
        guard let first = samples.first, let last = samples.last,
              (last.t - first.t) >= windowSec else { return [] }
        var out: [Double] = []
        var start = first.t
        while start + windowSec <= last.t + 0.001 {
            let window = samples.filter { $0.t >= start && $0.t < start + windowSec }
            out.append(breathsPerMinute(window, windowSec: .greatestFiniteMagnitude) ?? 0)
            start += hopSec
        }
        return out
    }

    private static func detrend(_ y: inout [Double], times t: [Double]) {
        let n = Double(y.count)
        guard n > 1 else { return }
        let meanT = t.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for i in 0..<y.count {
            num += (t[i] - meanT) * (y[i] - meanY)
            den += (t[i] - meanT) * (t[i] - meanT)
        }
        let slope = den == 0 ? 0 : num / den
        let intercept = meanY - slope * meanT
        for i in 0..<y.count { y[i] -= slope * t[i] + intercept }
    }

    private static func movingAverage(_ y: [Double], window: Int) -> [Double] {
        guard window > 1, y.count >= window else { return y }
        var out = [Double](repeating: 0, count: y.count)
        var sum = 0.0
        for i in 0..<y.count {
            sum += y[i]
            if i >= window { sum -= y[i - window] }
            out[i] = sum / Double(Swift.min(i + 1, window))
        }
        return out
    }

    private static func standardDeviation(_ y: [Double]) -> Double {
        let n = Double(y.count)
        guard n > 1 else { return 0 }
        let m = y.reduce(0, +) / n
        let v = y.reduce(0) { $0 + ($1 - m) * ($1 - m) } / n
        return v.squareRoot()
    }
}
