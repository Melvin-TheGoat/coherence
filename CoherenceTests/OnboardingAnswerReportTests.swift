import XCTest

/// Onboarding answers reach analytics since 2026-10-13, and only some of
/// them. These pin which, so a new mapping cannot quietly send the stress
/// answer, the mind-wandering slider, or anything someone typed.
final class OnboardingAnswerReportTests: XCTestCase {

    /// Every question answered, including the ones that must never be sent,
    /// and typed text in every free field.
    private var everything: OnboardingAnswers {
        var a = OnboardingAnswers()
        a.motivations = [.sharperFocus, .lessStressed, .other]
        a.motivationOther = "SECRET typed goal"
        a.obstacles = [.phonePulls, .forget]
        a.stress = 0.9
        a.stressLevel = StressLevel.burntOut.rawValue
        a.mindWandering = 0.85
        a.recovery = .forDays
        a.role = .founder
        a.quietTime = .beforeBed
        a.habitHistory = .didntStick
        a.ageBracket = AgeRange.from25.rawValue
        a.currentFrequency = .fewTimesMonth
        a.firstName = "SECRET name"
        a.username = "SECRET handle"
        return a
    }

    private func props(_ step: String, _ a: OnboardingAnswers? = nil) -> [String: Any] {
        OnboardingAnswerReport.properties(forStep: step, answers: a ?? everything)
    }

    func test_eachQuestionSendsItsAnswer() {
        XCTAssertEqual(props("motivation")[OnboardingAnswerReport.Key.goals] as? [String],
                       ["lessStressed", "other", "sharperFocus"])
        XCTAssertEqual(props("obstacles")[OnboardingAnswerReport.Key.obstacles] as? [String],
                       ["forget", "phonePulls"])
        XCTAssertEqual(props("role")[OnboardingAnswerReport.Key.role] as? String, "founder")
        XCTAssertEqual(props("quietTime")[OnboardingAnswerReport.Key.quietTime] as? String, "beforeBed")
        XCTAssertEqual(props("habitHistory")[OnboardingAnswerReport.Key.habitHistory] as? String, "didntStick")
        XCTAssertEqual(props("age")[OnboardingAnswerReport.Key.age] as? String, "25 to 34")
        XCTAssertEqual(props("baseline")[OnboardingAnswerReport.Key.frequency] as? String, "fewTimesMonth")
        XCTAssertEqual(props("mindProfile")[OnboardingAnswerReport.Key.mindProfile] as? String,
                       MindProfile.of(everything).rawValue)
    }

    /// The closed list: these eight screens send an answer, every other
    /// screen sends none, the stress and mind-wandering screens above all.
    func test_onlyTheApprovedScreensSendAnswers() {
        let approved: Set = ["motivation", "obstacles", "role", "quietTime", "habitHistory",
                             "age", "baseline", "mindProfile"]
        let others = ["stress", "wandering", "recovery", "relief", "breath", "breathing",
                      "meetOtto", "questionCount", "didYouKnow", "buildingPlan", "lifeNumber",
                      "lifeDots", "goodNews", "paywall", "permission", "health", "signIn",
                      "profile", "tourHome", "referral", "you", "anchor"]
        for step in approved { XCTAssertFalse(props(step).isEmpty, "\(step) sends nothing") }
        for step in others { XCTAssertTrue(props(step).isEmpty, "\(step) must send nothing") }
    }

    /// One prefix, one value per key, and only keys from the list.
    func test_everyKeyIsAKnownOnboardingKey() {
        for step in ["motivation", "obstacles", "role", "quietTime", "habitHistory",
                     "age", "baseline", "mindProfile"] {
            for key in props(step).keys {
                XCTAssertTrue(OnboardingAnswerReport.Key.all.contains(key), "unknown key \(key)")
                XCTAssertTrue(key.hasPrefix("onboarding_"))
            }
        }
    }

    /// Nothing typed ever leaves: not the "Something else" goal's text, not
    /// the name, not the username. And no stress value rides along anywhere.
    func test_noTypedTextAndNoStressValueIsEverSent() {
        let all = ["motivation", "obstacles", "role", "quietTime", "habitHistory",
                   "age", "baseline", "mindProfile", "stress", "wandering"]
            .flatMap { props($0).values }
            .map { "\($0)" }
            .joined(separator: " ")
        XCTAssertFalse(all.contains("SECRET"))
        XCTAssertFalse(all.contains("0.9"))
        XCTAssertFalse(all.contains("0.85"))
        XCTAssertFalse(all.contains("burntOut"))
        XCTAssertFalse(all.contains("forDays"))
    }

    /// An unanswered question sends nothing rather than an empty value.
    func test_unansweredSendsNothing() {
        let blank = OnboardingAnswers()
        for step in ["motivation", "obstacles", "role", "quietTime", "habitHistory", "age", "baseline"] {
            XCTAssertTrue(props(step, blank).isEmpty, "\(step) sent something unanswered")
        }
    }

    /// An older resume record's "25–34" is sent as today's label, so one
    /// bracket is one value in the data.
    func test_ageIsSentInOneFormat() {
        var a = OnboardingAnswers()
        a.ageBracket = "25\u{2013}34"
        XCTAssertEqual(props("age", a)[OnboardingAnswerReport.Key.age] as? String, "25 to 34")
        a.ageBracket = "Prefer not to say"
        XCTAssertEqual(props("age", a)[OnboardingAnswerReport.Key.age] as? String, "Prefer not to say")
    }
}
