import XCTest
@testable import Coherence

/// The ladder is where an honest app most easily turns into a manipulative one,
/// so its shape is asserted rather than trusted to review.
final class PaywallLadderTests: XCTestCase {

    /// **The free trial is an upsell** (Melvin, 2026-09-29: "we want them to
    /// not know it exists unless they deny the initial offer"). A "no" is
    /// answered first with the 3-day trial, then with half price after a
    /// 3-day trial.
    ///
    /// A follow-up may only exist if it concedes something (2026-09-22), and
    /// after the discount there is nothing left to concede, so the ladder
    /// can never grow past two.
    func test_theLadderIsTheTrialThenHalfPrice() {
        XCTAssertEqual(DownsellRung.ladder, [.trial, .halfMonth])
        XCTAssertEqual(DownsellRung.trial.next, .halfMonth)
        XCTAssertNil(DownsellRung.halfMonth.next, "the ladder must end")
        XCTAssertLessThanOrEqual(DownsellRung.ladder.count, 2)
        XCTAssertEqual(DownsellRung.trial.plan, .monthTrial)
        XCTAssertEqual(DownsellRung.halfMonth.plan, .monthHalf)
    }

    /// Both rungs sell their own products, and both must restore and entitle.
    func test_bothRungProductsRestore() {
        XCTAssertTrue(Store.ProductID.all.contains(Store.ProductID.monthTrial))
        XCTAssertTrue(Store.ProductID.all.contains(Store.ProductID.yearTrial))
        XCTAssertTrue(Store.ProductID.all.contains(Store.ProductID.monthHalf))
    }

    /// Taking the free trial offers it on BOTH Monthly and Yearly (Melvin,
    /// 2026-09-29), each in its own card's place, never beside it: two yearly
    /// cards at one price is a shell game. Lifetime is never swapped.
    func test_theTrialRungPutsTheTrialOnBothPlans() {
        let expected: [SubscriptionPlan] = [.monthTrial, .yearTrial, .lifetime]
        XCTAssertEqual(SubscriptionPlan.cards(selecting: .monthTrial), expected)
        XCTAssertEqual(SubscriptionPlan.cards(selecting: .yearTrial), expected)
        XCTAssertTrue(SubscriptionPlan.yearTrial.designedWithTrial)
        XCTAssertEqual(SubscriptionPlan.yearTrial.title, "Yearly")
        XCTAssertEqual(SubscriptionPlan.yearTrial.price, SubscriptionPlan.yearly.price)
        XCTAssertEqual(SubscriptionPlan.yearTrial.anchorPrice, SubscriptionPlan.yearly.anchorPrice,
                       "the same yearly plan carries the same true reference price")
        XCTAssertEqual(Store.ProductID.of(.yearTrial), "com.lockout.meditate808.yearlytrial")
    }

    /// The trial rung states what BOTH plans turn into after the free days
    /// when the yearly one exists, and only the monthly's when it does not.
    func test_theTrialRungStatesBothPrices() {
        let both = DownsellRung.trial.subtitle(plan: .yearTrial, yearlyPrice: "$29.99",
                                               trialPlanPrice: "$7.99", trialYearPrice: "$29.99",
                                               trialDays: 3)
        XCTAssertTrue(both.contains("$29.99 a year or $7.99 a month"), both)
        let monthOnly = DownsellRung.trial.subtitle(plan: .monthTrial, yearlyPrice: "$29.99",
                                                    trialPlanPrice: "$7.99", trialDays: 3)
        XCTAssertTrue(monthOnly.contains("then $7.99 a month."), monthOnly)
        XCTAssertFalse(monthOnly.contains("a year"), monthOnly)
    }

    /// The first rung is the first thing said after a "no", so it cannot open
    /// as though a rung came before it.
    /// Someone who already used a free trial skips the trial rung, so half
    /// price is the first thing they hear and must not open "Then".
    func test_halfPriceShownFirstDoesNotOpenWithThen() {
        XCTAssertFalse(DownsellRung.halfMonth.title(first: true).hasPrefix("Then"))
        XCTAssertTrue(DownsellRung.halfMonth.title(first: false).hasPrefix("Then"))
    }

