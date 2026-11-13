import XCTest
@testable import Coherence

/// "Who can see this?" on a session's page (Melvin, 2026-10-23: "default
/// friends").
final class SharingDefaultTests: XCTestCase {
    func test_aNewSessionStartsOnFriends() {
        XCTAssertTrue(SharingDefault.startsOnFriends(friendsOn: true, savedBefore: false, wasShared: false, hasProfile: true))
        // Before iCloud answers, it still leads with Friends.
        XCTAssertTrue(SharingDefault.startsOnFriends(friendsOn: true, savedBefore: false, wasShared: false, hasProfile: nil))
    }

    func test_noProfileStartsOnlyYou() {
        XCTAssertFalse(SharingDefault.startsOnFriends(friendsOn: true, savedBefore: false, wasShared: false, hasProfile: false))
    }

    func test_aSavedSessionStartsWhereItWasLeft() {
        XCTAssertFalse(SharingDefault.startsOnFriends(friendsOn: true, savedBefore: true, wasShared: false, hasProfile: true))
        XCTAssertTrue(SharingDefault.startsOnFriends(friendsOn: true, savedBefore: true, wasShared: true, hasProfile: true))
    }

    func test_neverFriendsWhenFriendsIsOff() {
        XCTAssertFalse(SharingDefault.startsOnFriends(friendsOn: false, savedBefore: false, wasShared: true, hasProfile: true))
    }
}
