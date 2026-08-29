import XCTest
@testable import Coherence

/// The onboarding interview must never ask a question whose premise the user
/// has already contradicted. These walk **every** answer permutation rather
/// than spot-checking, because the failure mode is a single wrong question on
/// a path nobody happened to click through.
final class OnboardingBranchTests: XCTestCase {

    /// Every baseline answer resolves to exactly one persona, and an
    /// unanswered baseline never crashes or invents one.
    func test_everyBaselineAnswerHasAPersona() {
        for frequency in CurrentFrequency.allCases {
            var a = OnboardingAnswers()
            a.currentFrequency = frequency
            XCTAssertFalse(a.interview.isEmpty, "\(frequency) produced no interview")
        }
        XCTAssertEqual(OnboardingAnswers().persona, .restarter,
                       "an unanswered baseline defaults to the broadest path")
    }

    /// THE BUG THIS FIXES. Someone who has never meditated must never be asked
    /// what made them stop, or how many times they've restarted.
    func test_newcomerIsNeverAskedAboutStopping() {
        var a = OnboardingAnswers()
        a.currentFrequency = .never
        XCTAssertEqual(a.persona, .newcomer)
        XCTAssertFalse(a.interview.contains(.causes), "asked a newcomer why they stopped")
        XCTAssertFalse(a.interview.contains(.restarts), "asked a newcomer how often they restarted")
        XCTAssertTrue(a.interview.contains(.intendedFor), "a newcomer should be asked how long they've meant to start")
    }

    /// Someone who already practices isn't "meaning to start", and shouldn't be
    /// quizzed on whether they can sit with their own thoughts.
    func test_regularIsNotTreatedAsABeginner() {
        for frequency in [CurrentFrequency.mostWeeks, .almostDaily] {
            var a = OnboardingAnswers()
            a.currentFrequency = frequency
            XCTAssertEqual(a.persona, .regular, "\(frequency)")
            XCTAssertFalse(a.interview.contains(.intendedFor), "\(frequency): asked when they'd start")
            XCTAssertFalse(a.interview.contains(.causes), "\(frequency): asked why they stopped")
            XCTAssertFalse(a.interview.contains(.restarts), "\(frequency): asked about restarts")
            XCTAssertFalse(a.interview.contains(.aloneWithThoughts), "\(frequency): condescending diagnostic")
            XCTAssertTrue(a.interview.contains(.blindSpot), "\(frequency): never asked what they can't see")
        }
    }

    /// The restarter is the only persona the consistency questions are for.
    func test_restarterGetsTheConsistencyQuestions() {
        for frequency in [CurrentFrequency.triedNeverStuck, .fewTimesMonth] {
            var a = OnboardingAnswers()
            a.currentFrequency = frequency
            XCTAssertEqual(a.persona, .restarter, "\(frequency)")
            XCTAssertTrue(a.interview.contains(.restarts))
            // .causes is now conditional on the restarts answer, so set one that
            // does not opt out.
            a.restarts = .few
            XCTAssertTrue(a.interview.contains(.causes))
            XCTAssertFalse(a.interview.contains(.intendedFor), "\(frequency): they've already started")
            XCTAssertFalse(a.interview.contains(.blindSpot), "\(frequency): that's the regular's question")
        }
    }

    /// Whatever the path, the screens that carry the product must always run.
    func test_everyPathKeepsTheLoadBearingScreens() {
        let required: [InterviewStep] = [.baseline, .motivation, .stress, .watchGate,
                                         .anchor, .you, .referral]
        for frequency in CurrentFrequency.allCases {
            var a = OnboardingAnswers()
            a.currentFrequency = frequency
            for step in required {
                XCTAssertTrue(a.interview.contains(step),
                              "\(frequency) lost \(step) — the Watch gate and the anchor are not optional")
            }
        }
    }

    /// Order is canonical on every path — no persona sees questions shuffled.
    func test_interviewOrderIsStable() {
        let canonical = InterviewStep.allCases
        for frequency in CurrentFrequency.allCases {
            var a = OnboardingAnswers()
            a.currentFrequency = frequency
            let indices = a.interview.map { canonical.firstIndex(of: $0)! }
            XCTAssertEqual(indices, indices.sorted(), "\(frequency) reordered the interview")
        }
    }