    func test_theFirstRungDoesNotFollowAnother() {
        let first = DownsellRung.ladder[0]
        XCTAssertFalse(first.title.hasPrefix("Then"), first.title)
        XCTAssertFalse(first.title.contains("\u{2014}"), "no em dashes")
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
        var current: DownsellRung? = DownsellRung.ladder.first
        var steps = 0
        while let rung = current {
            XCTAssertTrue(seen.insert(rung).inserted, "\(rung) appeared twice")
            current = rung.next
            steps += 1
            XCTAssertLessThan(steps, 10, "the ladder loops")
        }
        XCTAssertEqual(steps, DownsellRung.ladder.count)
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
    /// a product carries one introductory offer, and the monthly's is the
    /// paywall's own free trial, so a rung selling it could not also carry
    /// its discount.
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
        XCTAssertFalse(SubscriptionPlan.monthHalf.cadence(withTrial: false).contains("trial"))
        XCTAssertTrue(SubscriptionPlan.monthHalf.cadence(withTrial: true).contains("trial"))
        XCTAssertEqual(SubscriptionPlan.yearly.cadence(withTrial: false), SubscriptionPlan.yearly.cadence)
    }

    /// Only the two subscriptions must load for the paywall to sell. A
    /// missing Lifetime (its card hides) or half-off year (no screen offers
    /// it) must not leave everybody on "Plans aren't loading", which since
    /// 2026-09-29 is a locked app, not an open one.
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
    /// A rung's plan takes the monthly's place the same way; the trial rung
    /// takes both places, with the trial on each.
    func test_theDiscountedYearTakesTheYearsPlace() {
        XCTAssertEqual(SubscriptionPlan.cards(selecting: .yearly), [.monthly, .yearly, .lifetime])
        XCTAssertEqual(SubscriptionPlan.cards(selecting: .yearHalf), [.monthly, .yearHalf, .lifetime])
        XCTAssertEqual(SubscriptionPlan.cards(selecting: .monthTrial), [.monthTrial, .yearTrial, .lifetime])
        XCTAssertEqual(SubscriptionPlan.cards(selecting: .monthHalf), [.monthHalf, .yearly, .lifetime])
    }

    // MARK: Lifetime is back (Melvin, 2026-09-29: "that should def be a thing")

    /// Lifetime is the third card whatever is selected, and nothing ever
    /// takes its place: a rung replaces the monthly (and the trial rung the
    /// yearly too, with its own trial plan).
    func test_lifetimeIsAlwaysTheThirdCard() {
        for plan in SubscriptionPlan.allCases {
            let cards = SubscriptionPlan.cards(selecting: plan)
            XCTAssertEqual(cards.count, 3, "\(plan)")
            XCTAssertEqual(cards.last, .lifetime, "\(plan)")
            XCTAssertEqual(cards.filter { $0 == .lifetime }.count, 1, "\(plan)")
        }
        XCTAssertEqual(SubscriptionPlan.cards(selecting: DownsellRung.trial.plan),
                       [.monthTrial, .yearTrial, .lifetime], "the trial is on both plans")
        XCTAssertEqual(SubscriptionPlan.cards(selecting: DownsellRung.halfMonth.plan),
                       [.monthHalf, .yearly, .lifetime], "half price replaces the monthly card only")
    }

    /// One charge, today, nothing renews: the button and the terms say so,
    /// and neither mentions a trial or cancelling, which Lifetime has none of.
    func test_lifetimeIsOneChargeWithNoTrial() {
        XCTAssertFalse(SubscriptionPlan.lifetime.designedWithTrial)
        XCTAssertEqual(SubscriptionPlan.lifetime.cadence(withTrial: true), "once")
        XCTAssertEqual(PaywallScreen.buyButtonTitle(for: .lifetime, trialDays: 3), "Buy Lifetime")
        let terms = PaywallScreen.terms(for: .lifetime, priceLine: "$99.99 once", trialDays: 3)
        XCTAssertEqual(terms, "$99.99 once, charged today. Nothing renews.")
        for word in ["trial", "free", "renews automatically", "cancel"] {
            XCTAssertFalse(terms.lowercased().contains(word), word)
        }
        XCTAssertNil(SubscriptionPlan.lifetime.anchorPrice, "Lifetime never sold at $199")
    }

