import Foundation
import StoreKit

/// Everything 808 knows about being paid for.
///
/// StoreKit 2. One object owns product loading, purchase, restore, and the
/// answer to "is this person entitled", so there is exactly one place that
/// decides and exactly one place to look when it goes wrong.
///
/// **Read this before wiring anything to a screen.** The environment decides
/// whether money moves, not this code:
///
/// - Running from Xcode with a `.storekit` configuration selected: purchases
///   are local and fake. Nothing reaches Apple. This is how to develop.
/// - **TestFlight: purchases run against Apple's SANDBOX and no tester is ever
///   charged.** They are still real transactions though: entitlements are
///   granted, and subscriptions renew on an accelerated clock where a month
///   passes in minutes. "Nothing happens" is wrong; "no money moves" is right.
/// - App Store: identical code, real money.
///
/// When the plans cannot be fetched (offline, a slow sandbox, a build whose
/// bundle owns no products) `state` settles on `.unavailable`. **That never
/// opens the app** (Melvin, 2026-09-29): the paywall says the plans are not
/// loading and offers Try again, Restore and the Account link, and a payer
/// never meets it because their entitlement is read from StoreKit's
/// on-device record first. See `LaunchLock` and `PaywallScreen`.
@MainActor
final class Store: ObservableObject {

    /// Product identifiers, in one place because they are permanent.
    ///
    /// A product ID, once created in App Store Connect, can never be reused or
    /// renamed, the same way a bundle ID cannot. Do not create these under a
    /// personal developer account to "try it out": create them once, under the
    /// account that will actually sell the app.
    enum ProductID {
        static let monthly  = "com.lockout.meditate808.monthly"
        static let yearly   = "com.lockout.meditate808.yearly"
        static let lifetime = "com.lockout.meditate808.lifetime"
        /// The year at half price for the first year: its own product in the
        /// same subscription group, priced at the full yearly rate and
        /// carrying a first-year introductory offer. A product holds exactly
        /// one intro offer, which is why this cannot be the yearly one.
        static let yearHalf = "com.lockout.meditate808.yearly50"

        /// The ladder's rungs (2026-09-27), each carrying its own
        /// introductory offer.
        ///
        /// `monthTrial` is DORMANT since 2026-09-29 (Melvin): the paywall's
        /// own Monthly and Yearly carry the free trial again, so a rung
        /// offering the same trial on a copy of the monthly had nothing left
        /// to give. It stays in `all` so anybody who bought it still restores
        /// and stays entitled. `monthHalf` is the ladder's one rung: $3.99
        /// every month, starting with a free trial.
        static let monthTrial = "com.lockout.meditate808.monthlytrial"
        static let monthHalf = "com.lockout.meditate808.monthly50"

        static let all = [monthly, yearly, lifetime, yearHalf, monthTrial, monthHalf]
        /// What must load for the store to count as selling: the two
        /// subscriptions every paywall shows (Aziz, 2026-09-26). The rungs
        /// are NOT in it:
        /// until they exist in App Store Connect the ladder simply does not
        /// appear, where counting them would stop the whole paywall selling
        /// and, since 2026-09-29 (fail closed), leave everybody without a
        /// membership on "Plans aren't loading". Nor are Lifetime (a card
        /// again since 2026-09-29, hidden when its product did not load) and
        /// the half-off year (no screen offers it): both load when present
        /// and are never required.
        static let core = [monthly, yearly]

        static func of(_ plan: SubscriptionPlan) -> String {
            switch plan {
            case .monthly:  return monthly
            case .yearly:   return yearly
            case .lifetime: return lifetime
            case .yearHalf: return yearHalf
            case .monthTrial: return monthTrial
            case .monthHalf: return monthHalf
            }
        }
    }

