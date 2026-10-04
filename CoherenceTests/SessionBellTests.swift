import XCTest
@testable import Coherence

/// The bell at the end of a timed session (2026-10-04). It is synthesized, so
/// the only way it can sound wrong is the arithmetic: these pin that it never
/// clips, and that it starts and stops on silence (a jump at either end is a
/// click in someone's ear at the quietest moment of their day).
final class SessionBellTests: XCTestCase {

    func test_theBellNeverClipsAndStartsAndEndsOnSilence() {
        let rate = 48_000.0
        var peak = 0.0
        var i = 0.0
        while i / rate < SessionBell.length {
            peak = max(peak, abs(SessionBell.sample(at: i / rate)))
            i += 1
        }
        XCTAssertLessThan(peak, 0.8, "headroom left under full scale")
        XCTAssertGreaterThan(peak, 0.3, "loud enough to be heard across a room")
        XCTAssertEqual(SessionBell.sample(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(SessionBell.sample(at: SessionBell.length - 1 / rate), 0, accuracy: 1e-3)
        XCTAssertEqual(SessionBell.sample(at: SessionBell.length + 1), 0)
        XCTAssertEqual(SessionBell.sample(at: -1), 0)
    }
}