    /// The subscriptions' terms say the trial, the price after it, that it
    /// renews, and where to cancel; without a trial, no free days are named.
    func test_subscriptionTermsSayWhatTheyRenewAt() {
        let trial = PaywallScreen.terms(for: .monthly, priceLine: "$7.99 per month", trialDays: 3)
        XCTAssertTrue(trial.hasPrefix("3 days free, then $7.99 per month."), trial)
        XCTAssertTrue(trial.contains("Renews automatically"), trial)
        XCTAssertTrue(trial.contains("Settings app"), trial)
        let none = PaywallScreen.terms(for: .yearly, priceLine: "$29.99 per year", trialDays: nil)
        XCTAssertFalse(none.lowercased().contains("free"), none)
        XCTAssertTrue(none.contains("Renews automatically"), none)
        XCTAssertEqual(PaywallScreen.buyButtonTitle(for: .monthly, trialDays: 3), "Start my free trial")
        XCTAssertEqual(PaywallScreen.buyButtonTitle(for: .yearly, trialDays: nil), "Continue")
        for text in [trial, none] {
            XCTAssertFalse(text.contains("\u{2014}"), "no em dashes")
        }
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

    // MARK: The free trial lives on the ladder only (2026-09-29)

    /// The paywall's own plans carry no trial; only the two rungs' plans are
    /// designed with one. Lifetime and the half-off year never are.
    func test_onlyTheRungPlansCarryTheTrial() {
        XCTAssertFalse(Monetization.freeTrial)
        XCTAssertFalse(SubscriptionPlan.monthly.designedWithTrial)
        XCTAssertFalse(SubscriptionPlan.yearly.designedWithTrial)
        XCTAssertTrue(SubscriptionPlan.monthTrial.designedWithTrial)
        XCTAssertTrue(SubscriptionPlan.monthHalf.designedWithTrial)
        XCTAssertFalse(SubscriptionPlan.lifetime.designedWithTrial)
        XCTAssertFalse(SubscriptionPlan.yearHalf.designedWithTrial)
        XCTAssertEqual(SubscriptionPlan.fallbackTrialDays, 3)
    }

    /// A card says "after the trial" only when this person's purchase of it
    /// would start with one, and never changes what Lifetime or the
    /// half-off year say.
    func test_aCardMentionsTheTrialOnlyWhenItGivesOne() {
        for plan in [SubscriptionPlan.monthly, .yearly, .monthTrial, .monthHalf, .yearTrial] {
            XCTAssertTrue(plan.cadence(withTrial: true).contains("after the trial"), "\(plan)")
            XCTAssertFalse(plan.cadence(withTrial: false).contains("trial"), "\(plan)")
        }
        XCTAssertEqual(SubscriptionPlan.monthly.cadence(withTrial: false), "per month")
        XCTAssertEqual(SubscriptionPlan.yearly.cadence(withTrial: false), "per year")
        for plan in [SubscriptionPlan.lifetime, .yearHalf] {
            XCTAssertEqual(plan.cadence(withTrial: true), plan.cadence)
            XCTAssertEqual(plan.cadence(withTrial: false), plan.cadence)
        }
    }

    /// The half-price rung states the trial its own product gives, in the
    /// App Store's length, and says nothing of one when it gives none.
    func test_theHalfPriceRungSaysItsOwnTrialLength() {
        let three = DownsellRung.halfMonth.subtitle(plan: .monthHalf, yearlyPrice: "$29.99", trialDays: 3)
        let seven = DownsellRung.halfMonth.subtitle(plan: .monthHalf, yearlyPrice: "$29.99", trialDays: 7)
        XCTAssertTrue(three.hasPrefix("3 days free, then $3.99 a month"), three)
        XCTAssertTrue(seven.hasPrefix("7 days free"), seven)
        let euros = DownsellRung.halfMonth.subtitle(plan: .monthHalf, yearlyPrice: "29,99 €",
                                                    monthlyPrice: "7,99 €", halfMonthPrice: "3,99 €",
                                                    trialDays: 3)
        XCTAssertTrue(euros.contains("3,99 € a month instead of 7,99 €"), euros)
        XCTAssertFalse(euros.contains("$"), "a dollar figure beside a euro charge")
    }

    // MARK: The "was" price, every time (2026-09-29)

    /// The anchor is the same reference price in the live product's own
    /// currency: the live price scaled by the dollar anchor-to-price ratio,
    /// snapped to the live price's own ending.
    func test_theAnchorScalesIntoTheLiveCurrency() throws {
        let yearHalf = try XCTUnwrap(SubscriptionPlan.yearHalf.anchorRatio)
        XCTAssertEqual(Store.scaledAnchor(livePrice: Decimal(string: "14.99")!, ratio: yearHalf),
                       Decimal(string: "29.99")!)
        XCTAssertEqual(Store.scaledAnchor(livePrice: 2250, ratio: yearHalf), 4500,
                       "a whole price rounds to its own step")
        let monthHalf = try XCTUnwrap(SubscriptionPlan.monthHalf.anchorRatio)
        XCTAssertEqual(Store.scaledAnchor(livePrice: Decimal(string: "3.99")!, ratio: monthHalf),
                       Decimal(string: "7.99")!)
        XCTAssertEqual(Store.scaledAnchor(livePrice: Decimal(string: "2.99")!, ratio: monthHalf),
                       Decimal(string: "5.99")!, "a price with cents keeps its cents")
    }

    /// A struck-through "was" price only where it is a price 808 really
    /// charges (App Review pass, 2026-09-29): the half-price plans, beside
    /// the full plan's price. Yearly and Lifetime never sold at $59.99 or
    /// $199, and a fake reference price is a 5.6 / 3.1.2 rejection.
    func test_onlyRealPricesAreStruckThrough() {
        for plan in [SubscriptionPlan.yearly, .yearTrial, .lifetime, .monthly, .monthTrial] {
            XCTAssertNil(plan.anchorPrice, "\(plan) never sold at a higher price")
        }
        XCTAssertEqual(SubscriptionPlan.monthHalf.anchorPrice, SubscriptionPlan.monthly.price)
        XCTAssertEqual(SubscriptionPlan.yearHalf.anchorPrice, SubscriptionPlan.yearly.price)
    }

    /// In dollars, the scaled anchor is exactly the reference price the
    /// attorney cleared: the arithmetic may not move a cleared number.
    func test_inDollarsTheAnchorIsTheClearedPrice() {
        let dollars = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
        for plan in SubscriptionPlan.allCases {
            guard let cleared = plan.anchorPrice else { continue }
            let price = Decimal(string: plan.price.replacingOccurrences(of: "$", with: ""))!
            let live = Store.formattedAnchor(livePrice: price, plan: plan, style: dollars)
            XCTAssertEqual(live, cleared, "\(plan)")
        }
    }

    /// Formatted by the product's own currency style, never in dollars
    /// beside a euro price.
    func test_theAnchorIsSaidInTheLiveCurrency() {
        let euros = Decimal.FormatStyle.Currency(code: "EUR", locale: Locale(identifier: "de_DE"))
        let text = Store.formattedAnchor(livePrice: Decimal(string: "3.99")!, plan: .monthHalf, style: euros)
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("7,99") == true, text ?? "nil")
        XCTAssertTrue(text?.contains("€") == true, text ?? "nil")
        XCTAssertFalse(text?.contains("$") == true, text ?? "nil")

        let dollars = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(Store.formattedAnchor(livePrice: Decimal(string: "3.99")!, plan: .monthHalf,
                                             style: dollars), "$7.99")
        XCTAssertNil(Store.formattedAnchor(livePrice: Decimal(string: "29.99")!, plan: .yearly,
                                           style: dollars), "no anchor on Yearly")
    }