    enum State: Equatable {
        case loading
        /// Products came back. The paywall can sell.
        case ready
        /// No products exist for this build, so there is nothing to sell.
        /// Expected before the Paid Apps agreement is signed, and also when
        /// the device is offline at the wrong moment.
        case unavailable
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var products: [Product] = []
    /// Does this person have an active subscription or the lifetime unlock?
    ///
    /// **This is the key to the whole app** (Aziz, 2026-08-11: "paying unlocks
    /// the entire app"). RootView locks to the paywall when the store is
    /// selling and this is false. StoreKit caches entitlements on device, so
    /// it stays correct offline, and it goes false by itself when a lapsed
    /// subscription expires, which is what re-locks the app.
    @Published private(set) var entitled = false
    /// Whether this person can still claim the free-trial introductory
    /// offer. The paywall must not promise free days to someone StoreKit will
    /// charge immediately: that is the difference between an offer and a lie,
    /// and reviewers check the claim against the purchase sheet.
    @Published private(set) var trialEligible = true
    /// How many days the free trial runs: the monthly product's introductory
    /// offer (the paywall's own trial since 2026-09-29), read when the
    /// products load, and the plan's fallback before that. Every line that
    /// states the trial's length reads this or `freeTrialDays(for:)`
    /// (`TrialCopy`), so App Store Connect is the one place it is set.
    @Published private(set) var trialDays = SubscriptionPlan.fallbackTrialDays
    /// Each loaded product's free-trial introductory offer, in days, keyed by
    /// product ID, for the offers this person is still eligible for. A
    /// product with no free-trial offer (or a pay-up-front one, like the
    /// half-off year), or one they already used, has no entry.
    @Published private(set) var freeTrialDaysByProduct: [String: Int] = [:]
    /// StoreKit's on-device record has been read at least once. Until it
    /// has, a payer and a stranger look the same, so the launch waits on it
    /// (`LaunchLock`) instead of flashing a payer the paywall. It is local
    /// and needs no network, so this turns true within moments of launch.
    @Published private(set) var entitlementKnown = false

    /// The free days buying `plan` would start with for THIS person, or nil
    /// when it starts with none: the product carries no free-trial offer, or
    /// StoreKit says they already used one. Before the plans load (a DEBUG
    /// demo, or never in Release, where nothing sells until `.ready`) a plan
    /// is assumed to carry the trial it is designed with.
    func freeTrialDays(for plan: SubscriptionPlan) -> Int? {
        guard state == .ready else {
            return plan.designedWithTrial ? SubscriptionPlan.fallbackTrialDays : nil
        }
        guard let days = freeTrialDaysByProduct[ProductID.of(plan)], days > 0 else {
            return nil
        }
        return days
    }

    /// Whether any screen may offer the free trial: 808 offers one at all
    /// (`Monetization.freeTrial`), and this person is still eligible (or the
    /// plans have not loaded, when eligibility is unknown).
    var trialOffered: Bool {
        Monetization.freeTrial && (trialEligible || state != .ready)
    }
    /// The invite reward's balance, attached by the app at launch
    /// (`RewardLedger`). nil on a store with no persistence (tests).
    var ledger: RewardLedger?

    #if DEBUG
    /// The review build's simulated purchase.
    ///
    /// On a build with no products the buy button cannot reach StoreKit, so
    /// the lock → trial → unlock loop was unreviewable: tapping "Start 7 days
    /// free" navigated and nothing changed. When the review switch
    /// (`previewFreeByDefault`) is on, "buying" sets this instead, so the
    /// unlock actually happens and the loop can be felt end to end. Persisted,
    /// so it survives relaunch the way a real purchase would; the switch to
    /// go back to free lives in Settings' DEBUG section. Compiled out of
    /// Release entirely.
    @Published private(set) var previewEntitled =
        UserDefaults.standard.bool(forKey: "previewEntitled.debug")

    func setPreviewEntitled(_ value: Bool) {
        previewEntitled = value
        UserDefaults.standard.set(value, forKey: "previewEntitled.debug")
    }
    #endif

    private var updates: Task<Void, Never>?

