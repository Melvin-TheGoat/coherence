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
            breathDoorwayRate: belly ? 6 : nil,
            breathDoorwayHeldSec: belly ? 90 : nil,
            breathClarityTimeseries: belly ? [0.8, 0.8, 0.8] : [],
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

    /// The chosen sound preset is stored on the Session (nil = silence).
    func test_persistStoresFrequencyID() {
        let ctx = freshContext()
        let withSound = SessionStore.persist(payload(), frequencyID: "guided.identity", in: ctx)
        XCTAssertEqual(withSound?.frequencyID, "guided.identity")
        let silent = SessionStore.persist(payload(), in: ctx)
        XCTAssertNil(silent?.frequencyID)
    }


    /// Deleting a session takes its stats and reflection with it and leaves
    /// every other session alone.
    func test_deleteSessionRemovesItsRowsOnly() throws {
        let ctx = freshContext()
        let keep = payload(belly: false)
        let junk = payload(belly: true)
        XCTAssertNotNil(SessionStore.persist(keep, in: ctx))
        XCTAssertNotNil(SessionStore.persist(junk, in: ctx))
        _ = SessionStore.saveReflection(sessionID: junk.sessionID, rating: 3, note: "oops",
                                    technique: nil, techniqueNote: "", in: ctx)
        XCTAssertEqual(count(Session.self, in: ctx), 2)
        XCTAssertEqual(count(SessionReflection.self, in: ctx), 1)

        XCTAssertTrue(SessionStore.deleteSession(id: junk.sessionID, in: ctx))

        XCTAssertEqual(count(Session.self, in: ctx), 1)
        XCTAssertEqual(count(MeditationStats.self, in: ctx), 1)
        XCTAssertEqual(count(SessionReflection.self, in: ctx), 0)
        let left = try XCTUnwrap(ctx.fetch(FetchDescriptor<Session>()).first)
        XCTAssertEqual(left.id, keep.sessionID)
        XCTAssertFalse(SessionStore.deleteSession(id: junk.sessionID, in: ctx), "a second delete finds nothing")
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

    /// The Watch sends every payload twice. The second copy must come back
    /// as a duplicate, not as "nothing written", or the phone reads a good
    /// session as unreadable and puts up the discard screen.
    func test_aSecondCopyIsAlreadyStoredNotRejected() {
        let ctx = freshContext()
        let p = payload()
        guard case .saved = SessionStore.store(p, in: ctx) else {
            return XCTFail("the first copy writes the session")
        }
        guard case .alreadyStored = SessionStore.store(p, in: ctx) else {
            return XCTFail("the second copy is a duplicate, not a rejection")
        }
        XCTAssertEqual(count(Session.self, in: ctx), 1)
        XCTAssertEqual(count(MeditationStats.self, in: ctx), 1)
    }

    /// Only a payload with nothing to write is rejected.
    func test_discardedAndShortPayloadsAreRejected() {
        let ctx = freshContext()
        guard case .rejected = SessionStore.store(payload(discard: true), in: ctx),
              case .rejected = SessionStore.store(payload(duration: 10), in: ctx) else {
            return XCTFail("discarded and too-short payloads are rejections")
        }
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

    // MARK: - Payload transport

    /// A realistic two-hour result: noisy curves on the engine's 5 s hop, the
    /// way a live session arrives. As plain JSON it overran sendMessage's
    /// limit, so End on the Watch waited on the slow queue.
    private func longResult(minutes: Int) -> SignalResult {
        let n = minutes * 60 / 5
        var seed: UInt64 = 808
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return SignalResult(
            heartRateTimeseries: (0..<n).map { 72 - Double($0) / Double(n) * 9 + noise() * 1.8 },
            meanHR: 67.4, startHR: 72, endHR: 63, hrDecline: 9,
            stillnessTimeseries: (0..<n).map { _ in 0.82 + noise() * 0.15 },
            stillnessScore: 0.9, stillnessMethod: "total",
            breathingRateTimeseries: (0..<n).map { _ in 5 + noise() * 6 },
            breathDepthTimeseries: (0..<n).map { _ in noise() * 0.004 },
            meanBreathingRate: 7.1, breathingRegularity: 0.5, resonanceMatchScore: 0.7,
            breathClarityTimeseries: (0..<n).map { _ in 0.4 + noise() * 0.5 },
            overallScore: 0.83, windowSec: 30, hopSec: 5, algorithmVersion: "5.3.1"
        )
    }

    func test_payloadCoding_roundTripsCompressedAndReadsPlainJSON() throws {
        let p = payload(duration: 7200, result: longResult(minutes: 120))
        let packed = try PayloadCoding.encode(p)
        XCTAssertTrue(packed.starts(with: PayloadCoding.tag))
        let back = try XCTUnwrap(PayloadCoding.decode(packed))
        XCTAssertEqual(back, PayloadCoding.forTransport(p))
        // Summary numbers travel exact; curves to six significant digits.
        XCTAssertEqual(back.result?.overallScore, p.result?.overallScore)
        for (a, b) in zip(back.result!.heartRateTimeseries, p.result!.heartRateTimeseries) {
            XCTAssertEqual(a, b, accuracy: 0.001)
        }
        // An older Watch sends plain JSON; the phone still reads it.
        let plain = try JSONEncoder().encode(p)
        XCTAssertEqual(PayloadCoding.decode(plain), p)
    }

    func test_payloadCoding_fourHourSessionFitsTheImmediateChannel() throws {
        let p = payload(duration: 14_400, result: longResult(minutes: 240))
        let plain = try JSONEncoder().encode(p)
        let packed = try PayloadCoding.encode(p)
        XCTAssertGreaterThan(plain.count, PayloadCoding.messageLimit, "the fixture should reproduce the problem")
        XCTAssertLessThanOrEqual(packed.count, PayloadCoding.messageLimit)
    }
}
