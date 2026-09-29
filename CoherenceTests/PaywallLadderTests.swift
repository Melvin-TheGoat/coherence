import XCTest
@testable import Coherence

/// The ladder is where an honest app most easily turns into a manipulative one,
/// so its shape is asserted rather than trusted to review.
final class PaywallLadderTests: XCTestCase {

    /// Cheapest concession first: risk, then money. A ladder that opens with
    /// money has nothing left to offer and teaches people to wait for the
    /// discount.
    ///
    /// **Two rungs, and no more** (Melvin, 2026-09-22): a follow-up may only
    /// exist if it concedes something, and after the discount there is
    /// nothing left to concede.
    func test_rungsGoRiskThenMoney() {
        XCTAssertEqual(DownsellRung.allCases, [.trial, .halfMonth])
        XCTAssertEqual(DownsellRung.trial.next, .halfMonth)
        XCTAssertNil(DownsellRung.halfMonth.next, "the ladder must end")
        XCTAssertLessThanOrEqual(DownsellRung.allCases.count, 2)
    }

    /// **A rung may only sell an offer the product it buys can actually
    /// deliver.**
    ///
    /// A half-off-first-month rung shipped on 2026-08-18 and was removed on
    /// 2026-08-24: it sold `.monthly`, and a product carries exactly one
    /// introductory offer, which for the monthly product is the free week. So
    /// the screen promised a discount the purchase sheet would contradict.
    /// This test is the tripwire, because the mistake is invisible until a
    /// real purchase runs.
    func test_noTwoRungsSellTheSameProductWithDifferentOffers() {
        let plans = DownsellRung.allCases.map(\.plan)
        XCTAssertEqual(Set(plans).count, plans.count,
                       "two rungs sell the same product, so they cannot both carry their own intro offer")
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
        XCTAssertEqual(DownsellRung.halfMonth.plan, .monthHalf)
        XCTAssertEqual(DownsellRung.trial.plan, .monthTrial)
        let copy = DownsellRung.halfMonth.subtitle(plan: .monthHalf,
                                                   yearlyPrice: SubscriptionPlan.yearly.price)
        XCTAssertTrue(copy.contains(SubscriptionPlan.monthHalf.price), "it must state what you pay")
        XCTAssertTrue(copy.contains(SubscriptionPlan.monthly.price), "and what it renews at")
    }

    /// Every rung sells its own product, never the paywall's plain monthly:
    /// the paywall's monthly carries no trial (Aziz, 2026-09-26), so a rung
    /// selling it would promise an offer the purchase sheet contradicts.
    func test_rungsSellTheirOwnProducts() {
        for rung in DownsellRung.allCases {
            XCTAssertNotEqual(Store.ProductID.of(rung.plan), Store.ProductID.monthly)
            XCTAssertFalse(Store.ProductID.core.contains(Store.ProductID.of(rung.plan)),
                           "a rung's product must not be required, or a missing one stops the paywall selling")
        }
    }

    /// Half the month's price, every month since 2026-09-27, after a free
    /// trial. The rung must say both the trial and that it renews, and the
    /// strikethrough is the real monthly price it is half of.
    func test_theHalfPricePlanIsRealAndSaysItRenews() {
        XCTAssertEqual(SubscriptionPlan.monthHalf.price, "$3.99")
        XCTAssertEqual(SubscriptionPlan.monthly.price, "$7.99")
        XCTAssertTrue(SubscriptionPlan.monthHalf.cadence.contains("per month"))
        XCTAssertEqual(SubscriptionPlan.monthHalf.anchorPrice, SubscriptionPlan.monthly.price)
        let copy = DownsellRung.halfMonth.subtitle(plan: .monthHalf, yearlyPrice: SubscriptionPlan.yearly.price,
                                                   trialDays: 3)
        XCTAssertTrue(copy.contains("free"), "the rung must say the trial comes first")
        XCTAssertTrue(copy.lowercased().contains("renews"))
    }