    /// The interview must stay short enough to finish. QUITTR spends ten
    /// questions on a user motivated by shame; ours is aspirational and can't.
    func test_noPathIsTooLong() {
        for frequency in CurrentFrequency.allCases {
            var a = OnboardingAnswers()
            a.currentFrequency = frequency
            XCTAssertLessThanOrEqual(a.interview.count, 11,
                                     "\(frequency) asks \(a.interview.count) questions")
        }
    }

    /// The review hook has to show each path honestly. A sample that fills a
    /// field the persona is never asked would hide the exact bug the payoff
    /// screens had: reading an answer nobody gave.
    func test_sampleAnswersOnlyFillWhatThePersonaIsAsked() {
        for persona in OnboardingPersona.allCases {
            let a = OnboardingAnswers.sample(persona)
            XCTAssertEqual(a.persona, persona, "sample(\(persona)) resolves elsewhere")

            let asked = Set(a.interview)
            if !asked.contains(.restarts) { XCTAssertNil(a.restarts, "\(persona)") }
            if !asked.contains(.intendedFor) { XCTAssertNil(a.intendedFor, "\(persona)") }
            if !asked.contains(.causes) { XCTAssertTrue(a.causes.isEmpty, "\(persona)") }
            if !asked.contains(.blindSpot) { XCTAssertNil(a.blindSpot, "\(persona)") }

            // And it must fill what they ARE asked, or the screens under review
            // render their empty state instead of the copy being reviewed.
            if asked.contains(.restarts) { XCTAssertNotNil(a.restarts, "\(persona)") }
            if asked.contains(.intendedFor) { XCTAssertNotNil(a.intendedFor, "\(persona)") }
            if asked.contains(.causes) { XCTAssertFalse(a.causes.isEmpty, "\(persona)") }
            if asked.contains(.blindSpot) { XCTAssertNotNil(a.blindSpot, "\(persona)") }
        }
    }

    /// Melvin hit this in the flow: he answered "It sticks" and was still asked
    /// what made him stop. The baseline decides the persona, but a later, more
    /// specific answer has to be allowed to overrule it.
    func test_itSticksIsNeverAskedWhatMadeThemStop() {
        for frequency in [CurrentFrequency.triedNeverStuck, .fewTimesMonth] {
            var a = OnboardingAnswers()
            a.currentFrequency = frequency
            a.restarts = .sticks
            XCTAssertEqual(a.persona, .restarter, "\(frequency)")
            XCTAssertFalse(a.interview.contains(.causes),
                           "\(frequency): asked why they stopped after they said it stuck")
            XCTAssertTrue(a.interview.contains(.restarts),
                          "\(frequency): the question they answered must still be asked")
        }
    }

    /// And the ordinary restarter still gets it, or the fix above quietly
    /// deletes the question for everyone.
    func test_anOrdinaryRestarterIsStillAskedWhyTheyStopped() {
        var a = OnboardingAnswers()
        a.currentFrequency = .triedNeverStuck
        a.restarts = .few
        XCTAssertTrue(a.interview.contains(.causes))
    }

    /// Exhaustive: every combination of baseline × restarts × intendedFor.
    /// No combination may produce a question the answers contradict.
    func test_everyPermutationIsCoherent() {
        var checked = 0
        for frequency in CurrentFrequency.allCases {
            for restarts in RestartCount.allCases {
                for intended in IntendedFor.allCases {
                    var a = OnboardingAnswers()
                    a.currentFrequency = frequency
                    a.restarts = restarts
                    a.intendedFor = intended
                    let shown = a.interview
                    checked += 1

                    if a.persona == .newcomer {
                        XCTAssertFalse(shown.contains(.causes),
                                       "newcomer/\(restarts)/\(intended) asked why they stopped")
                    }
                    if a.persona == .regular {
                        XCTAssertFalse(shown.contains(.intendedFor),
                                       "regular/\(restarts)/\(intended) asked when they'd start")
                    }
                    // A question is asked at most once.
                    XCTAssertEqual(Set(shown).count, shown.count,
                                   "\(frequency)/\(restarts)/\(intended) repeated a question")
                }
            }
        }
        XCTAssertEqual(checked, CurrentFrequency.allCases.count
                       * RestartCount.allCases.count
                       * IntendedFor.allCases.count)
    }
}
