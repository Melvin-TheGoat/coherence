import XCTest
import SwiftData
@testable import Coherence

/// The v3 back-fill. A history graph is a comparison, so two formulas across
/// one timeline would be a lie told with a line chart — these lock the
/// back-fill's correctness and its refusal to touch anything measured.
final class ScoreMigrationTests: XCTestCase {

    private func makeContext() -> ModelContext {
        ModelContext(Persistence.inMemory())
    }

    /// A row scored by an older formula is rewritten to exactly what the
    /// engine would compute today — the whole point of sharing one code path.
    ///
    /// The curve, not the mean, is what the score is built from now, so the
    /// fixture carries one: twenty windows at 6/min, long enough to be a
    /// doorway (`(20-1)*5 + 30 = 125 s`).
    func test_backfill_matchesAFreshComputation() {
        let ctx = makeContext()
        let id = UUID()
        let curve = [Double](repeating: 6.0, count: 20)
        ctx.insert(Session(id: id, startedAt: Date(), durationSec: 1200))
        let stats = MeditationStats(
            sessionID: id,
            heartRateTimeseries: [74, 72, 70, 68, 66, 64],
            stillnessScore: 0.90,
            breathingRateTimeseries: curve,
            meanBreathingRate: 6.0,
            resonanceMatchScore: 0.95,
            overallScore: 0.42,                 // whatever the old formula said
            algorithmVersion: "2.0.0")
        ctx.insert(stats)

        ScoreMigration.backfill(in: ctx)

        let doorway = SignalEngine.breathDoorway(
            rates: curve, clarities: [Double](repeating: 1.0, count: curve.count),
            windowSec: 30, hopSec: 5)
        XCTAssertNotNil(doorway, "a steady 6/min curve is a doorway")
        let expected = SignalEngine.score(stillnessScore: 0.90,
                                          heartRateTimeseries: [74, 72, 70, 68, 66, 64],
                                          breathDoorway: doorway,
                                          durationSec: 1200)
        XCTAssertEqual(stats.overallScore ?? -1, expected ?? -2, accuracy: 0.0001)
        XCTAssertEqual(stats.algorithmVersion, SignalEngine.version)
    }

    /// A row with a stored mean but NO curve gets no doorway, so breath cannot
    /// reach its back-filled score. A real behaviour change from the doorway
    /// rework: the old back-fill scored breath off the mean alone.
    func test_backfill_rowWithoutACurveScoresNoBreath() {
        let ctx = makeContext()
        let id = UUID()
        ctx.insert(Session(id: id, startedAt: Date(), durationSec: 1200))
        let stats = MeditationStats(
            sessionID: id,
            heartRateTimeseries: [74, 72, 70, 68, 66, 64],
            stillnessScore: 0.90,
            meanBreathingRate: 6.2,             // stored, but no curve behind it
            algorithmVersion: "2.0.0")
        ctx.insert(stats)

        ScoreMigration.backfill(in: ctx)

        let noBreath = SignalEngine.score(stillnessScore: 0.90,
                                          heartRateTimeseries: [74, 72, 70, 68, 66, 64],
                                          breathDoorway: nil,
                                          durationSec: 1200)
        XCTAssertEqual(stats.overallScore ?? -1, noBreath ?? -2, accuracy: 0.0001)
        XCTAssertNil(stats.breathDoorwayRate)
    }

    /// It rewrites a derived number and nothing else. Every measurement the
    /// Watch actually took must survive untouched — that's what makes editing
    /// an "immutable" row defensible here.
    func test_backfill_neverTouchesMeasurements() {
        let ctx = makeContext()
        let id = UUID()
        ctx.insert(Session(id: id, startedAt: Date(), durationSec: 600))
        let hr: [Double] = [72, 71, 70, 69]
        let still: [Double] = [0.8, 0.85, 0.9, 0.88]
        let stats = MeditationStats(
            sessionID: id,
            heartRateTimeseries: hr, meanHR: 70.5, startHR: 72, endHR: 69, hrDecline: 3,
            stillnessTimeseries: still, stillnessScore: 0.86,
            meanBreathingRate: 5.9, resonanceMatchScore: 0.99,
            overallScore: 0.1, algorithmVersion: "2.0.0")
        ctx.insert(stats)

        ScoreMigration.backfill(in: ctx)

        XCTAssertEqual(stats.heartRateTimeseries, hr)
        XCTAssertEqual(stats.stillnessTimeseries, still)
        XCTAssertEqual(stats.meanHR, 70.5)
        XCTAssertEqual(stats.hrDecline, 3)
        XCTAssertEqual(stats.stillnessScore, 0.86)
        XCTAssertEqual(stats.meanBreathingRate, 5.9)
        XCTAssertEqual(stats.resonanceMatchScore, 0.99)
    }

    func test_backfill_isIdempotentAndSkipsCurrentRows() {
        let ctx = makeContext()
        let id = UUID()
        ctx.insert(Session(id: id, startedAt: Date(), durationSec: 900))
        ctx.insert(MeditationStats(sessionID: id,
                                   heartRateTimeseries: [70, 69, 68],
                                   stillnessScore: 0.9,
                                   algorithmVersion: "2.0.0"))

        XCTAssertEqual(ScoreMigration.backfill(in: ctx), 1)
        XCTAssertEqual(ScoreMigration.backfill(in: ctx), 0, "already current rows are skipped")
    }

    /// A stats row can outlive its session in a partial sync. It must still be
    /// rescored, using the span its own timeseries covers.
    func test_backfill_survivesAMissingSession() {
        let ctx = makeContext()
        let stats = MeditationStats(sessionID: UUID(),
                                    heartRateTimeseries: Array(repeating: 70, count: 30),
                                    stillnessScore: 0.9,
                                    algorithmVersion: "2.0.0")
        ctx.insert(stats)

        ScoreMigration.backfill(in: ctx)
        XCTAssertNotNil(stats.overallScore)
        XCTAssertEqual(stats.algorithmVersion, SignalEngine.version)
    }

    func test_backfillIfNeeded_runsOnlyOnce() {
        let ctx = makeContext()
        let defaults = UserDefaults(suiteName: "score-migration-test")!
        defaults.removePersistentDomain(forName: "score-migration-test")
        let id = UUID()
        ctx.insert(Session(id: id, startedAt: Date(), durationSec: 600))
        ctx.insert(MeditationStats(sessionID: id,
                                   heartRateTimeseries: [70, 69, 68],
                                   stillnessScore: 0.9,
                                   algorithmVersion: "2.0.0"))

        XCTAssertEqual(ScoreMigration.backfillIfNeeded(in: ctx, defaults: defaults), 1)
        XCTAssertEqual(ScoreMigration.backfillIfNeeded(in: ctx, defaults: defaults), 0)
    }
}