    /// Monthly sells at its old anchor, so it has none in any currency; and
    /// no anchor may come out at or under the price it strikes through.
    func test_noAnchorIsFakeInAnyCurrency() {
        let dollars = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
        XCTAssertNil(SubscriptionPlan.monthly.anchorRatio)
        XCTAssertNil(Store.formattedAnchor(livePrice: Decimal(string: "7.99")!, plan: .monthly, style: dollars))
        XCTAssertNil(SubscriptionPlan.monthTrial.anchorRatio)
        let prices: [Decimal] = [Decimal(string: "0.99")!, Decimal(string: "2.49")!, Decimal(string: "14.99")!,
                                 Decimal(string: "29.99")!, 30, 250, 999, 4500, 12000]
        for plan in SubscriptionPlan.allCases {
            guard let ratio = plan.anchorRatio else { continue }
            for price in prices {
                XCTAssertGreaterThan(Store.scaledAnchor(livePrice: price, ratio: ratio,
                                                        keepsCents: plan.anchorKeepsCents), price,
                                     "\(plan) at \(price)")
            }
        }
    }

    // MARK: Disclosures (2026-09-29, 3.1.2)

    /// The trial rung states the condition that decides the charge, not a
    /// promise about whether it helped.
    func test_theTrialRungStatesTheConditionForPayingNothing() {
        let text = DownsellRung.trial.subtitle(plan: .monthTrial, yearlyPrice: SubscriptionPlan.yearly.price)
        XCTAssertTrue(text.contains("24 hours"), text)
        XCTAssertFalse(text.lowercased().contains("help you"), text)
    }

