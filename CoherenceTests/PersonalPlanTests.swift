import XCTest
@testable import Coherence

/// The interview asks thirteen questions. These prove the answers are read
/// back, which is the difference between a personalised flow and a decorative
/// one.
final class PersonalPlanTests: XCTestCase {

    private func answers(motivations: Set<Motivation> = [],
                         causes: Set<DropoutCause> = [],
                         frequency: CurrentFrequency = .triedNeverStuck) -> OnboardingAnswers {
        var a = OnboardingAnswers()
        a.currentFrequency = frequency
        a.motivations = motivations
        a.causes = causes
        return a
    }

    // MARK: Every pain point gets an answer

    /// The screen used to speak to ONE cause and drop the rest.
    func test_everyCauseNamedIsAnswered() {
        let all = Set(DropoutCause.allCases)
        let plan = PersonalPlan.answers(for: answers(causes: all))
        for cause in all {
            XCTAssertTrue(plan.contains { $0.concern == cause.label },
                          "\(cause) was collected and then never answered")
        }
    }

    /// Melvin's example: say accountability is the problem and the answer has
    /// to be the reminder and the community, not another chart.
    func test_accountabilityIsAnsweredByPeopleNotByData() {
        let plan = PersonalPlan.answers(for: answers(causes: [.noAccountability]))
        let item = plan.first { $0.concern == DropoutCause.noAccountability.label }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.pillar, .universal)
        XCTAssertTrue(item?.response.lowercased().contains("people") == true,
                      "accountability was answered without mentioning other people")
    }

    // MARK: The mission, all three thirds of it

    /// The flow was written when the mission was measurement alone. Whatever
    /// someone answers, habitual and universal must both get said.
    func test_allThreePillarsAlwaysAppear() {
        let cases: [OnboardingAnswers] = [
            answers(),
            answers(motivations: [.lessStressed]),
            answers(causes: [.couldntTell]),
            answers(motivations: Set(Motivation.allCases), causes: Set(DropoutCause.allCases)),
        ]
        for a in cases {
            let pillars = Set(PersonalPlan.answers(for: a).map(\.pillar))
            for pillar in PersonalPlan.Pillar.allCases {
                XCTAssertTrue(pillars.contains(pillar),
                              "\(pillar) never came up for \(a.motivations)/\(a.causes)")
            }
        }
    }

    /// Every response has to be a shipped feature, so nothing here may promise
    /// something the app does not do.
    func test_noAnswerIsEmptyOrDuplicated() {
        let a = answers(motivations: Set(Motivation.allCases),
                        causes: Set(DropoutCause.allCases))
        let plan = PersonalPlan.answers(for: a)
        var seen = Set<String>()
        for item in plan {
            XCTAssertFalse(item.concern.isEmpty)
            XCTAssertFalse(item.response.isEmpty)
            XCTAssertTrue(seen.insert(item.concern).inserted,
                          "\(item.concern) printed twice")
        }
    }

    // MARK: Outcomes on the build screen

    func test_outcomesReadBackInAFixedOrder() {
        let a = PersonalPlan.outcomeSentence(for: [.sharperFocus, .lessStressed])
        let b = PersonalPlan.outcomeSentence(for: [.lessStressed, .sharperFocus])
        XCTAssertEqual(a, b, "two people who picked the same things read different sentences")
        XCTAssertEqual(a, "Lowered stress, Sharper focus.")
    }

    func test_oneMotivationYieldsOneClause() {
        XCTAssertEqual(PersonalPlan.outcomeSentence(for: [.lessStressed]), "Lowered stress.")
    }

    /// Nothing selected, or only "something else", means we say nothing rather
    /// than print an empty flourish or invent what they meant.
    func test_nothingClaimableSaysNothing() {
        XCTAssertEqual(PersonalPlan.outcomeSentence(for: []), "")
        XCTAssertEqual(PersonalPlan.outcomeSentence(for: [.other]), "")
    }

    func test_otherIsCarriedIntoNoClaimAnywhere() {
        let plan = PersonalPlan.answers(for: answers(motivations: [.other]))
        XCTAssertFalse(plan.contains { $0.concern == "Something else" },
                       "we put words in the mouth of someone who said 'something else'")
    }
}
