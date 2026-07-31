#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only synthetic data, for previewing screens (e.g. the post-session
/// evidence graphs) in the simulator without a real Watch session. Not compiled
/// into release builds.
enum DemoData {
    /// Inserts one belly session with realistic settling curves and returns its id.
    static func seedResults(in context: ModelContext) -> UUID {
        let n = 18
        let hr = (0..<n).map { 75.0 - 13.0 * (Double($0) / Double(n - 1)) }        // 75 → 62
        let still = (0..<n).map { 0.60 + 0.30 * (Double($0) / Double(n - 1)) }      // 0.60 → 0.90
        let breaths = (0..<n).map { 5.6 + 0.5 * sin(Double($0) / 2.2) }            // ~5–6/min
        let depth = (0..<n).map { _ in 0.08 }

        let session = Session(mode: "nature", bellyBreathing: true, durationSec: 600)
        let stats = MeditationStats(
            sessionID: session.id,
            heartRateTimeseries: hr, meanHR: 68, startHR: 75, endHR: 62, hrDecline: 13,
            stillnessTimeseries: still, stillnessScore: 0.86, stillnessMethod: "breathingExcluded",
            breathingRateTimeseries: breaths, breathDepthTimeseries: depth,
            meanBreathingRate: 5.6, breathingRegularity: 0.82, resonanceMatchScore: 0.9,
            overallScore: 0.81, windowSec: 30, hopSec: 5
        )
        context.insert(session)
        context.insert(stats)
        context.insert(SessionReflection(sessionID: session.id, rating: 8,
                                         note: "Felt genuinely settled by the end. The first ten minutes my mind was everywhere — kept planning tomorrow instead of being here. Then somewhere around the halfway mark it went quiet on its own, and I stopped noticing the timer. Getting up afterwards felt like surfacing."))
        try? context.save()
        return session.id
    }
}
#endif