    init() {
        // Start listening BEFORE loading products. A purchase approved out of
        // band, by Ask to Buy or an interrupted transaction finishing later,
        // arrives on this stream and nowhere else. Miss it and someone pays
        // and stays locked out.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshEntitlement()
                }
            }
        }
    }

    deinit { updates?.cancel() }

    func load() async {
        // The on-device entitlement first: it needs no network, and a payer
        // must be recognised before the product fetch has a chance to fail
        // or hang. Only then does `.loading` stop covering for anyone.
        await refreshEntitlement()
        do {
            let found = try await Product.products(for: ProductID.all)
            products = found.sorted { $0.price < $1.price }
            // Both core plans or none: a partial fetch would render hardcoded
            // fallback prices beside live rows and a buy button that silently
            // no-ops on the missing product. Unavailable never opens the app
            // (2026-09-29): the paywall shows "Plans aren't loading" with a
            // Try again.
            state = ProductID.core.allSatisfy { id in found.contains { $0.id == id } } ? .ready : .unavailable
        } catch {
            state = .unavailable
        }
        await refreshEntitlement()
        // Both subscriptions share one group, so either answers for both.
        if let sub = products.first(where: { $0.subscription != nil })?.subscription {
            trialEligible = await sub.isEligibleForIntroOffer
        }
        // The paywall's own plans carry the trial again (2026-09-29), so the
        // monthly's offer is the one every "Start 3 days free" states; the
        // yearly's, then the half-price rung's, only if it has none.
        for source in [SubscriptionPlan.monthly, .yearly, .monthHalf, .monthTrial] {
            if let offer = product(for: source)?.subscription?.introductoryOffer,
               offer.paymentMode == .freeTrial {
                trialDays = Self.days(in: offer.period)
                break
            }
        }
        // Every product's own trial, so a rung states the length (or the
        // absence) of the offer IT carries, never another product's.
        var byProduct: [String: Int] = [:]
        for product in products {
            // Eligibility is per subscription group, so it is asked of the
            // product's own group rather than assumed from the monthly's.
            if let sub = product.subscription, let offer = sub.introductoryOffer,
               offer.paymentMode == .freeTrial, await sub.isEligibleForIntroOffer {
                byProduct[product.id] = Self.days(in: offer.period)
            }
        }
        freeTrialDaysByProduct = byProduct
    }

    /// A subscription period in days, the way a trial is stated.
    private static func days(in period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return period.value
        }
    }

    func product(for plan: SubscriptionPlan) -> Product? {
        products.first { $0.id == ProductID.of(plan) }
    }

    /// The price as the App Store would display it, in the user's own currency,
    /// or nil when there is no product to ask.
    ///
    /// Never hardcode a price next to a real purchase button. `SubscriptionPlan`
    /// carries dollar strings for the pre-billing beta and for design work; the
    /// moment a tap can charge someone, the number beside it has to be Apple's,
    /// or it will be wrong in every country but one.
    func displayPrice(for plan: SubscriptionPlan) -> String? {
        product(for: plan)?.displayPrice
    }

    /// The struck-through "was" price, shown EVERY time (Melvin, 2026-09-29),
    /// not only when the App Store's prices failed to load.
    ///
    /// It used to render only beside our fallback, because
    /// `SubscriptionPlan.anchorPrice` is a dollar string and a dollar anchor
    /// beside a euro price is nonsense. Now it is said in the product's own
    /// currency:
    ///
    /// - The half-price month's anchor is the monthly product's REAL live
    ///   price, which it is genuinely half of.
    /// - Every other anchor is the same reference price in that currency: the
    ///   live price scaled by the plan's anchor-to-price ratio (the yearly's
    ///   $59.99 against $29.99), snapped to the live price's own ending
    ///   (`scaledAnchor`), and formatted by the product's `priceFormatStyle`.
    /// - The dollar string only when no product loaded, beside the dollar
    ///   fallback price.
    ///
    /// Monthly has none, and gets none here: see `SubscriptionPlan.anchorPrice`
    /// for why, and for the legal note on these reference prices.
    func anchorPrice(for plan: SubscriptionPlan) -> String? {
        guard let listAnchor = plan.anchorPrice else { return nil }
        guard let live = product(for: plan) else { return listAnchor }
        if plan == .monthHalf, let monthly = product(for: .monthly) {
            return monthly.price > live.price ? monthly.displayPrice : nil
        }
        return Self.formattedAnchor(livePrice: live.price, plan: plan, style: live.priceFormatStyle)
    }

    /// `anchorPrice(for:)`'s arithmetic, apart from StoreKit so it can be
    /// tested: nil when the plan has no anchor, or when the result would not
    /// sit above the price (a strikethrough at or under the price is not a
    /// reference price, it is a mistake someone will screenshot).
    nonisolated static func formattedAnchor(livePrice: Decimal, plan: SubscriptionPlan,
                                            style: Decimal.FormatStyle.Currency) -> String? {
        guard let ratio = plan.anchorRatio else { return nil }
        let anchor = scaledAnchor(livePrice: livePrice, ratio: ratio, keepsCents: plan.anchorKeepsCents)
        guard anchor > livePrice else { return nil }
        // A whole anchor reads the way the reference price is written: "$199",
        // not "$199.00".
        var input = anchor
        var whole = Decimal()
        NSDecimalRound(&whole, &input, 0, .plain)
        return anchor.formatted(whole == anchor ? style.precision(.fractionLength(0)) : style)
    }

    /// The live price times the ratio, snapped so it reads as a price rather
    /// than a sum, the way the dollar anchor reads beside the dollar price:
    ///
    /// - `keepsCents` (the yearly's $59.99 beside $29.99): a price with cents
    ///   keeps its own cents, so "29,99 €" scales to "59,99 €" and "£24.99"
    ///   to "£49.99".
    /// - Otherwise (Lifetime's $199 beside $99.99) it rounds to a whole unit.
    /// - A whole price rounds to its own step: "¥4,500" scales to "¥9,000",
    ///   not "¥9,002".
    ///
    /// In dollars it gives back every cleared reference price exactly.
    nonisolated static func scaledAnchor(livePrice: Decimal, ratio: Decimal,
                                         keepsCents: Bool = true) -> Decimal {
        func round(_ value: Decimal) -> Decimal {
            var input = value
            var output = Decimal()
            NSDecimalRound(&output, &input, 0, .plain)
            return output
        }
        func isWhole(_ value: Decimal) -> Bool { round(value) == value }

        let scaled = livePrice * ratio
        var whole = Decimal()
        var price = livePrice
        NSDecimalRound(&whole, &price, 0, .down)
        let cents = livePrice - whole
        if cents != 0 {
            return keepsCents ? round(scaled - cents) + cents : round(scaled)
        }
        var step: Decimal = 1
        while step * 10 <= livePrice, isWhole(livePrice / (step * 10)) {
            step *= 10
        }
        return round(scaled / step) * step
    }

    enum PurchaseOutcome { case bought, cancelled, pending, unavailable }

    @discardableResult
    func purchase(_ plan: SubscriptionPlan) async -> PurchaseOutcome {
        guard let product = product(for: plan) else { return .unavailable }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                    return .bought
                }
                // Failed verification is not a purchase. Apple checks the
                // signature for us; distrusting it here is the whole point.
                return .unavailable
            case .userCancelled:
                return .cancelled
            case .pending:
                // Ask to Buy, or a payment method needing action. The
                // Transaction.updates stream above delivers the result later.
                return .pending
            @unknown default:
                return .unavailable
            }
        } catch {
            return .unavailable
        }
    }

    /// Apple requires a restore path on any screen selling a subscription
    /// (guideline 3.1.1), and it is the only honest way through for someone
    /// who already paid and is reinstalling.
    /// Returns false when the App Store could not be reached (or the sign-in
    /// prompt was cancelled), so "nothing to restore" and "couldn't ask" can
    /// be told apart.
    @discardableResult
    func restore() async -> Bool {
        var synced = true
        do { try await AppStore.sync() } catch { synced = false }
        await refreshEntitlement()
        return synced
    }

    private func refreshEntitlement() async {
        var active = false
        var owned: [String] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ProductID.all.contains(transaction.productID) else { continue }
            if transaction.revocationDate != nil { continue }
            // No expiry check here (Melvin, 2026-09-29). `currentEntitlements`
            // already leaves out expired subscriptions, and it deliberately
            // INCLUDES one in its Billing Grace Period, whose expiration date
            // is already past while Apple retries the card. Skipping past
            // expiries locked out exactly the people Apple is still honouring.
            active = true
            owned.append(transaction.productID)
        }
        if entitled && !active { Analytics.track(.entitlementLost) }
        entitled = active
        entitlementKnown = true
        // Whether this install pays, and for which plan, on the anonymous
        // PostHog person (the SDK drops a repeat of the same values).
        Analytics.setPersonProperties(["is_subscriber": active,
                                       "plan": Self.planName(owning: owned)])
    }

    /// The plan a set of owned product IDs amounts to, for the `plan` person
    /// property: a `SubscriptionPlan` raw value, or "none". Lifetime outranks
    /// a year, a year outranks a month, so a person mid-upgrade reads as the
    /// bigger plan.
    nonisolated static func planName(owning productIDs: [String]) -> String {
        let ranked: [SubscriptionPlan] = [.lifetime, .yearly, .yearHalf, .monthly, .monthHalf, .monthTrial]
        return ranked.first { productIDs.contains(ProductID.of($0)) }?.rawValue ?? "none"
    }
}
