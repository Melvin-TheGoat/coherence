import XCTest
@testable import Coherence

/// The onboarding funnel in PostHog is read by screen name, not by the Swift
/// case name. A screen without a name shows up as "??" in a dashboard, which
/// is how a new screen would silently become unreadable.
final class AnalyticsScreenNamesTests: XCTestCase {

    func test_everyOnboardingScreenHasAReadableName() {
        var seen = Set<String>()
        for step in OnboardingView.Step.allCases {
            let id = String(describing: step)
            let name = Analytics.onboardingScreenName(for: id)
            XCTAssertFalse(name.hasPrefix("??"), "Screen `\(id)` has no readable analytics name")
            XCTAssertTrue(seen.insert(name).inserted, "Two screens share the analytics name `\(name)`")
        }
    }

    func test_onboardingStepCarriesBothTheRoutingIDAndTheScreenName() {
        let props = Analytics.Event.onboardingStep(id: "watchGate").properties
        XCTAssertEqual(props["step"], "watchGate")
        XCTAssertEqual(props["screen"], "12 Do you have an Apple Watch?")
    }

    func test_unknownScreenIsVisiblyUnnamed() {
        XCTAssertTrue(Analytics.onboardingScreenName(for: "somethingNew").hasPrefix("??"))
    }
}
