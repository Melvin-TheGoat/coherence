import XCTest
import SwiftData

/// Headless verification of the Phase-4 write path: bootstrap user, one-transaction
/// persistence, idempotency, and discard/short guards — all against an in-memory
/// store, no device required.
final class SessionStoreTests: XCTestCase {

    private func freshContext() -> ModelContext {
        ModelContext(Persistence.inMemory())
    }

    private func sampleResult(belly: Bool) -> SignalResult {
        SignalResult(
            heartRateTimeseries: [70, 68, 66], meanHR: 68, startHR: 70, endHR: 66, hrDecline: 4,
            stillnessTimeseries: [0.9, 0.92, 0.95], stillnessScore: 0.92,
            stillnessMethod: belly ? "breathingExcluded" : "total",
            breathingRateTimeseries: belly ? [6, 6, 6] : [],
            breathDepthTimeseries: belly ? [0.1, 0.1, 0.1] : [],
            meanBreathingRate: belly ? 6 : nil,
            breathingRegularity: belly ? 0.9 : nil,
            resonanceMatchScore: belly ? 0.95 : nil,
            overallScore: 0.8, windowSec: 30, hopSec: 5, algorithmVersion: "2.0.0"
        )
    }

    private func payload(
        id: UUID = UUID(), belly: Bool = false, duration: Int = 120,
        discard: Bool = false, result: SignalResult? = nil
    ) -> SessionPayload {
        SessionPayload(
            sessionID: id, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            mode: "silence", trackID: nil, bellyBreathing: belly,
            durationSec: duration, discard: discard,
            result: result ?? sampleResult(belly: belly)
        )
    }

    private func count<T: PersistentModel>(_ type: T.Type, in ctx: ModelContext) -> Int {
        (try? ctx.fetch(FetchDescriptor<T>()))?.count ?? 0
    }

    /// Bootstrap creates exactly one User (+ Preferences) and reuses it.
    func test_bootstrapCreatesSingleUser() {
        let ctx = freshContext()
        let u1 = SessionStore.currentUser(in: ctx)
        let u2 = SessionStore.currentUser(in: ctx)
        XCTAssertEqual(u1.id, u2.id)
        XCTAssertEqual(u1.appleUserID, "")
        XCTAssertEqual(count(User.self, in: ctx), 1)
        XCTAssertEqual(count(Preferences.self, in: ctx), 1)
    }

    /// A good belly payload writes one Session + one Stats with the engine fields.
    func test_persistWritesSessionAndStats() throws {
        let ctx = freshContext()
        let p = payload(belly: true)
        let session = SessionStore.persist(p, in: ctx)

        XCTAssertNotNil(session)
        XCTAssertEqual(count(Session.self, in: ctx), 1)
        XCTAssertEqual(count(MeditationStats.self, in: ctx), 1)
        XCTAssertEqual(session?.id, p.sessionID)
        XCTAssertTrue(session?.bellyBreathing ?? false)
        XCTAssertEqual(session?.durationSec, 120)

        let stats = try XCTUnwrap(ctx.fetch(FetchDescriptor<MeditationStats>()).first)
        XCTAssertEqual(try XCTUnwrap(stats.sessionID), p.sessionID)
        XCTAssertEqual(stats.meanBreathingRate, 6)
        XCTAssertEqual(stats.stillnessMethod, "breathingExcluded")
    }

    /// Persisting the same payload twice never creates a duplicate.
    func test_persistIsIdempotent() {
        let ctx = freshContext()
        let p = payload(belly: false)
        XCTAssertNotNil(SessionStore.persist(p, in: ctx))
        XCTAssertNil(SessionStore.persist(p, in: ctx))
        XCTAssertEqual(count(Session.self, in: ctx), 1)
        XCTAssertEqual(count(MeditationStats.self, in: ctx), 1)
    }

    /// Discarded and too-short payloads write nothing.
    func test_persistSkipsDiscardedAndShort() {
        let ctx = freshContext()
        XCTAssertNil(SessionStore.persist(payload(discard: true), in: ctx))
        XCTAssertNil(SessionStore.persist(payload(duration: 10), in: ctx))
        XCTAssertEqual(count(Session.self, in: ctx), 0)
        XCTAssertEqual(count(MeditationStats.self, in: ctx), 0)
    }

    /// Persisted sessions feed the streak calculator.
    func test_sessionStartDatesFeedStreak() {
        let ctx = freshContext()
        SessionStore.persist(payload(), in: ctx)
        let dates = SessionStore.sessionStartDates(in: ctx)
        XCTAssertEqual(dates.count, 1)
        let r = StreakCalculator.streak(from: dates, today: dates[0])
        XCTAssertEqual(r.current, 1)
    }
}