    /// The half-price rung promises free days only when its own product
    /// gives this person some. With none (no free-trial offer on monthly50,
    /// or the trial already used), it states the price from today, and its
    /// button and cadence stop mentioning a trial.
    func test_theHalfPriceRungPromisesNoTrialItCannotGive() {
        let copy = DownsellRung.halfMonth.subtitle(plan: .monthHalf, yearlyPrice: SubscriptionPlan.yearly.price,
                                                   trialDays: nil)
        XCTAssertFalse(copy.lowercased().contains("free"), copy)
        XCTAssertTrue(copy.contains(SubscriptionPlan.monthHalf.price))
        XCTAssertTrue(copy.lowercased().contains("renews"))
        XCTAssertFalse(DownsellRung.halfMonth.cta(trialDays: nil).lowercased().contains("free"))
        XCTAssertTrue(DownsellRung.halfMonth.cta(trialDays: 3).lowercased().contains("free"))
        XCTAssertFalse(SubscriptionPlan.monthHalf.cadence(withTrial: false).contains("trial"))
        XCTAssertTrue(SubscriptionPlan.monthHalf.cadence(withTrial: true).contains("trial"))
        XCTAssertEqual(SubscriptionPlan.yearly.cadence(withTrial: false), SubscriptionPlan.yearly.cadence)
    }

    /// Only the two plans the paywall shows must load for it to sell. A
    /// missing Lifetime (no longer sold) or half-off year (no screen offers
    /// it) must not leave the paywall reading "Plans aren't loading" with the
    /// premium lock off.
    func test_onlyThePaywallsPlansAreRequired() {
        XCTAssertEqual(Set(Store.ProductID.core), [Store.ProductID.monthly, Store.ProductID.yearly])
        XCTAssertTrue(Store.ProductID.all.contains(Store.ProductID.lifetime),
                      "Lifetime still loads, so a past purchase restores")
    }

    func test_theDiscountIsRealAndSaysWhatItRenewsAt() {
        XCTAssertEqual(SubscriptionPlan.yearHalf.price, "$14.99")
        XCTAssertEqual(SubscriptionPlan.yearly.price, "$29.99")
        XCTAssertTrue(SubscriptionPlan.yearHalf.cadence.contains(SubscriptionPlan.yearly.price))
        XCTAssertEqual(SubscriptionPlan.yearHalf.anchorPrice, SubscriptionPlan.yearly.price)
    }

    /// The discounted year replaces the year on the paywall rather than
    /// sitting beside it: two yearly cards at two prices is a shell game.
    func test_theDiscountedYearTakesTheYearsPlace() {
        XCTAssertEqual(SubscriptionPlan.cards(selecting: .yearly), [.monthly, .yearly])
        XCTAssertEqual(SubscriptionPlan.cards(selecting: .yearHalf), [.monthly, .yearHalf])
        XCTAssertEqual(SubscriptionPlan.cards(selecting: .monthTrial), [.monthTrial, .yearly])
        XCTAssertEqual(SubscriptionPlan.cards(selecting: .monthHalf), [.monthHalf, .yearly])
    }

