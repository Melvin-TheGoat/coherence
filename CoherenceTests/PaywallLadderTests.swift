import XCTest
@testable import Coherence

/// The ladder is where an honest app most easily turns into a manipulative one,
/// so its shape is asserted rather than trusted to review.
final class PaywallLadderTests: XCTestCase {

    /// Cheapest concession first: risk, then commitment, then price. A ladder
    /// that opens with money has nothing left to offer and teaches people to
    /// wait for the discount.
    func test_rungsGoRiskThenCommitmentThenPrice() {
        XCTAssertEqual(DownsellRung.allCases, [.trial, .firstMonthHalf, .yearReframe])
        XCTAssertEqual(DownsellRung.trial.next, .firstMonthHalf)
        XCTAssertEqual(DownsellRung.firstMonthHalf.next, .yearReframe)
        XCTAssertNil(DownsellRung.yearReframe.next, "the ladder must end")
    }

    /// No rung may repeat, or someone who declines is walked in a circle.
    func test_theLadderTerminates() {
        var seen: Set<DownsellRung> = []
        var current: DownsellRung? = .trial
        var steps = 0
        while let rung = current {
            XCTAssertTrue(seen.insert(rung).inserted, "\(rung) appeared twice")
            current = rung.next
            steps += 1
            XCTAssertLessThan(steps, 10, "the ladder loops")
        }
        XCTAssertEqual(steps, DownsellRung.allCases.count)
    }

    /// Each rung sells the plan it describes. A rung that talked about a year
    /// and charged for a month would be the deception the whole flow avoids.
    func test_eachRungSellsWhatItDescribes() {
        XCTAssertEqual(DownsellRung.yearReframe.plan, .yearly)
        XCTAssertEqual(DownsellRung.trial.plan, .monthly)
        XCTAssertEqual(DownsellRung.firstMonthHalf.plan, .monthly)
        XCTAssertTrue(DownsellRung.yearReframe.subtitle(plan: .yearly)
            .contains(SubscriptionPlan.yearly.price))
    }

    /// The rules from the paywall above it apply the whole way down.
    func test_noManufacturedUrgency() {
        let banned = ["hurry", "expires", "last chance", "spots", "only today",
                      "never see", "act now", "% off"]
        for rung in DownsellRung.allCases {
            let text = (rung.title + " " + rung.cta + " "
                        + rung.subtitle(plan: .monthly)).lowercased()
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(rung) says '\(word)'")
            }
        }
    }

    /// Every anchor must be above the price it anchors, or it is not a
    /// discount, it is a mistake someone will screenshot.
    func test_anchorsAreHigherThanPrices() {
        func dollars(_ s: String) -> Double {
            Double(s.replacingOccurrences(of: "$", with: "")) ?? 0
        }
        for plan in SubscriptionPlan.allCases {
            XCTAssertGreaterThan(dollars(plan.anchorPrice), dollars(plan.price),
                                 "\(plan)'s anchor is not above its price")
        }
    }

    /// Every per-unit claim is recomputed from the price beside it. This is the
    /// only pricing psychology in the flow and it earns its place by being
    /// true; a rounding that drifts turns it into a small lie printed at scale.
    func test_everyUnitFramingIsArithmetic() {
        func dollars(_ s: String) -> Double {
            Double(s.replacingOccurrences(of: "$", with: "")) ?? 0
        }
        let monthly = dollars(SubscriptionPlan.monthly.price)
        let yearly = dollars(SubscriptionPlan.yearly.price)
        let lifetime = dollars(SubscriptionPlan.lifetime.price)

        // "About 16 cents a day"
        XCTAssertEqual((monthly * 12 / 365) * 100, 16, accuracy: 1.0)
        // "$2.50 a month"
        XCTAssertEqual(yearly / 12, 2.50, accuracy: 0.01)
        XCTAssertTrue(SubscriptionPlan.yearly.note?.contains("$2.50") == true)
        // "less than one coffee" has to actually be a small number
        XCTAssertLessThan(yearly / 12, 4.0, "the coffee claim stopped being true")
        // "Ten months of monthly"
        XCTAssertEqual(lifetime / monthly, 10, accuracy: 0.2)
        // And the yearly really is half the monthly, which the note implies.
        XCTAssertLessThanOrEqual(yearly, monthly * 12 * 0.55)
    }

    /// The weekly reframe has to be arithmetic, not a flourish. Yearly divided
    /// by 52, to the nearest cent.
    func test_theWeeklyReframeIsTrue() {
        let yearly = Double(SubscriptionPlan.yearly.price.dropFirst()) ?? 0
        let weekly = yearly / 52
        let claimed = Double(DownsellRung.weeklyEquivalent
            .replacingOccurrences(of: " cents", with: "")) ?? 0
        XCTAssertEqual(weekly * 100, claimed, accuracy: 1.0,
                       "the weekly equivalent does not match the yearly price")
    }
}
