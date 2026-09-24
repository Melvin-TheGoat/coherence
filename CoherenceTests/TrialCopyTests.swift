import XCTest
@testable import Coherence

/// The trial's length is set in App Store Connect and read off the monthly
/// product (`Store.trialDays`); these pin how every screen says it, so a
/// change of trial length can never leave one line promising the old one.
final class TrialCopyTests: XCTestCase {

    func test_theLengthIsSaidTheSameWayEverywhere() {
        XCTAssertEqual(TrialCopy.length(3), "3 days")
        XCTAssertEqual(TrialCopy.length(7), "7 days")
        XCTAssertEqual(TrialCopy.length(1), "1 day")
        XCTAssertEqual(TrialCopy.spelled(3), "Three")
        XCTAssertEqual(TrialCopy.startButton(3), "Start 3 days free")
    }

    /// The ladder's trial rung states the real length, never a hardcoded one.
    func test_theTrialRungSaysTheStoresLength() {
        let three = DownsellRung.trial.subtitle(plan: .monthly, yearlyPrice: "$29.99", trialDays: 3)
        let seven = DownsellRung.trial.subtitle(plan: .monthly, yearlyPrice: "$29.99", trialDays: 7)
        XCTAssertTrue(three.hasPrefix("3 days free"), three)
        XCTAssertTrue(seven.hasPrefix("7 days free"), seven)
        for text in [three, seven, DownsellRung.trial.title, DownsellRung.trial.cta] {
            XCTAssertFalse(text.lowercased().contains("week"), text)
            XCTAssertFalse(text.contains("\u{2014}"), "no em dashes: \(text)")
        }
    }

    /// Premium only (2026-09-23): there is no free 808 for the ladder to end on.
    func test_premiumOnlyIsOn() {
        XCTAssertTrue(Monetization.premiumOnly)
    }
}
