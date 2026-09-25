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

/// The "N years" arithmetic: their age bracket, 16 waking hours, their own
/// wandering estimate. Pinned so a changed constant cannot quietly move the
/// number we show someone.
final class MindWanderTests: XCTestCase {
    private func a(_ age: AgeRange?, _ share: Double?) -> OnboardingAnswers {
        var x = OnboardingAnswers()
        x.ageBracket = age?.rawValue
        x.mindWandering = share
        return x
    }

    func test_yearsFromAgeAndShare() {
        XCTAssertEqual(MindWander.years(a(.from25, 0.5)), 17)   // 50 left x 2/3 x 0.5
        XCTAssertEqual(MindWander.years(a(.from18, 0.7)), 28)   // 59 x 2/3 x 0.7
        XCTAssertEqual(MindWander.years(a(.from45, 0.3)), 6)    // 30 x 2/3 x 0.3
    }

    func test_noAgeMeansNoYearsButDaysAYear() {
        XCTAssertNil(MindWander.years(a(.notSaying, 0.5)))
        XCTAssertNil(MindWander.years(a(nil, 0.5)))
        XCTAssertEqual(MindWander.daysPerYear(a(nil, 0.5)), 122)
    }

    func test_wordStopsMapToShares() {
        XCTAssertEqual(WanderLevel.aboutHalf.share, MindWander.average)
        XCTAssertEqual(WanderLevel.allCases.map(\.share), WanderLevel.allCases.map(\.share).sorted())
        XCTAssertEqual(WanderLevel(share: 0.47), .aboutHalf)
        XCTAssertEqual(WanderLevel(share: 0.9), .almostAlways)
    }

    func test_aQuarterBack() {
        XCTAssertEqual(MindWander.quarterBack(a(.from25, 0.47)), 4)   // 16 / 4
        XCTAssertEqual(MindWander.quarterBack(a(.over55, 0.15)), 1)   // never 0
        XCTAssertEqual(MindWander.quarterBack(a(nil, 0.47)), 29)      // 114 days / 4
    }

    func test_oldAgeFormatStillReads() {
        var x = OnboardingAnswers()
        x.ageBracket = "25-34"
        XCTAssertEqual(MindWander.age(x), 30)
    }

    func test_unansweredUsesTheResearchAverage() {
        XCTAssertEqual(MindWander.share(a(.from25, nil)), 0.47)
    }
}
