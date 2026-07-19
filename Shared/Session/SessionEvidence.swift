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
    var id: String { kind.rawValue }
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

        var out: [EvidenceSeries] = []
        if !heartRate.isEmpty {
            out.append(EvidenceSeries(kind: .heartRate, title: "Heart rate", unit: "bpm", points: points(heartRate)))
        }
        if !stillness.isEmpty {
            out.append(EvidenceSeries(kind: .stillness, title: "Stillness", unit: "", points: points(stillness)))
        }
        if !breathing.isEmpty {
            out.append(EvidenceSeries(kind: .breathing, title: "Breathing", unit: "br/min", points: points(breathing)))
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
