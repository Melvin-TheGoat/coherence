import XCTest
@testable import Coherence

final class ReviewPromptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func test_neverInsideOnboarding() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(sessionCount: 10, onboardingComplete: false,
                                              lastAskedAt: nil, now: now))
    }

    func test_waitsForThreeSessions() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(sessionCount: 2, onboardingComplete: true,
                                              lastAskedAt: nil, now: now))
        XCTAssertTrue(ReviewPrompt.shouldAsk(sessionCount: 3, onboardingComplete: true,
                                             lastAskedAt: nil, now: now))
    }

    func test_cooldownHoldsForNinetyDays() {
        let recent = now.addingTimeInterval(-89 * 24 * 3600)
        XCTAssertFalse(ReviewPrompt.shouldAsk(sessionCount: 5, onboardingComplete: true,
                                              lastAskedAt: recent, now: now))
        let old = now.addingTimeInterval(-91 * 24 * 3600)
        XCTAssertTrue(ReviewPrompt.shouldAsk(sessionCount: 5, onboardingComplete: true,
                                             lastAskedAt: old, now: now))
    }

    /// The rule takes no score, no verdict, no sentiment. This test exists so
    /// nobody adds one: the signature is the guarantee.
    func test_ruleIsBlindToHowTheSessionWent() {
        let ask = ReviewPrompt.shouldAsk(sessionCount: 3, onboardingComplete: true,
                                         lastAskedAt: nil, now: now)
        XCTAssertTrue(ask)
    }
}
