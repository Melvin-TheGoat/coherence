import XCTest

/// The Apple Watch switch's default (Aziz, 2026-09-28): on only when this
/// Watch has connected before and is connected now.
final class WatchDefaultTests: XCTestCase {
    func test_theFirstConnectionTurnsMeasuringOn() {
        XCTAssertEqual(WatchDefault.choiceOnConnect(everConnected: false), true)
    }

    func test_afterThatThePersonsChoiceIsKept() {
        XCTAssertNil(WatchDefault.choiceOnConnect(everConnected: true))
    }

    func test_aWatchThatIsNotConnectedNeverMeasures() {
        XCTAssertFalse(WatchDefault.measures(chosen: true, connected: false))
        XCTAssertFalse(WatchDefault.measures(chosen: false, connected: true))
        XCTAssertTrue(WatchDefault.measures(chosen: true, connected: true))
    }
}
