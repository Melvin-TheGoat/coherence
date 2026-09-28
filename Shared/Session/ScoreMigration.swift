import Foundation
import SwiftData

/// One-time back-fill of the current score across every historical session.
///
/// v9 (5.3.1): live scores now use the wall-clock duration this back-fill
/// already read, so rows scored live under 5.3.0 are brought onto it.
///
/// Re-run for v5, which demoted breath to the SMALLEST term and made it
/// binary: a doorway either exists or it does not, worth .20 against heart .50
/// and stillness .30. It must also now BEGIN within the first five minutes,
/// because slow breathing is an entry technique and pacing late is someone
/// managing a number. Same reasoning as every re-run before it: a history
/// graph is a comparison, and a comparison across two formulas is a lie told
/// with a line chart.
///
/// v4 (superseded) moved breath from the session mean to the doorway.
///
/// **Most rows will not move.** Absent breath keeps the same 0.60/0.40
/// heart/stillness split it had before, so every session that never slowed its
/// breath rescores to exactly what it showed. Only sessions with a doorway
/// change, and they come down.
///
/// **What this back-fill can and cannot reproduce.** The doorway itself
/// recomputes exactly, because `breathingRateTimeseries`, `windowSec` and
/// `hopSec` are all stored. The CLARITY gate cannot: per-window clarity was
/// never persisted before v4, so historical rows are scored as though their
/// reads were clear. Historical breath credit is therefore more permissive
/// than live scoring, and that gap decays as new sessions accumulate.
///
/// Worth naming plainly, since the paragraph below used to claim otherwise:
/// the previous back-fill passed the DISPLAYED mean, which live `analyze`
/// gated and this did not. History was already scored on reads the engine
/// refused. This is not a new compromise, it is the same one, now measured.
///
/// **Why it's safe to rewrite an "immutable" row here.** Stats rows are
/// immutable by convention because a session's *measurements* must never
/// change after the fact. This doesn't touch a measurement: every input the
/// formula needs is already stored on the row, so the back-fill runs the same
/// code path `analyze` runs and replaces a number that was derived from those
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

    static let doneKey = "scoreBackfillDone.v9"

    /// Rewrites `overallScore` on every row not already at the current
    /// algorithm version. Idempotent, and a no-op once the flag is set.
    @discardableResult
    static func backfillIfNeeded(in context: ModelContext,
                                 defaults: UserDefaults = .standard,
                                 save: (ModelContext) throws -> Void = { try $0.save() }) -> Int {
        guard !defaults.bool(forKey: doneKey) else { return 0 }
        // The flag follows a SUCCESSFUL save, never the attempt. It used to be
        // set whatever `save()` did, so one failed write (disk full, a store
        // mid-migration) left history on the old formula forever with the
        // flag swearing it was done.
        guard let updated = try? backfillOrThrow(in: context, save: save) else { return 0 }
        defaults.set(true, forKey: doneKey)
        return updated
    }

    /// The work itself, without the flag — exposed for tests.
    @discardableResult
    static func backfill(in context: ModelContext) -> Int {
        (try? backfillOrThrow(in: context)) ?? 0
    }

    /// Throws when a fetch or the save fails, so the caller can leave the flag
    /// unset and retry on the next launch. `save` is a seam for the test that
    /// proves a failed save leaves the flag unset.
    static func backfillOrThrow(in context: ModelContext,
                                save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Int {
        let version = SignalEngine.version
        let rows = try context.fetch(FetchDescriptor<MeditationStats>())

        // Session durations, keyed by id: the stats row doesn't carry one, and
        // duration is what the time ceiling needs. A failed fetch throws rather
        // than falling back to spans, which would score every row short.
        let sessions = try context.fetch(FetchDescriptor<Session>())
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

            // Clarity is treated as passing: it was never stored, so there is
            // nothing to gate on. See the note at the top of this file.
            let doorway = SignalEngine.breathDoorway(
                rates: row.breathingRateTimeseries,
                clarities: row.breathClarityTimeseries.count == row.breathingRateTimeseries.count
                    ? row.breathClarityTimeseries
                    : [Double](repeating: 1.0, count: row.breathingRateTimeseries.count),
                windowSec: row.windowSec,
                hopSec: row.hopSec)
            row.breathDoorwayRate = doorway?.rate
            row.breathDoorwayHeldSec = doorway?.heldSec
            row.breathDoorwayStartSec = doorway?.startSec

            row.overallScore = SignalEngine.score(
                stillnessScore: row.stillnessScore,
                heartRateTimeseries: row.heartRateTimeseries,
                breathDoorway: doorway,
                durationSec: seconds)
            row.algorithmVersion = version
            updated += 1
        }
        if updated > 0 {
            // Roll the edits back on a failed save, so the rows still read as
            // the old version and a retry rescores them rather than skipping
            // rows that only look current in memory.
            do { try save(context) } catch { context.rollback(); throw error }
        }
        return updated
    }
}