    /// The rules from the paywall above it apply the whole way down.
    func test_noManufacturedUrgency() {
        let banned = ["hurry", "expires", "last chance", "spots", "only today",
                      "never see", "act now", "% off"]
        for rung in DownsellRung.allCases {
            let text = (rung.title + " " + rung.cta + " "
                        + rung.subtitle(plan: .monthly,
                                        yearlyPrice: SubscriptionPlan.yearly.price)).lowercased()
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(rung) says '\(word)'")
            }
        }
    }

    /// Every anchor that exists must be above the price it anchors, or it is
    /// not a discount, it is a mistake someone will screenshot. Monthly
    /// deliberately has none since the 2026-08-25 reprice made its old anchor
    /// the real price.
    func test_anchorsAreHigherThanPrices() {
        func dollars(_ s: String) -> Double {
            Double(s.replacingOccurrences(of: "$", with: "")) ?? 0
        }
        for plan in SubscriptionPlan.allCases {
            guard let anchor = plan.anchorPrice else { continue }
            XCTAssertGreaterThan(dollars(anchor), dollars(plan.price),
                                 "\(plan)'s anchor is not above its price")
        }
        XCTAssertNil(SubscriptionPlan.monthly.anchorPrice,
                     "monthly sells AT its old anchor; striking it through would be a fake reference price")
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

        // "About $1.84 a week"
        XCTAssertEqual(monthly * 12 / 52, 1.84, accuracy: 0.02)
        XCTAssertTrue(SubscriptionPlan.monthly.note?.contains("$1.84") == true)
        // "$2.50 a month"
        XCTAssertEqual(yearly / 12, 2.50, accuracy: 0.01)
        XCTAssertTrue(SubscriptionPlan.yearly.note?.contains("$2.50") == true)
        // "less than one coffee" has to actually be a small number
        XCTAssertLessThan(yearly / 12, 4.0, "the coffee claim stopped being true")
        // "A year of monthly": 99.99 / 7.99 is 12.5 months, a year rounded the
        // honest direction (claiming less than it is, never more).
        XCTAssertEqual(lifetime / monthly, 12.5, accuracy: 0.2)
        XCTAssertGreaterThanOrEqual(lifetime / monthly, 12,
                                    "the note says a year; the ratio fell under one")
        // And the yearly is far under the monthly run-rate, which the ladder's
        // reframe rung leans on.
        XCTAssertLessThanOrEqual(yearly, monthly * 12 * 0.55)
    }

    /// The year rung must state auto-renewal in its own words: it advertises
    /// a subscription, and "paid once a year" alone reads as a one-time
    /// charge. (The weekly-cents reframe was dropped with the localized
    /// price: a cents figure computed from USD is wrong in every other
    /// currency.)
    func test_theMonthRungSaysItRenews() {
        let text = DownsellRung.halfMonth
            .subtitle(plan: .monthHalf, yearlyPrice: SubscriptionPlan.yearly.price)
            .lowercased()
        XCTAssertTrue(text.contains("renews"), "the month rung hides the renewal")
    }

    // MARK: Disclosures (2026-09-29, 3.1.2)

    /// The trial rung states the condition that decides the charge, not a
    /// promise about whether it helped.
    func test_theTrialRungStatesTheConditionForPayingNothing() {
        let text = DownsellRung.trial.subtitle(plan: .monthTrial, yearlyPrice: SubscriptionPlan.yearly.price)
        XCTAssertTrue(text.contains("24 hours"), text)
        XCTAssertFalse(text.lowercased().contains("help you"), text)
    }

    /// A card is named for the plan it buys. "Free trial" as the title of a
    /// card that renews at the monthly price read as a free card.
    func test_rungCardsAreNamedForThePlan() {
        XCTAssertEqual(SubscriptionPlan.monthTrial.title, "Monthly")
        XCTAssertEqual(SubscriptionPlan.monthHalf.title, "Monthly, half price")
        XCTAssertTrue(SubscriptionPlan.monthTrial.cadence(withTrial: true).contains("trial"),
                      "the trial is still stated, on the cadence line")
    }

    /// What a membership opens is said on the purchase screen, and only what
    /// this build contains: nothing about Block, hats, points or Otto's chat.
    func test_theIncludesLineNamesOnlyWhatThisBuildHas() {
        let line = PaywallScreen.includesLine
        for absent in ["block", "hats", "points", "shop", "chat"] {
            XCTAssertFalse(line.lowercased().contains(absent), absent)
        }
        XCTAssertEqual(line.contains("Friends"), FeatureFlags.friends)
        XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"), "no em dashes")
    }

    /// A Restore always says what happened, except where success simply
    /// opens the app.
    func test_restoreSaysWhatItFound() {
        XCTAssertNil(RestoreFeedback(entitled: true, synced: true))
        XCTAssertEqual(RestoreFeedback(entitled: true, synced: true, announceSuccess: true), .restored)
        XCTAssertEqual(RestoreFeedback(entitled: false, synced: true), .nothing)
        XCTAssertEqual(RestoreFeedback(entitled: false, synced: false), .failed)
        for f in [RestoreFeedback.restored, .nothing, .failed] {
            XCTAssertFalse((f.title + f.message).contains("\u{2014}"), f.title)
        }
    }
}
