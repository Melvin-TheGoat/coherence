import XCTest

/// The Ready screen's tape and typed field (`Shared/Session/SessionLength.swift`).
final class SessionLengthTests: XCTestCase {

    func test_theTapeRunsOpenThenEveryMinuteToAnHourThenTheLongOnes() {
        XCTAssertNil(SessionLength.values.first!, "Open sits at the left end")
        XCTAssertEqual(SessionLength.values[1], 1)
        XCTAssertEqual(SessionLength.values[60], 60)
        XCTAssertEqual(Array(SessionLength.values.suffix(3)), [75, 90, 120])
    }

    func test_everyTickFindsItself() {
        for (i, v) in SessionLength.values.enumerated() {
            XCTAssertEqual(SessionLength.nearestIndex(for: v), i)
        }
    }

    /// A typed length the tape does not carry rests on its nearest tick.
    func test_aTypedLengthRestsOnTheNearestTick() {
        XCTAssertEqual(SessionLength.values[SessionLength.nearestIndex(for: 100)], 90)
        XCTAssertEqual(SessionLength.values[SessionLength.nearestIndex(for: 68)], 75)
        XCTAssertEqual(SessionLength.values[SessionLength.nearestIndex(for: 500)], 120)
    }

    func test_typing() {
        XCTAssertEqual(SessionLength.typed("25").minutes, 25)
        XCTAssertEqual(SessionLength.typed("999").minutes, 600, "ten hours at most")
        XCTAssertTrue(SessionLength.typed("0").valid)
        XCTAssertNil(SessionLength.typed("0").minutes, "zero minutes is Open")
        XCTAssertFalse(SessionLength.typed("").valid, "an empty field keeps what was there")
    }

    func test_words() {
        XCTAssertEqual(SessionLength.clock(10), "10:00")
        XCTAssertEqual(SessionLength.clock(nil), "\u{221E}")
        XCTAssertEqual(SessionLength.words(1), "1 minute")
        XCTAssertEqual(SessionLength.words(45), "45 minutes")
        XCTAssertFalse(SessionLength.words(nil).contains("\u{2014}"), "no em dashes")
    }
}
