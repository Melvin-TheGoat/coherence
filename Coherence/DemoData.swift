#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only synthetic data, for previewing screens (e.g. the post-session
/// evidence graphs) in the simulator without a real Watch session. Not compiled
/// into release builds.
enum DemoData {
    /// Inserts one belly session with realistic settling curves and returns its id.
    static func seedResults(in context: ModelContext) -> UUID {
        // Window count for a 600 s session at the real grid: point i sits at
        // i*hop + window/2, so n = (dur - window)/hop + 1. It used to be a flat
        // 18, which drew ninety seconds of curve under a "10 min" header.
        let n = (600 - 30) / 5 + 1
        let f = { (i: Int) in Double(i) / Double(n - 1) }
        // Shaped like a real settle rather than a ruled line: heart rate falls
        // fast in the first couple of minutes and then wobbles along a floor,
        // which is what every captured session actually looks like. A linear
        // ramp reads as placeholder art in a screenshot.
        let hrWob: [Double] = [0.0, 0.9, -0.7, 1.3, -0.4, 0.6, -1.1, 0.4, 0.8, -0.9]
        let hr: [Double] = (0..<n).map { i in
            let settle: Double = 62.0 + 13.0 * exp(-3.4 * f(i))
            let drift: Double = 0.8 * sin(Double(i) / 5.7)
            return settle + drift + hrWob[i % hrWob.count]
        }
        // Stillness climbs as the body gives up holding itself, with two small
        // dips where a real sitter shifts.
        let stillDip: [Double] = [0.0, 0.0, -0.05, 0.0, 0.02, 0.0, -0.03, 0.01]
        let still: [Double] = (0..<n).map { i in
            let rise: Double = 0.93 - 0.36 * exp(-3.1 * f(i))
            let sway: Double = 0.018 * sin(Double(i) / 4.3)
            return min(0.98, max(0.4, rise + sway + stillDip[i % stillDip.count]))
        }
        // A slow opening, then natural breathing — the shape the score is built
        // for, and the reason the graph highlights a stretch rather than a band.
        let breaths = (0..<n).map { i -> Double in
            let t = Double(i) * 5 + 15                        // window centre
            if t < 165 { return 5.6 + 0.25 * sin(Double(i) / 2.2) }
            if t < 210 { return 5.6 + (t - 165) / 45 * 4.6 }  // letting it go
            return 10.4 + 0.7 * sin(Double(i) / 4.0)
        }
        let depth = (0..<n).map { _ in 0.08 }

        // Pinned to mid-afternoon rather than "now": the store slides show
        // this session twice, and a launch-time stamp had slide 1 saying
        // 3:24 PM while slide 2 said 1:34 AM. Screenshots must agree.
        let at = Calendar.current.date(bySettingHour: 15, minute: 24, second: 0,
                                       of: Date()) ?? Date()
        let session = Session(mode: "nature", bellyBreathing: true,
                              frequencyID: "rain", startedAt: at, durationSec: 600)
        let stats = MeditationStats(
            sessionID: session.id,
            heartRateTimeseries: hr, meanHR: 68, startHR: 75, endHR: 62, hrDecline: 13,
            stillnessTimeseries: still, stillnessScore: 0.86, stillnessMethod: "breathingExcluded",
            breathingRateTimeseries: breaths, breathDepthTimeseries: depth,
            meanBreathingRate: 8.9, breathingRegularity: 0.82, resonanceMatchScore: 0.9,
            breathDoorwayRate: 5.6, breathDoorwayHeldSec: 145, breathDoorwayStartSec: 10,
            overallScore: 0.81, windowSec: 30, hopSec: 5
        )
        stats.preCoherenceScore = 0.34; stats.preCoherenceHR = 74; stats.preCoherenceRMSSD = 96
        stats.postCoherenceScore = 0.78; stats.postCoherenceHR = 63; stats.postCoherenceRMSSD = 118
        context.insert(session)
        context.insert(stats)
        context.insert(SessionReflection(sessionID: session.id, rating: 8,
                                         note: "Felt genuinely settled by the end. The first ten minutes my mind was everywhere, kept planning tomorrow instead of being here. Then somewhere around the halfway mark it went quiet on its own, and I stopped noticing the timer. Getting up afterwards felt like surfacing."))
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
            ("guided", "guided.identity", false), ("frequency", "manifest", false),
            ("nature", "rain", false), ("frequency", "theta", false),
            ("silence", nil, false), ("nature", "ocean", false),
        ]
        for (i, back) in offsets.enumerated() {
            let day = cal.date(byAdding: .day, value: -back, to: Date())!
            let start = cal.date(bySettingHour: [7, 21, 12][i % 3], minute: (i * 13) % 55, second: 0, of: day)!
            let pick = sounds[i % sounds.count]
            let dur = [600, 900, 1530, 300, 600][i % 5]
            let session = Session(mode: pick.mode, bellyBreathing: pick.belly,
                                  frequencyID: pick.id, startedAt: start, durationSec: dur)
            // One point per hop across the WHOLE duration, or the chart's
            // x-axis ends long before the header's minutes do. Melvin caught a
            // "5 min" session whose curve stopped at 1.4 minutes.
            let n = max(14, dur / 5)
            let drop = Double(6 + (i * 7) % 12)                     // HR settles 6–17 bpm
            let hr = (0..<n).map { 74.0 - drop * Double($0) / Double(n - 1) + Double((i + $0) % 3) }
            let still = (0..<n).map { 0.5 + 0.4 * Double($0) / Double(n - 1) }
            let overall = 0.55 + Double((i * 11) % 40) / 100.0      // 0.55–0.94
            let stats = MeditationStats(
                sessionID: session.id,
                heartRateTimeseries: hr, meanHR: 74 - drop / 2, startHR: 74, endHR: 74 - drop, hrDecline: drop,
                stillnessTimeseries: still, stillnessScore: min(0.95, overall + 0.08),
                stillnessMethod: "total",
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
        // One honestly bad session, yesterday evening. The website's whole
        // argument is that a restless sit still shows you what happened, so the
        // screenshot set needs a real low score next to the high one: climbing
        // heart rate, jagged stillness, no readable breath.
        let badDay = cal.date(byAdding: .day, value: -1, to: Date())!
        let badStart = cal.date(bySettingHour: 18, minute: 40, second: 0, of: badDay)!
        let bad = Session(mode: "silence", bellyBreathing: false,
                          frequencyID: nil, startedAt: badStart, durationSec: 480)
        // 480 s at hopSec 5 = 96 windows, so the curve spans the whole 8
        // minutes. A 14-point series under an "8 min" header drew a chart whose
        // x-axis ended at minute one, which reads as a bug in a screenshot.
        let bn = 96
        let wobble: [Double] = [0.0, 1.4, -0.8, 0.6, -1.1]
        let badHR: [Double] = (0..<bn).map { i -> Double in
            let ramp: Double = 72.0 + 12.0 * Double(i) / Double(bn - 1)
            return ramp + wobble[i % 5]
        }
        let jitter: [Double] = [0.42, 0.18, 0.35, 0.15, 0.30, 0.44, 0.12,
                                0.28, 0.38, 0.16, 0.33, 0.20, 0.41, 0.24]
        let badStill: [Double] = (0..<bn).map { jitter[$0 % jitter.count] }
        let badStats = MeditationStats(
            sessionID: bad.id,
            heartRateTimeseries: badHR, meanHR: 78, startHR: 72, endHR: 84,
            hrDecline: -12,
            stillnessTimeseries: badStill, stillnessScore: 0.27,
            stillnessMethod: "total",
            breathingRateTimeseries: [], breathDepthTimeseries: [],
            meanBreathingRate: nil, breathingRegularity: nil,
            resonanceMatchScore: nil,
            overallScore: 0.24, windowSec: 30, hopSec: 5
        )
        context.insert(bad)
        context.insert(badStats)
        context.insert(SessionReflection(sessionID: bad.id, rating: 3,
                                         note: "Could not settle at all today."))
        try? context.save()
    }

    /// One noisy, honest, low-scoring session WITH a readable breath, for
    /// screenshots (`PREVIEW_NOISY=1`). The point of the noise is the point of
    /// the product: the instrument is sensitive, so a restless sit LOOKS
    /// restless. Deterministic wobble, no randomness, so every capture of it
    /// is identical. Idempotent via a fixed timestamp.
    static func seedNoisyBad(in context: ModelContext) {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -1, to: Date())!
        let start = cal.date(bySettingHour: 19, minute: 12, second: 0, of: day)!

        let existing = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        guard !existing.contains(where: { abs($0.startedAt.timeIntervalSince(start)) < 60 })
        else { return }

        let dur = 720
        let n = dur / 5   // 144 windows

        // Heart: drifts UP 71 -> 81 with visible beat-to-window wobble.
        let wob: [Double] = [0.0, 1.8, -1.2, 2.4, -0.6, 1.1, -1.9, 0.7]
        let hr: [Double] = (0..<n).map { i in
            let ramp = 71.0 + 10.0 * Double(i) / Double(n - 1)
            let sway = 1.6 * sin(Double(i) / 3.1)
            return ramp + sway + wob[i % wob.count]
        }

        // Stillness: low and jagged, never settling.
        let jag: [Double] = [0.42, 0.18, 0.51, 0.22, 0.35, 0.12, 0.47, 0.28,
                             0.15, 0.44, 0.24, 0.38]
        let still: [Double] = (0..<n).map { i in
            min(0.6, max(0.05, jag[i % jag.count] + 0.06 * sin(Double(i) / 5.0)))
        }

        // Breath: READ, but fast and uneven, wandering 8-12/min, with patches
        // the engine could not follow (zeros, not plotted). Roughly 72%
        // readable, so it displays plainly, without the partial-read tag.
        let breath: [Double] = (0..<n).map { i in
            if (i % 11) < 3 { return 0 }   // unreadable stretch
            let wander = 9.8 + 1.6 * sin(Double(i) / 7.0)
            let jitter = 0.9 * sin(Double(i) / 2.3) + 0.5 * sin(Double(i) / 1.4)
            return max(6.5, min(13.5, wander + jitter))
        }

        let session = Session(mode: "silence", bellyBreathing: false,
                              frequencyID: nil, startedAt: start, durationSec: dur)
        let stats = MeditationStats(
            sessionID: session.id,
            heartRateTimeseries: hr, meanHR: 76, startHR: 71, endHR: 81,
            hrDecline: -10,
            stillnessTimeseries: still, stillnessScore: 0.31,
            stillnessMethod: "total",
            breathingRateTimeseries: breath, breathDepthTimeseries: [],
            meanBreathingRate: 9.8, breathingRegularity: 0.34,
            resonanceMatchScore: nil,
            overallScore: 0.29, windowSec: 30, hopSec: 5
        )
        context.insert(session)
        context.insert(stats)
        context.insert(SessionReflection(sessionID: session.id, rating: 4,
                                         note: "Mind was racing the whole time."))
        try? context.save()
    }
}
#endif
