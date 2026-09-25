import XCTest

/// The profile at the end of the questions is the reader's answers played
/// back. These pin who gets which type and which way each bar moves, so a
/// reordered rule cannot quietly tell a first-timer they are "coming back".
final class MindProfileTests: XCTestCase {
    private func answers(_ build: (inout OnboardingAnswers) -> Void) -> OnboardingAnswers {
        var a = OnboardingAnswers()
        a.currentFrequency = .fewTimesMonth
        build(&a)
        return a
    }

    func test_neverMeditatedIsAlwaysAFreshStart() {
        let a = answers { $0.currentFrequency = .never; $0.obstacles = [.phonePulls, .noTime] }
        XCTAssertEqual(MindProfile.of(a), .freshStart)
        let b = answers { $0.currentFrequency = nil; $0.habitHistory = .firstTry }
        XCTAssertEqual(MindProfile.of(b), .freshStart)
    }

    func test_obstaclesDecideInOrder() {
        XCTAssertEqual(MindProfile.of(answers { $0.obstacles = [.phonePulls, .mindWontSettle] }), .alwaysOn)
        XCTAssertEqual(MindProfile.of(answers { $0.obstacles = [.mindWontSettle, .noTime] }), .racingMind)
        XCTAssertEqual(MindProfile.of(answers { $0.motivations = [.overthinkLess] }), .racingMind)
        XCTAssertEqual(MindProfile.of(answers { $0.obstacles = [.noTime, .forget] }), .fullPlate)
        XCTAssertEqual(MindProfile.of(answers { $0.obstacles = [.forget] }), .comeback)
        XCTAssertEqual(MindProfile.of(answers { _ in }), .comeback)
    }

    func test_headspaceClutterMovesTheRightWay() {
        let calm = answers { $0.stress = 0.1 }
        let busy = answers { $0.stress = 0.9; $0.obstacles = [.mindWontSettle, .phonePulls] }
        XCTAssertGreaterThan(MindProfile.headspace(calm), MindProfile.headspace(busy))
        for a in [calm, busy] {
            XCTAssert((0.08...0.94).contains(MindProfile.headspace(a)))
        }
    }

    func test_balanceFollowsHowFastTheySettle() {
        let order: [StressRecovery] = [.rightAway, .withinHour, .allDay, .forDays]
        let values = order.map { r in MindProfile.balance(answers { $0.recovery = r }) }
        XCTAssertEqual(values, values.sorted(by: >))
    }

    func test_everyProfileHasNoEmDash() {
        for p in MindProfile.allCases {
            XCTAssertFalse(p.name.contains("\u{2014}") || p.line.contains("\u{2014}"), "\(p)")
        }
    }
}
