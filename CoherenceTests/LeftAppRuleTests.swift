import XCTest
import SwiftUI
@testable import Coherence

/// Leaving 808 mid-sit, and how long is forgiven.
///
/// Melvin, 2026-09-23: "if they leave for more than 10 seconds then the
/// meditation doesn't count." `LeftAppRule` is the whole of that decision,
/// pure and apart from `SessionCoordinator`, so it can be proven right with
/// no session actually running and no ten real seconds spent waiting.
final class LeftAppRuleTests: XCTestCase {

    // MARK: - The ten-second grace period

    func test_shortAbsenceCarriesOn() {
        XCTAssertEqual(LeftAppRule.verdict(awaySec: 9.9), .continues)
    }

    func test_longAbsenceVoidsTheSession() {
        XCTAssertEqual(LeftAppRule.verdict(awaySec: 10.1), .voided)
    }

    /// "Ten seconds or less" carries on — the boundary belongs to the person,
    /// not against them.
    func test_exactlyTenSecondsStillCarriesOn() {
        XCTAssertEqual(LeftAppRule.verdict(awaySec: 10.0), .continues)
    }

    func test_noTimeAwayCarriesOn() {
        XCTAssertEqual(LeftAppRule.verdict(awaySec: 0), .continues)
    }

    func test_farOverTheGraceVoids() {
        XCTAssertEqual(LeftAppRule.verdict(awaySec: 600), .voided)
    }

    // MARK: - What counts as leaving

    /// Control Center, the Notification Center swipe, a system alert: the
    /// app is momentarily not frontmost, but nobody left it.
    func test_inactiveIsNotLeaving() {
        XCTAssertFalse(LeftAppRule.isLeaving(.inactive))
    }

    func test_backgroundIsLeaving() {
        XCTAssertTrue(LeftAppRule.isLeaving(.background))
    }

    func test_activeIsNotLeaving() {
        XCTAssertFalse(LeftAppRule.isLeaving(.active))
    }

    // MARK: - Only a phone sit can be left

    /// A Watch sit is measured on the wrist regardless of what the phone's
    /// screen is doing, so the rule never applies to one.
    func test_watchSessionsAreExempt() {
        XCTAssertFalse(LeftAppRule.applies(engine: .watch))
    }

    func test_phoneSessionsAreJudged() {
        XCTAssertTrue(LeftAppRule.applies(engine: .phone))
    }
}
