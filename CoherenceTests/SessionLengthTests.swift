import XCTest

/// The Ready screen's tape and typed field (`Shared/Session/SessionLength.swift`).
final class SessionLengthTests: XCTestCase {

    /// Aziz, 2026-09-22: five is the shortest, and left of five is ∞.
    func test_theTapeRunsOpenThenEveryMinuteFromFiveToTwoHours() {
        XCTAssertNil(SessionLength.values.first!, "Open sits at the left end")
        XCTAssertEqual(SessionLength.values[1], 5, "left of five is Open")
        XCTAssertEqual(SessionLength.values.compactMap { $0 }.min(), 5)
        XCTAssertEqual(SessionLength.values[56], 60)
        XCTAssertEqual(SessionLength.values.last!, 120)
        XCTAssertEqual(SessionLength.values.count, 1 + 116, "every minute, no jumps")
    }

    func test_everyTickFindsItself() {
        for (i, v) in SessionLength.values.enumerated() {
            XCTAssertEqual(SessionLength.nearestIndex(for: v), i)
        }
    }

    /// A typed length the tape does not carry rests on its nearest tick.
    func test_aTypedLengthRestsOnTheNearestTick() {
        XCTAssertEqual(SessionLength.values[SessionLength.nearestIndex(for: 100)], 100)
        XCTAssertEqual(SessionLength.values[SessionLength.nearestIndex(for: 300)], 120)
    }

    func test_typing() {
        XCTAssertEqual(SessionLength.typed("25").minutes, 25)
        XCTAssertEqual(SessionLength.typed("3").minutes, 5, "under five becomes five")
        XCTAssertEqual(SessionLength.typed("999").minutes, 600, "ten hours at most")
        XCTAssertTrue(SessionLength.typed("0").valid)
        XCTAssertNil(SessionLength.typed("0").minutes, "zero minutes is Open")
        XCTAssertFalse(SessionLength.typed("").valid, "an empty field keeps what was there")
    }

    /// A 2 minute default saved before the floor opens on 5.
    func test_anOldShortDefaultReadsAsFive() {
        XCTAssertEqual(SessionLength.clamped(2), 5)
        XCTAssertNil(SessionLength.clamped(nil))
        XCTAssertEqual(SessionLength.values[SessionLength.nearestIndex(for: 3)], 5)
    }

    /// Five is also what opens Block's apps, so a timed sit always counts.
    func test_theShortestTimedSessionOpensBlock() {
        XCTAssertEqual(SessionLength.shortest, Blocker.sessionMinutes)
    }

    func test_theEndNotificationTitle() {
        XCTAssertEqual(SessionLength.endTitle(minutes: 10), "That's 10 minutes")
        XCTAssertEqual(SessionLength.endTitle(minutes: 60), "That's an hour")
    }

    func test_words() {
        XCTAssertEqual(SessionLength.clock(10), "10:00")
        XCTAssertEqual(SessionLength.clock(nil), "\u{221E}")
        XCTAssertEqual(SessionLength.words(5), "5 minutes")
        XCTAssertEqual(SessionLength.words(45), "45 minutes")
        XCTAssertFalse(SessionLength.words(nil).contains("\u{2014}"), "no em dashes")
    }
}
