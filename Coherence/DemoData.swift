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

        let session = Session(mode: "nature", bellyBreathing: true,
                              frequencyID: "rain", durationSec: 600)
        let stats = MeditationStats(
            sessionID: session.id,
            heartRateTimeseries: hr, meanHR: 68, startHR: 75, endHR: 62, hrDecline: 13,
            stillnessTimeseries: still, stillnessScore: 0.86, stillnessMethod: "breathingExcluded",
            breathingRateTimeseries: breaths, breathDepthTimeseries: depth,
            meanBreathingRate: 5.6, breathingRegularity: 0.82, resonanceMatchScore: 0.9,
            overallScore: 0.81, windowSec: 30, hopSec: 5
        )
        stats.preCoherenceScore = 0.34; stats.preCoherenceHR = 74; stats.preCoherenceRMSSD = 96
        stats.postCoherenceScore = 0.78; stats.postCoherenceHR = 63; stats.postCoherenceRMSSD = 118
        context.insert(session)
        context.insert(stats)
        context.insert(SessionReflection(sessionID: session.id, rating: 8,
                                         note: "Felt genuinely settled by the end. The first ten minutes my mind was everywhere — kept planning tomorrow instead of being here. Then somewhere around the halfway mark it went quiet on its own, and I stopped noticing the timer. Getting up afterwards felt like surfacing."))
        try? context.save()
        return session.id
    }

    /// Seeds ~3 weeks of varied history (App Store screenshots via
    /// `PREVIEW_HISTORY=1`): a live 7-day streak, dotted calendar, mixed
    /// modes/sounds/ratings. No-op if real history already exists.
    static func seedHistory(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Session>()))?.count ?? 0
        guard existing < 5 else { return }

        let cal = Calendar.current
        // Day offsets back from today — consecutive last 7 days (the streak),
        // then a realistic scatter before that.
        let offsets = [0, 1, 2, 3, 4, 5, 6, 8, 9, 11, 12, 13, 15, 17, 18, 20, 22, 25]
        let sounds: [(mode: String, id: String?, belly: Bool)] = [
            ("guided", "guided.identity", false), ("frequency", "manifest", true),
            ("nature", "rain", false), ("frequency", "theta", true),
            ("silence", nil, false), ("nature", "ocean", false),
        ]
        for (i, back) in offsets.enumerated() {
            let day = cal.date(byAdding: .day, value: -back, to: Date())!
            let start = cal.date(bySettingHour: [7, 21, 12][i % 3], minute: (i * 13) % 55, second: 0, of: day)!
            let pick = sounds[i % sounds.count]
            let dur = [600, 900, 1530, 300, 600][i % 5]
            let session = Session(mode: pick.mode, bellyBreathing: pick.belly,
                                  frequencyID: pick.id, startedAt: start, durationSec: dur)
            let n = 14
            let drop = Double(6 + (i * 7) % 12)                     // HR settles 6–17 bpm
            let hr = (0..<n).map { 74.0 - drop * Double($0) / Double(n - 1) + Double((i + $0) % 3) }
            let still = (0..<n).map { 0.5 + 0.4 * Double($0) / Double(n - 1) }
            let overall = 0.55 + Double((i * 11) % 40) / 100.0      // 0.55–0.94
            let stats = MeditationStats(
                sessionID: session.id,
                heartRateTimeseries: hr, meanHR: 74 - drop / 2, startHR: 74, endHR: 74 - drop, hrDecline: drop,
                stillnessTimeseries: still, stillnessScore: min(0.95, overall + 0.08),
                stillnessMethod: pick.belly ? "breathingExcluded" : "total",
                breathingRateTimeseries: pick.belly ? (0..<n).map { 5.7 + 0.4 * sin(Double($0)) } : [],
                breathDepthTimeseries: pick.belly ? (0..<n).map { _ in 0.08 } : [],
                meanBreathingRate: pick.belly ? 5.8 : nil,
                breathingRegularity: pick.belly ? 0.8 : nil,
                resonanceMatchScore: pick.belly ? 0.87 : nil,
                overallScore: overall, windowSec: 30, hopSec: 5
            )
            context.insert(session)
            context.insert(stats)
            if i % 2 == 0 {
                context.insert(SessionReflection(sessionID: session.id,
                                                 rating: 6 + (i * 3) % 5, note: ""))
            }
        }
        try? context.save()
    }
}
#endif
