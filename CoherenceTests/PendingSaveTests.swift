import XCTest
@testable import Coherence

/// The hand-off that survives the app dying. Aziz, 2026-09-15: picking the
/// phone up after a sit should land on the grading screen, and by then the
/// app has usually been suspended or killed, so the in-memory route through
/// `SessionCoordinator.lastSessionID` is gone.
final class PendingSaveTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A throwaway suite so a test can never disturb the real one.
        suite = "PendingSaveTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        super.tearDown()
    }

    func test_nothingWaitingByDefault() {
        XCTAssertNil(PendingSave.read(in: defaults))
    }

    func test_aSavedSessionIsReadBack() {
        let id = UUID()
        PendingSave.set(id, in: defaults)
        XCTAssertEqual(PendingSave.read(in: defaults), id)
    }

    /// Reading is not consuming: the app can come to the foreground several
    /// times before the person actually finishes the sheet.
    func test_readingDoesNotConsume() {
        let id = UUID()
        PendingSave.set(id, in: defaults)
        _ = PendingSave.read(in: defaults)
        XCTAssertEqual(PendingSave.read(in: defaults), id)
    }

    func test_clearingRemovesIt() {
        PendingSave.set(UUID(), in: defaults)
        PendingSave.clear(in: defaults)
        XCTAssertNil(PendingSave.read(in: defaults))
    }

    /// A sit you forgot about two days ago must not ambush you with a save
    /// sheet. The session is stored either way and can still be shared from
    /// its own results screen.
    func test_aStaleSessionIsNotOffered() {
        let id = UUID()
        let landed = Date()
        PendingSave.set(id, at: landed, in: defaults)

        let justInside = landed.addingTimeInterval(PendingSave.maxAge - 60)
        XCTAssertEqual(PendingSave.read(now: justInside, in: defaults), id)

        let justOutside = landed.addingTimeInterval(PendingSave.maxAge + 60)
        XCTAssertNil(PendingSave.read(now: justOutside, in: defaults))
    }

    /// Reading a stale one clears it, so nothing has to sweep separately.
    func test_readingAStaleOneClearsIt() {
        let landed = Date()
        PendingSave.set(UUID(), at: landed, in: defaults)
        _ = PendingSave.read(now: landed.addingTimeInterval(PendingSave.maxAge + 1), in: defaults)
        XCTAssertNil(PendingSave.read(now: landed, in: defaults),
                     "the stale read should have removed it, not just refused it")
    }

    /// A later session replaces an earlier one: only the most recent sit is
    /// ever owed a screen.
    func test_aNewerSessionReplacesTheWaitingOne() {
        let first = UUID(), second = UUID()
        PendingSave.set(first, in: defaults)
        PendingSave.set(second, in: defaults)
        XCTAssertEqual(PendingSave.read(in: defaults), second)
    }
}
