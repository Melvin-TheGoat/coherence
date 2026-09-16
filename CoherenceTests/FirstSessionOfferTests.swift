import XCTest
@testable import Coherence

@MainActor
final class FirstSessionOfferTests: XCTestCase {

    private func fresh() -> (FirstSessionOffer, UserDefaults) {
        let suite = "FirstSessionOfferTests." + UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return (FirstSessionOffer(defaults: d), d)
    }

    /// The first results screen is unlocked; after the paywall, nothing is.
    func test_coversUntilThePaywallHasBeenShown() {
        let (offer, _) = fresh()
        XCTAssertTrue(offer.covers)
        offer.requestPaywall()
        XCTAssertTrue(offer.due, "leaving a covered results screen asks for the paywall")
        offer.markShown()
        XCTAssertFalse(offer.covers, "coming back after the paywall is locked")
        XCTAssertFalse(offer.due)
    }

    /// A second launch reads the same answer off disk.
    func test_shownSurvivesRelaunch() {
        let (offer, defaults) = fresh()
        offer.markShown()
        let again = FirstSessionOffer(defaults: defaults)
        XCTAssertFalse(again.covers)
        XCTAssertFalse(again.due, "due is a live request, never persisted")
    }

    /// After the paywall, leaving a results screen asks for nothing.
    func test_noSecondPaywallRequest() {
        let (offer, _) = fresh()
        offer.markShown()
        offer.requestPaywall()
        XCTAssertFalse(offer.due)
    }

    /// The tour's Begin hands off to Home once, and the flag clears itself.
    func test_setupHandoffIsReadOnce() {
        let suite = "OnboardingHandoffTests." + UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        XCTAssertFalse(OnboardingHandoff.takeSetupRequest(d))
        OnboardingHandoff.requestSetup(d)
        XCTAssertTrue(OnboardingHandoff.takeSetupRequest(d))
        XCTAssertFalse(OnboardingHandoff.takeSetupRequest(d), "read once, then cleared")
    }
}