    /// A rung buys nothing: it selects its plan and returns to the paywall,
    /// which sells it. So no rung's button may say it starts anything
    /// (App Review, 2026-09-29: "Start my free trial" started nothing).
    func test_rungButtonsChooseAndStartNothing() {
        for rung in DownsellRung.allCases {
            for days in [nil, 3] as [Int?] {
                let cta = rung.cta(trialDays: days)
                XCTAssertTrue(cta.hasPrefix("Choose"), cta)
                XCTAssertFalse(cta.lowercased().contains("start"), cta)
                XCTAssertFalse(cta.lowercased().contains("trial"), cta)
            }
        }
    }

    /// The trial rung says what the free days turn into, in the rung's own
    /// product's price (Apple's localized string when there is one).
    func test_theTrialRungStatesThePriceAfterTheTrial() {
        let dollars = DownsellRung.trial.subtitle(plan: .monthTrial, yearlyPrice: SubscriptionPlan.yearly.price,
                                                  trialDays: 3)
        XCTAssertTrue(dollars.contains("then \(SubscriptionPlan.monthTrial.price) a month"), dollars)
        let euros = DownsellRung.trial.subtitle(plan: .monthTrial, yearlyPrice: "29,99 €",
                                                trialPlanPrice: "7,99 €", trialDays: 3)
        XCTAssertTrue(euros.contains("then 7,99 € a month"), euros)
        XCTAssertFalse(euros.contains("$"), "a dollar figure beside a euro charge")
        XCTAssertFalse(euros.contains("\u{2014}"), "no em dashes")
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
    /// this build contains: Block, hats and Friends by their flags, never
    /// points (never sold) or Otto's chat.
    func test_theIncludesLineNamesOnlyWhatThisBuildHas() {
        let line = PaywallScreen.includesLine
        for absent in ["points", "shop", "chat"] {
            XCTAssertFalse(line.lowercased().contains(absent), absent)
        }
        XCTAssertEqual(line.contains("Block"), FeatureFlags.block)
        XCTAssertEqual(line.contains("hats"), FeatureFlags.shop)
        XCTAssertEqual(line.contains("Friends"), FeatureFlags.friends)
        XCTAssertTrue(line.hasPrefix("808 Premium: "), "the subscription is named before purchase (3.1.2)")
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
