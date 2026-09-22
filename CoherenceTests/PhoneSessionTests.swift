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
    /// The watchdog can hand a sit to the phone and the Watch's payload can
    /// still land afterwards. Without this the late payload inserts a second
    /// Session under the same id, and nothing in SwiftData objects.
    func test_aLatePayloadDoesNotDuplicateAPhoneSession() throws {
        let ctx = ModelContext(Persistence.inMemory())
        let id = UUID()
        let started = Date().addingTimeInterval(-600)
        SessionStore.persistPhoneSession(id: id, startedAt: started,
                                         mode: "silence", durationSec: 600, in: ctx)

        let payload = SessionPayload(
            sessionID: id, startedAt: started, mode: "silence",
            bellyBreathing: false, durationSec: 600, discard: false,
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
        XCTAssertNil(SessionStore.persist(payload, in: ctx))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Session>()).count, 1)
    }
}
