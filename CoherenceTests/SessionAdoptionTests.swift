import XCTest
@testable import Coherence

/// Taking over a session the Watch is running but the phone is not showing.
///
/// Aziz, 2026-09-16: his Watch was locked when he tapped Begin. The Watch
/// started and ran, but a locked Watch is unreachable, so its start ack could
/// not be delivered; the phone's 45-second watchdog fired and said the session
/// could not start. He unlocked the Watch and found it at 33 seconds, then
/// pressing Begin again did nothing, because the Watch was already running and
/// silently dropped the new params.
///
/// The fix is that a start ack for a session the phone is not showing is taken
/// over rather than dropped. These lock the guards that keep it safe, because
/// the failure mode on the other side is the stale-WC-queue family this
/// project has been bitten by four times: a queued ack replaying later must
/// never resurrect a finished session's screen.
final class SessionAdoptionTests: XCTestCase {

    func test_aSessionRunningRightNowIsAdopted() {
        XCTAssertTrue(SessionCoordinator.shouldAdopt(startedAt: Date(), alreadyPersisted: false))
    }

    /// Aziz's case exactly: the ack lands a little after the phone gave up.
    func test_theAckThatArrivesAfterThePhoneGaveUpIsAdopted() {
        let started = Date().addingTimeInterval(-60)
        XCTAssertTrue(SessionCoordinator.shouldAdopt(startedAt: started, alreadyPersisted: false))
    }

    /// A long open-ended sit is still running, and only the Watch ends it.
    func test_aLongSitIsStillAdopted() {
        let started = Date().addingTimeInterval(-45 * 60)
        XCTAssertTrue(SessionCoordinator.shouldAdopt(startedAt: started, alreadyPersisted: false))
    }

    /// The stale-queue guard. A finished session is always persisted, so a
    /// persisted id means this ack is a replay, however fresh it looks.
    func test_aPersistedSessionIsNeverAdopted() {
        XCTAssertFalse(SessionCoordinator.shouldAdopt(startedAt: Date(), alreadyPersisted: true))
        XCTAssertFalse(SessionCoordinator.shouldAdopt(startedAt: Date().addingTimeInterval(-30),
                                                      alreadyPersisted: true))
    }

    /// The second guard, for a session that was never persisted (the payload
    /// was lost) but cannot possibly still be running.
    func test_anAckTooOldToBeRunningIsRefused() {
        let now = Date()
        let justInside = now.addingTimeInterval(-(SessionCoordinator.maxAdoptAgeSec - 60))
        XCTAssertTrue(SessionCoordinator.shouldAdopt(startedAt: justInside, now: now,
                                                     alreadyPersisted: false))

        let justOutside = now.addingTimeInterval(-(SessionCoordinator.maxAdoptAgeSec + 60))
        XCTAssertFalse(SessionCoordinator.shouldAdopt(startedAt: justOutside, now: now,
                                                      alreadyPersisted: false))
    }

    /// A start stamped in the future is clock skew between the two devices,
    /// not a session to take over.
    func test_aStartInTheFutureIsRefused() {
        let now = Date()
        XCTAssertFalse(SessionCoordinator.shouldAdopt(startedAt: now.addingTimeInterval(120),
                                                      now: now, alreadyPersisted: false))
    }
}
