import Foundation
import SwiftData

/// One-time back-fill of the current score across every historical session.
///
/// Re-run for v3.2, which changed what a breathing rate is worth: breath now
/// counts at any rate on a wide curve instead of a narrow resonance bell. Same
/// reasoning as v3 itself, so the key is bumped to .v2: a history graph is a
/// comparison, and a comparison across two formulas is a lie told with a line
/// chart.
///
/// **Why it's safe to rewrite an "immutable" row here.** Stats rows are
/// immutable by convention because a session's *measurements* must never
/// change after the fact. This doesn't touch a measurement: every input the v3
/// formula needs (stillness score, the heart-rate series, resonance, duration)
/// is already stored on the row, so the back-fill runs the identical code path
/// `analyze` runs and simply replaces a number that was derived from those
/// inputs by an older formula. Nothing measured is edited, invented, or lost.
///
/// **Why back-fill at all**, when `algorithmVersion` exists precisely so old
/// rows can keep their old scores: a history graph is a comparison, and a
/// comparison across two different formulas is a lie told with a line chart.
/// A visible step at the changeover would read as "something happened to me
/// in August" when nothing did. One formula over the whole history, or the
/// history means nothing.
///
/// Follows the health-rescue precedent: a UserDefaults flag, set only after a
/// successful save, so a crash mid-migration just retries next launch.
enum ScoreMigration {

    static let doneKey = "scoreBackfillDone.v2"

    /// Rewrites `overallScore` on every row not already at the current
    /// algorithm version. Idempotent, and a no-op once the flag is set.
    @discardableResult
    static func backfillIfNeeded(in context: ModelContext,
                                 defaults: UserDefaults = .standard) -> Int {
        guard !defaults.bool(forKey: doneKey) else { return 0 }
        let updated = backfill(in: context)
        defaults.set(true, forKey: doneKey)
        return updated
    }

    /// The work itself, without the flag — exposed for tests.
    @discardableResult
    static func backfill(in context: ModelContext) -> Int {
        let version = SignalEngine.version
        guard let rows = try? context.fetch(FetchDescriptor<MeditationStats>()) else { return 0 }

        // Session durations, keyed by id: the stats row doesn't carry one, and
        // duration is what the time ceiling needs.
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        var durations: [UUID: Int] = [:]
        for s in sessions { durations[s.id] = s.durationSec }

        var updated = 0
        for row in rows where row.algorithmVersion != version {
            // Fall back to the timeseries' own span when a session row is
            // missing (a stats row can outlive its session in a partial sync):
            // point i sits at i*hop + window/2, so the last point ends at
            // (n-1)*hop + window.
            let spanned = row.heartRateTimeseries.isEmpty
                ? 0
                : (row.heartRateTimeseries.count - 1) * row.hopSec + row.windowSec
            let seconds = durations[row.sessionID ?? UUID()] ?? spanned

            row.overallScore = SignalEngine.score(
                stillnessScore: row.stillnessScore,
                heartRateTimeseries: row.heartRateTimeseries,
                meanBreathingRate: row.meanBreathingRate,
                durationSec: seconds)
            row.algorithmVersion = version
            updated += 1
        }
        if updated > 0 { try? context.save() }
        return updated
    }
}
