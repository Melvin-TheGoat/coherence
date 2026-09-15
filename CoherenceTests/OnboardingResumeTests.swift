import XCTest
@testable import Coherence

/// Closing the app mid-onboarding resumes on the same screen, with the same
/// answers, instead of screen one.
final class OnboardingResumeTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "OnboardingResumeTests")!
        defaults.removePersistentDomain(forName: "OnboardingResumeTests")
    }

    private func sample(step: Int = 12, history: [Int] = [0, 1, 2], savedAt: Date = Date()) -> OnboardingResume {
        var answers = OnboardingAnswers()
        answers.firstName = "Aziz"
        answers.hasWatch = true
        return OnboardingResume(step: step, history: history, answers: answers, plan: "yearly",
                                  waitlistEmail: "", planRating: 4, reminderAllowed: true, savedAt: savedAt)
    }

    func test_roundTripsEverythingItSaves() {
        let saved = sample()
        saved.save(to: defaults)
        XCTAssertEqual(OnboardingResume.load(from: defaults), saved)
    }

    func test_nothingSavedMeansStartFromTheTop() {
        XCTAssertNil(OnboardingResume.load(from: defaults))
    }

    func test_clearForgetsIt() {
        sample().save(to: defaults)
        OnboardingResume.clear(from: defaults)
        XCTAssertNil(OnboardingResume.load(from: defaults))
    }

    func test_twoWeeksOldStartsOver() {
        sample(savedAt: Date().addingTimeInterval(-15 * 86_400)).save(to: defaults)
        XCTAssertNil(OnboardingResume.load(from: defaults), "stale answers belong to a different person")
        XCTAssertNil(defaults.data(forKey: OnboardingResume.key), "and the stale record is removed")
    }

    func test_ordinaryScreenResumesExactly() {
        let point = sample(step: 12, history: [0, 1, 2]).resumePoint(unresumable: [40, 41], fallback: 39)
        XCTAssertEqual(point.step, 12)
        XCTAssertEqual(point.history, [0, 1, 2])
    }

    /// A live practice session died with the app; reopen on the screen that
    /// leads into it, with Back still pointing somewhere sensible.
    func test_liveSessionReopensOnTheScreenBeforeIt() {
        let point = sample(step: 40, history: [0, 1, 38, 39]).resumePoint(unresumable: [40, 41], fallback: 39)
        XCTAssertEqual(point.step, 39)
        XCTAssertEqual(point.history, [0, 1, 38], "history ends where the fallback screen was entered from")
    }

    func test_resultsWithNoFallbackInHistoryStillLandSafely() {
        let point = sample(step: 41, history: [0, 40]).resumePoint(unresumable: [40, 41], fallback: 39)
        XCTAssertEqual(point.step, 39)
        XCTAssertEqual(point.history, [0])
    }

    /// The first screen must not offer a way to sign in: it skipped every
    /// screen including the paywall (PostHog, 2026-09-14).
    func test_firstScreenHasNoSignInLink() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Coherence/Onboarding/OnboardingInterview.swift"),
                                encoding: .utf8)
        let relief = source.components(separatedBy: "struct ReliefScreen").dropFirst().first?
            .components(separatedBy: "\nstruct ").first ?? ""
        XCTAssertFalse(relief.isEmpty)
        XCTAssertFalse(relief.contains("Already have an account"))
        XCTAssertFalse(relief.contains("onSignIn"))
    }
}

/// The next App Store build must not carry the unfinished Friends feature.
final class FeatureFlagTests: XCTestCase {
    func test_friendsIsOffForTheAppStoreUntil1_1() {
        XCTAssertFalse(FeatureFlags.friendsInRelease,
                       "Friends ships in 1.1 after RELEASE_CHECKLIST's 1.1 list; flip this only in that archive")
    }
}
