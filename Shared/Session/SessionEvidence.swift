import Foundation

/// Turns a persisted `MeditationStats` into plottable evidence series for the
/// results graphs. Pure Foundation (no SwiftUI/Charts) so the timestamp math is
/// unit-tested independently of the view.
///
/// The three timeseries share one index; point `i`'s time is the window CENTER:
/// `i*hopSec + windowSec/2` seconds from the session start. A series is included
/// only when its timeseries is non-empty — so a Regular session yields two graphs
/// (heart rate + stillness) and a Belly session three.

/// One point on an evidence graph: seconds-from-start (window center) → value.
struct EvidencePoint: Identifiable {
    let t: TimeInterval
    let value: Double
    var id: TimeInterval { t }
}

/// A single plottable signal.
struct EvidenceSeries: Identifiable {
    enum Kind: String { case heartRate, stillness, breathing }
    let kind: Kind
    let title: String
    let unit: String
    let points: [EvidencePoint]
    /// Half the analysis window, in seconds. Display only; see `smoothedPoints`.
    var halfWindowSec: Double = 15
    var id: String { kind.rawValue }

    /// The curve as drawn: a 9-point weighted moving average (≈45 s at the
    /// standard 5 s hop), display ONLY. Stored data, scores and the doorway
    /// all read `points`; nothing downstream of this is ever analysed.
    ///
    /// Why it exists: raw window-to-window jitter is measurement noise, not
    /// physiology, and drawing it at full weight made every session look
    /// twitchy (Aziz, 2026-08-14). The kernel is centred and edge-normalised,
    /// so the endpoints stay honest instead of sliding toward zero.
    var smoothedPoints: [EvidencePoint] {
        let w: [Double] = [1, 2, 3, 4, 5, 4, 3, 2, 1]
        var smoothed = points.indices.map { i in
            var num = 0.0, den = 0.0
            for (k, wt) in w.enumerated() {
                let j = i + k - 4
                guard points.indices.contains(j) else { continue }
                num += points[j].value * wt
                den += wt
            }
            return EvidencePoint(t: points[i].t, value: num / den)
        }
        // Extend the drawn curve to the span the windows actually measured.
        // A point sits at its window's CENTER, but its value describes the
        // whole window: the first window covers second 0, not second 15. On a
        // long session the missing half-window is invisible; on a 45-second
        // one it left the curve floating between 0.25 and 0.5 min of an
        // auto-fitted axis, "barely anything" (Aziz, 2026-08-29). The pads
        // carry the endpoint values sideways, claiming nothing new.
        if let first = smoothed.first, first.t > 0 {
            smoothed.insert(EvidencePoint(t: max(0, first.t - halfWindowSec),
                                          value: first.value), at: 0)
        }
        if let last = smoothed.last {
            smoothed.append(EvidencePoint(t: last.t + halfWindowSec,
                                          value: last.value))
        }
        return smoothed
    }
}

enum SessionEvidence {

    /// Builds the series from raw timeseries + window params (the unit-tested core).
    static func series(
        heartRate: [Double], stillness: [Double], breathing: [Double],
        windowSec: Int, hopSec: Int
    ) -> [EvidenceSeries] {
        let hop = Double(hopSec)
        let halfWindow = Double(windowSec) / 2
        func points(_ values: [Double]) -> [EvidencePoint] {
            values.enumerated().map { EvidencePoint(t: Double($0.offset) * hop + halfWindow, value: $0.element) }
        }
        func series(_ kind: EvidenceSeries.Kind, _ title: String, _ unit: String,
                    _ pts: [EvidencePoint]) -> EvidenceSeries {
            EvidenceSeries(kind: kind, title: title, unit: unit,
                           points: pts, halfWindowSec: halfWindow)
        }

        var out: [EvidenceSeries] = []
        if !heartRate.isEmpty {
            out.append(series(.heartRate, "Heart rate", "bpm", points(heartRate)))
        }
        if !stillness.isEmpty {
            out.append(series(.stillness, "Stillness", "", points(stillness)))
        }
        if !breathing.isEmpty {
            // Zero in the breathing series means "this window could not be
            // read", not "zero breaths a minute". Plotting it drops the line to
            // the floor and invents a collapse that never happened. Dropping
            // those points instead keeps each remaining point at its true
            // timestamp and lets the chart join the last real reading to the
            // next one across the gap.
            let readable = points(breathing).filter { $0.value > 0 }
            if !readable.isEmpty {
                out.append(series(.breathing, "Breathing", "br/min", readable))
            }
        }
        return out
    }

    /// Convenience over a persisted stats row.
    static func series(from stats: MeditationStats) -> [EvidenceSeries] {
        series(
            heartRate: stats.heartRateTimeseries,
            stillness: stats.stillnessTimeseries,
            breathing: stats.breathingRateTimeseries,
            windowSec: stats.windowSec,
            hopSec: stats.hopSec
        )
    }
}
