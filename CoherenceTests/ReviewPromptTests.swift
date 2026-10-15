import XCTest
@testable import Coherence

final class ReviewPromptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 3600

    private func due(count: Int = 1, longest: Int = 1, onboarded: Bool = true,
                     asked: Set<ReviewPrompt.Moment> = [], last: Date? = nil) -> ReviewPrompt.Ask? {
        ReviewPrompt.due(sessionCount: count, longestStreak: longest, onboardingComplete: onboarded,
                         asked: asked, lastAskedAt: last, now: now)
    }

    func test_neverInsideOnboarding() {
        XCTAssertNil(due(count: 10, longest: 9, onboarded: false))
    }

    func test_neverBeforeAFirstSession() {
        XCTAssertNil(due(count: 0, longest: 0))
    }

    /// Melvin, 2026-10-15: ask after their first meditation.
    func test_theFirstMeditationAsks() {
        XCTAssertEqual(due(), .init(moment: .firstSession, covers: [.firstSession]))
    }

    func test_aSevenDayStreakAsksAgain() {
        XCTAssertNil(due(count: 6, longest: 6, asked: [.firstSession], last: now.addingTimeInterval(-8 * day)))
        XCTAssertEqual(due(count: 7, longest: 7, asked: [.firstSession], last: now.addingTimeInterval(-8 * day)),
                       .init(moment: .weekStreak, covers: [.weekStreak]))
    }

    /// Never two asks in a week. The streak earned six days after the first
    /// ask is owed, and asked once the week has passed, even if the streak
    /// has broken by then: it was earned.
    func test_noTwoAsksInAWeekButAnEarnedMomentWaits() {
        XCTAssertNil(due(count: 7, longest: 7, asked: [.firstSession], last: now.addingTimeInterval(-6 * day)))
        XCTAssertEqual(due(count: 9, longest: 7, asked: [.firstSession], last: now.addingTimeInterval(-9 * day))?.moment,
                       .weekStreak)
    }

    /// A member who already had a long streak before this rule is asked once
    /// for both, never twice for things that happened long ago.
    func test_aVeteranIsAskedOnceForEverythingBehindThem() {
        let ask = due(count: 80, longest: 21)
        XCTAssertEqual(ask, .init(moment: .weekStreak, covers: [.firstSession, .weekStreak]))
        XCTAssertNil(due(count: 81, longest: 21, asked: [.firstSession, .weekStreak],
                         last: now.addingTimeInterval(-10 * day)))
    }

    /// Someone asked under the old results-screen rule still gets the gap.
    func test_anOldAskStillCountsTowardTheGap() {
        XCTAssertNil(due(count: 12, longest: 3, last: now.addingTimeInterval(-2 * day)))
    }

    func test_regularsAreAskedAgainAboutEveryFourMonths() {
        let both: Set<ReviewPrompt.Moment> = [.firstSession, .weekStreak]
        XCTAssertNil(due(count: 40, longest: 12, asked: both, last: now.addingTimeInterval(-119 * day)))
        XCTAssertEqual(due(count: 40, longest: 12, asked: both, last: now.addingTimeInterval(-121 * day)),
                       .init(moment: .later, covers: []))
        // Someone who never reached a week still gets the later ask.
        XCTAssertEqual(due(count: 9, longest: 4, asked: [.firstSession],
                           last: now.addingTimeInterval(-121 * day))?.moment, .later)
    }

    /// The rule takes no score, no verdict, no sentiment. This test exists so
    /// nobody adds one: the signature is the guarantee. Asking only happy
    /// people is ratings manipulation and an App Review rejection.
    func test_ruleIsBlindToHowTheSessionWent() {
        XCTAssertNotNil(ReviewPrompt.due(sessionCount: 1, longestStreak: 1, onboardingComplete: true,
                                         asked: [], lastAskedAt: nil, now: now))
    }

    func test_recordingAnAskRemembersWhatItCovered() {
        let defaults = UserDefaults(suiteName: "ReviewPromptTests-\(UUID().uuidString)")!
        ReviewPrompt.record(.init(moment: .weekStreak, covers: [.firstSession, .weekStreak]), now: now, defaults)
        XCTAssertEqual(ReviewPrompt.askedMoments(defaults), [.firstSession, .weekStreak])
        XCTAssertEqual(ReviewPrompt.lastAskedAt(defaults), now)
        ReviewPrompt.record(.init(moment: .later, covers: []), now: now.addingTimeInterval(day), defaults)
        XCTAssertEqual(ReviewPrompt.askedMoments(defaults), [.firstSession, .weekStreak])
        XCTAssertEqual(ReviewPrompt.lastAskedAt(defaults), now.addingTimeInterval(day))
    }
}
