import XCTest

/// What this phone remembers of Friends (2026-10-27, Melvin: friend awards,
/// and "nothing happened when aziz and i just finished a full week
/// together"). The ledger is what makes those awards and points last.
final class FriendsLedgerTests: XCTestCase {

    private func week(_ index: Int, done: String, goal: String = "g") -> TogetherWeek {
        TogetherWeek(goalID: goal, partner: "ana", partnerName: "Ana", index: index,
                     first: "2026-10-01", last: "2026-10-07", target: 3,
                     completedDay: done, seenAt: .distantPast)
    }

    func test_theFriendCountOnlyGrows_andTheFirstLookSaysSo() {
        var l = FriendsLedger()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(l.observe(friendCount: 2, now: t0), "the first look")
        XCTAssertFalse(l.observe(friendCount: 1, now: t0.addingTimeInterval(60)))
        XCTAssertEqual(l.friendCountReached, [t0, t0], "a removed friend takes nothing back")
        let t1 = t0.addingTimeInterval(3600)
        l.observe(friendCount: 3, now: t1)
        XCTAssertEqual(l.friendCountReached.last, t1)
    }

    /// The first look files old weeks quietly and still celebrates one from
    /// today or yesterday; after that, every new week is news.
    func test_weeksFirstLookFilesOldOnesQuietly() {
        var l = FriendsLedger()
        let first = l.observe(goalRunning: true,
                              finished: [week(0, done: "2026-10-01"), week(1, done: "2026-10-26")],
                              celebrateFrom: "2026-10-26")
        XCTAssertEqual(first.quiet.map(\.index), [0])
        XCTAssertEqual(first.new.map(\.index), [1])
        XCTAssertNotNil(l.firstGoalAt)

        let again = l.observe(goalRunning: true,
                              finished: [week(0, done: "2026-10-01"), week(1, done: "2026-10-26"),
                                         week(2, done: "2026-10-02")],
                              celebrateFrom: "2026-10-26")
        XCTAssertEqual(again.new.map(\.index), [2], "known weeks are never news twice; later weeks always are")
        XCTAssertTrue(again.quiet.isEmpty)
        XCTAssertEqual(l.weeks.count, 3)
        XCTAssertEqual(l.bonusPoints, 3 * FriendsLedger.pointsPerWeek)
        XCTAssertEqual(l.facts.weeksTogether.count, 3)
    }

    func test_anotherPersonStartsTheirOwnLedger() {
        var l = FriendsLedger()
        l.claim(for: "me")
        l.observe(friendCount: 4)
        l.claim(for: "me")
        XCTAssertEqual(l.friendCountReached.count, 4, "the same person keeps theirs")
        l.claim(for: "someone else")
        XCTAssertEqual(l, FriendsLedger(owner: "someone else"))
    }

    func test_itRoundTripsThroughTheDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FriendsLedgerTests"))
        defaults.removePersistentDomain(forName: "FriendsLedgerTests")
        var l = FriendsLedger()
        l.claim(for: "me")
        l.observe(friendCount: 1)
        _ = l.observe(goalRunning: false, finished: [week(0, done: "2026-10-26")], celebrateFrom: "2026-10-26")
        FriendsMemory.save(l, defaults)
        XCTAssertEqual(FriendsMemory.load(defaults), l)
        XCTAssertEqual(FriendsMemory.bonusPoints(defaults), FriendsLedger.pointsPerWeek)
        FriendsMemory.forget(defaults)
        XCTAssertEqual(FriendsMemory.load(defaults), FriendsLedger())
    }
}
