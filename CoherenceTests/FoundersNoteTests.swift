import XCTest
@testable import Coherence

/// The founders' note opens once after a member's second session, may come
/// back once a week later, and never on the day Apple's rating sheet asked.
final class FoundersNoteTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 3600

    private func due(sessions: Int = 2, onboarded: Bool = true, shown: [Date] = [],
                     done: Bool = false, rating: Date? = nil) -> Bool {
        FoundersNote.due(sessionsRun: sessions, onboardingComplete: onboarded, shown: shown,
                         done: done, lastRatingAskAt: rating, now: now)
    }

    func test_opensFromTheSecondSession() {
        XCTAssertFalse(due(sessions: 0))
        XCTAssertFalse(due(sessions: 1))
        XCTAssertTrue(due(sessions: 2))
        XCTAssertTrue(due(sessions: 30))
    }

    func test_neverDuringOnboarding() {
        XCTAssertFalse(due(onboarded: false))
    }

    func test_maybeLaterComesBackOnceAWeekLater() {
        XCTAssertFalse(due(shown: [now.addingTimeInterval(-6 * day)]))
        XCTAssertTrue(due(shown: [now.addingTimeInterval(-7 * day)]))
        XCTAssertFalse(due(shown: [now.addingTimeInterval(-30 * day), now.addingTimeInterval(-20 * day)]))
    }

    func test_aReviewOrAMessageEndsIt() {
        XCTAssertFalse(due(done: true))
        XCTAssertTrue(FoundersNote.Answer.review.isFinal)
        XCTAssertTrue(FoundersNote.Answer.feedback.isFinal)
        XCTAssertFalse(FoundersNote.Answer.later.isFinal)
        XCTAssertFalse(FoundersNote.Answer.dismissed.isFinal)
    }

    func test_neverTheSameDayAsApplesRatingSheet() {
        XCTAssertFalse(due(rating: now.addingTimeInterval(-2 * 3600)))
        XCTAssertTrue(due(rating: now.addingTimeInterval(-25 * 3600)))
    }

    func test_storageRoundTrip() {
        let defaults = UserDefaults(suiteName: "FoundersNoteTests")!
        defaults.removePersistentDomain(forName: "FoundersNoteTests")
        XCTAssertEqual(FoundersNote.shownAt(defaults), [])
        FoundersNote.recordShown(now: now, defaults)
        XCTAssertEqual(FoundersNote.shownAt(defaults), [now])
        FoundersNote.record(.later, defaults)
        XCTAssertFalse(FoundersNote.isDone(defaults))
        FoundersNote.record(.review, defaults)
        XCTAssertTrue(FoundersNote.isDone(defaults))
        defaults.removePersistentDomain(forName: "FoundersNoteTests")
    }
}
