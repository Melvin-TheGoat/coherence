import XCTest
import SwiftData
@testable import Coherence

/// The Watch is optional, so the phone has to be able to write a session by
/// itself. These lock the three things that path must get right: it counts,
/// it claims nothing it did not measure, and it cannot write twice.
final class PhoneSessionTests: XCTestCase {

    private func freshContext() -> ModelContext {
        ModelContext(Persistence.inMemory())
    }

    func test_phoneSession_isWrittenWithNoStats() throws {
        let ctx = freshContext()
        let id = UUID()
        let session = SessionStore.persistPhoneSession(
            id: id, startedAt: Date().addingTimeInterval(-600),
            mode: "silence", durationSec: 600, in: ctx)

        XCTAssertNotNil(session)
        XCTAssertEqual(session?.source, "phone")
        XCTAssertTrue(session?.isPhoneOnly == true)

        // No MeditationStats: an empty row would claim we looked and found
        // nothing, and nothing was looking.
        let stats = try ctx.fetch(FetchDescriptor<MeditationStats>(
            predicate: #Predicate { $0.sessionID == id }))
        XCTAssertTrue(stats.isEmpty, "a phone sit must not write an empty stats row")
    }

    func test_phoneSession_countsTowardTheStreak() throws {
        let ctx = freshContext()
        SessionStore.persistPhoneSession(id: UUID(), startedAt: Date(),
                                         mode: "silence", durationSec: 600, in: ctx)
        let dates = try ctx.fetch(FetchDescriptor<Session>()).map(\.startedAt)
        XCTAssertEqual(StreakCalculator.streak(from: dates).current, 1)
    }

    func test_phoneSession_underTheFloorIsNotWritten() throws {
        let ctx = freshContext()
        let written = SessionStore.persistPhoneSession(
            id: UUID(), startedAt: Date(), mode: "silence",
            durationSec: SessionStore.minDurationSec - 1, in: ctx)
        XCTAssertNil(written, "a Begin-then-End by accident is not a session")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<Session>()).isEmpty)
    }

    /// The finish can be reached twice (the timer fires while the user is
    /// tapping End), so the write has to be keyed on the session itself —
    /// `persist` keys on the stats row, and there is none here.
    func test_phoneSession_isIdempotent() throws {
        let ctx = freshContext()
        let id = UUID()
        let first = SessionStore.persistPhoneSession(id: id, startedAt: Date(),
                                                     mode: "silence", durationSec: 600, in: ctx)
        let second = SessionStore.persistPhoneSession(id: id, startedAt: Date(),
                                                      mode: "silence", durationSec: 600, in: ctx)
        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Session>()).count, 1)
    }

    /// Everything written before the phone could run a sit on its own was run
    /// by a Watch, and must keep reading that way.
    func test_aSessionWithNoSourceReadsAsAWatchSession() throws {
        let ctx = freshContext()
        let session = Session(startedAt: Date(), durationSec: 600)
        ctx.insert(session)
        XCTAssertEqual(session.source, "watch")
        XCTAssertFalse(session.isPhoneOnly)
    }
}

extension PhoneSessionTests {
    private func measuredPayload(id: UUID, startedAt: Date, durationSec: Int = 600) -> SessionPayload {
        SessionPayload(
            sessionID: id, startedAt: startedAt, mode: "silence",
            bellyBreathing: false, durationSec: durationSec, discard: false,
            result: SignalResult(
                heartRateTimeseries: [70, 68], meanHR: 69, startHR: 70, endHR: 68,
                hrDecline: 2,
                stillnessTimeseries: [0.9, 0.9], stillnessScore: 0.9,
                stillnessMethod: "total",
                breathingRateTimeseries: [], breathDepthTimeseries: [],
                meanBreathingRate: nil, breathingRegularity: nil,
                resonanceMatchScore: nil,
                breathDoorwayRate: nil, breathDoorwayHeldSec: nil,
                breathClarityTimeseries: [],
                overallScore: 0.8, windowSec: 30, hopSec: 5,
                algorithmVersion: "5.3.0"))
    }

    /// The phone can take a Watch sit over (the Watch never confirmed in
    /// time, or End was tapped first) and write it as a phone sit. When the
    /// Watch's measurements land afterwards they belong to that sit: attached
    /// to the one row, never a second Session under the same id, and never
    /// thrown away.
    func test_aLatePayloadAttachesToThePhoneSessionItTookOver() throws {
        let ctx = ModelContext(Persistence.inMemory())
        let id = UUID()
        let started = Date().addingTimeInterval(-600)
        SessionStore.persistPhoneSession(id: id, startedAt: started,
                                         mode: "silence", durationSec: 600, in: ctx)

        let outcome = SessionStore.store(measuredPayload(id: id, startedAt: started.addingTimeInterval(20),
                                                         durationSec: 560), in: ctx)
        guard case .saved(let session) = outcome else {
            return XCTFail("the readings attach to the phone's session")
        }
        XCTAssertEqual(session.id, id)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Session>()).count, 1)
        let stats = try ctx.fetch(FetchDescriptor<MeditationStats>(
            predicate: #Predicate { $0.sessionID == id }))
        XCTAssertEqual(stats.count, 1)
        // It was measured after all, so it stops reading as unmeasured, and
        // keeps the length the person actually sat.
        XCTAssertFalse(session.isPhoneOnly)
        XCTAssertEqual(session.durationSec, 600)
        XCTAssertEqual(session.startedAt, started)

        // The Watch's second copy is a duplicate, not a second attach.
        guard case .alreadyStored = SessionStore.store(measuredPayload(id: id, startedAt: started),
                                                       in: ctx) else {
            return XCTFail("a second copy is a duplicate")
        }
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MeditationStats>()).count, 1)
    }

    /// A sit recorded by hand never takes a Watch's readings.
    func test_aLoggedSessionNeverTakesAPayload() throws {
        let ctx = ModelContext(Persistence.inMemory())
        let id = UUID()
        SessionStore.persistPhoneSession(id: id, startedAt: Date(), mode: "silence",
                                         durationSec: 600, source: "logged", in: ctx)
        XCTAssertNil(SessionStore.persist(measuredPayload(id: id, startedAt: Date()), in: ctx))
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<MeditationStats>()).isEmpty)
    }
}
