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

    /// Being new only keeps someone out of The Comeback, whose line assumes a
    /// history; a specific obstacle still names them (phone + never meditated
    /// is Always-On, Aziz 2026-09-25).
    func test_aNewcomerIsNeverTheComeback() {
        XCTAssertEqual(MindProfile.of(answers { $0.currentFrequency = .never; $0.obstacles = [.phonePulls] }), .alwaysOn)
        XCTAssertEqual(MindProfile.of(answers { $0.currentFrequency = .never; $0.obstacles = [.forget] }), .freshStart)
        XCTAssertEqual(MindProfile.of(answers { $0.currentFrequency = nil; $0.habitHistory = .firstTry }), .freshStart)
        XCTAssertEqual(MindProfile.of(answers { $0.obstacles = [.unsureDoingItRight] }), .freshStart)
        for f in CurrentFrequency.allCases where f == .never {
            for o in Obstacle.allCases {
                XCTAssertNotEqual(MindProfile.of(answers { $0.currentFrequency = f; $0.obstacles = [o] }), .comeback)
            }
        }
    }

    func test_everyDayIsNeverComingBack() {
        XCTAssertNotEqual(MindProfile.of(answers { $0.currentFrequency = .almostDaily; $0.obstacles = [.forget] }), .comeback)
    }

    func test_obstaclesDecideInOrder() {
        XCTAssertEqual(MindProfile.of(answers { $0.obstacles = [.phonePulls, .mindWontSettle] }), .alwaysOn)
        XCTAssertEqual(MindProfile.of(answers { $0.obstacles = [.mindWontSettle, .noTime] }), .racingMind)
        XCTAssertEqual(MindProfile.of(answers { $0.motivations = [.overthinkLess] }), .racingMind)
        XCTAssertEqual(MindProfile.of(answers { $0.obstacles = [.noTime, .forget] }), .fullPlate)
        XCTAssertEqual(MindProfile.of(answers { $0.obstacles = [.forget] }), .comeback)
        XCTAssertEqual(MindProfile.of(answers { $0.obstacles = [.loseMotivation] }), .comeback)
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
