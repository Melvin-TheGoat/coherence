import XCTest
@testable import Coherence

/// The onboarding interview's arithmetic. These exist because screen 16c makes
/// the one numeric claim in the whole flow ("your 30-day streak lands Sept 4"),
/// and the spec's integrity rule is that it must be real arithmetic from the
/// user's own answer — not an invented goal date like the flow we modelled on.
final class OnboardingModelTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - Projection

    func test_streakDate_sevenDaysAWeek_isThirtyDaysOut() {
        let start = date(2026, 8, 5)
        let landed = OnboardingProjection.streakDate(daysPerWeek: 7, from: start, calendar: cal)
        XCTAssertEqual(landed, date(2026, 9, 4))
    }

    func test_streakDate_fewerDaysPerWeek_landsLater() {
        let start = date(2026, 8, 5)
        let daily = OnboardingProjection.streakDate(daysPerWeek: 7, from: start, calendar: cal)!
        let fiveADay = OnboardingProjection.streakDate(daysPerWeek: 5, from: start, calendar: cal)!
        let threeADay = OnboardingProjection.streakDate(daysPerWeek: 3, from: start, calendar: cal)!
        XCTAssertLessThan(daily, fiveADay)
        XCTAssertLessThan(fiveADay, threeADay)
    }

    func test_streakDate_fiveDaysAWeek_isFortyTwoDays() {
        // 30 days at 5/week = 6 weeks = 42 days. Checked by hand so a change
        // to the rounding can't quietly move the date we print.
        let start = date(2026, 8, 5)
        XCTAssertEqual(OnboardingProjection.streakDate(daysPerWeek: 5, from: start, calendar: cal),
                       date(2026, 9, 16))
    }

    func test_streakDate_rejectsOutOfRangeCommitment() {
        let start = date(2026, 8, 5)
        XCTAssertNil(OnboardingProjection.streakDate(daysPerWeek: 0, from: start, calendar: cal))
        XCTAssertNil(OnboardingProjection.streakDate(daysPerWeek: 8, from: start, calendar: cal))
    }

    func test_weeklyCumulativeDays_risesAtTheChosenRate() {
        XCTAssertEqual(OnboardingProjection.weeklyCumulativeDays(daysPerWeek: 5), [5, 10, 15, 20])
        XCTAssertEqual(OnboardingProjection.weeklyCumulativeDays(daysPerWeek: 7), [7, 14, 21, 28])
        XCTAssertEqual(OnboardingProjection.weeklyCumulativeDays(daysPerWeek: 0), [])
    }

    // MARK: - Profile: every card must echo an answer

    func test_profile_echoesTheirOwnAnswers() {
        var a = OnboardingAnswers()
        a.motivations = [.moreDiscipline, .betterSleep]
        a.restarts = .lostCount
        a.anchor = .coffee
        a.causes = [.forgot, .couldntTell]

        let p = PracticeProfile(from: a)
        XCTAssertEqual(p.chasing, "More discipline")          // priority beats set order
        XCTAssertTrue(p.pattern.contains("more times"))
        XCTAssertEqual(p.anchorLine, "You practise with your morning coffee")
        // couldntTell outranks forgot: it's the one 808 answers most directly.
        XCTAssertEqual(p.blindSpot, "I couldn't tell it was working")
    }

    func test_profile_emptyAnswersStillProducesSayableCards() {
        // A user who skips everything must not get blank cards or a crash.
        let p = PracticeProfile(from: OnboardingAnswers())
        XCTAssertFalse(p.chasing.isEmpty)
        XCTAssertFalse(p.pattern.isEmpty)
        XCTAssertFalse(p.anchorLine.isEmpty)
        XCTAssertFalse(p.blindSpot.isEmpty)
    }

    // MARK: - Every dropout cause must have a feature that answers it

    func test_everyDropoutCauseHasAnAnswer() {
        // Screen 16d maps each stated cause to a feature. If a case is ever
        // added without an answer, this fails rather than shipping a blank row.
        for cause in DropoutCause.allCases {
            XCTAssertFalse(cause.answer.isEmpty, "\(cause) has no answering feature")
            XCTAssertFalse(cause.label.isEmpty)
        }
    }

    func test_everyAnchorHasAPhraseAndAPlausibleHour() {
        for anchor in Anchor.allCases {
            XCTAssertFalse(anchor.phrase.isEmpty)
            XCTAssertTrue((0...23).contains(anchor.defaultHour), "\(anchor) hour out of range")
        }
    }

    // MARK: - The cost, and the promise that answers it

    func test_primaryCost_prefersTheOneAConsistentPracticeSpeaksTo() {
        var a = OnboardingAnswers()
        a.costs = [.driftedFromPractice, .cantFocus]
        XCTAssertEqual(a.primaryCost, .cantFocus)
        a.costs.insert(.dontFinish)
        XCTAssertEqual(a.primaryCost, .dontFinish)
    }

    func test_primaryCost_isNilWhenNothingTicked() {
        // Nothing is required on that screen, so the commitment line has to
        // cope with an empty set rather than printing "So that ."
        XCTAssertNil(OnboardingAnswers().primaryCost)
    }

    func test_everyCostSymptomHasALabelAnEchoAndALens() {
        // The echo has to finish the sentence "So that ..." on the commitment
        // screen. A missing one would ship as a broken sentence, not a crash.
        for symptom in CostSymptom.allCases {
            XCTAssertFalse(symptom.label.isEmpty, "\(symptom) has no label")
            XCTAssertFalse(symptom.echo.isEmpty, "\(symptom) has no echo")
            XCTAssertFalse(symptom.echo.hasSuffix("."), "\(symptom) echo double-punctuates")
        }
        for lens in CostSymptom.Lens.allCases {
            XCTAssertFalse(CostSymptom.inLens(lens).isEmpty, "\(lens) has no symptoms")
        }
        XCTAssertEqual(CostSymptom.allCases.count, 9)
    }

    func test_primaryCause_prefersTheOneWeAnswerBest() {
        var a = OnboardingAnswers()
        a.causes = [.noTime, .gotBoring]
        XCTAssertEqual(a.primaryCause, .gotBoring)
        a.causes.insert(.tooManyChoices)
        XCTAssertEqual(a.primaryCause, .tooManyChoices)
        a.causes.insert(.couldntTell)
        XCTAssertEqual(a.primaryCause, .couldntTell)
    }
}
