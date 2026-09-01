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
/// Until the Paid Applications agreement is signed (which needs the entity's
/// bank and tax details) no products can exist in App Store Connect, so
/// `state` will settle on `.unavailable` everywhere. That is a supported
/// state, not a failure: the paywall shows honest beta copy instead of
/// pretending to sell something. See `PaywallScreen`.
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

        static let all = [monthly, yearly, lifetime]

        static func of(_ plan: SubscriptionPlan) -> String {
            switch plan {
            case .monthly:  return monthly
            case .yearly:   return yearly
            case .lifetime: return lifetime
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
    /// Whether this person can still claim the 7-day introductory offer.
    /// The paywall must not promise a free week to someone StoreKit will
    /// charge immediately: that is the difference between an offer and a lie,
    /// and reviewers check the claim against the purchase sheet.
    @Published private(set) var trialEligible = true

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
        do {
            let found = try await Product.products(for: ProductID.all)
            products = found.sorted { $0.price < $1.price }
            // All three or none: a partial fetch would render hardcoded
            // fallback prices beside live rows and a buy button that silently
            // no-ops on the missing product. Unavailable keeps the app open
            // and everyone paid, which is the safe floor.
            state = found.count == ProductID.all.count ? .ready : .unavailable
        } catch {
            state = .unavailable
        }
        await refreshEntitlement()
        // Both subscriptions share one group, so either answers for both.
        if let sub = products.first(where: { $0.subscription != nil })?.subscription {
            trialEligible = await sub.isEligibleForIntroOffer
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
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ProductID.all.contains(transaction.productID) else { continue }
            if transaction.revocationDate != nil { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            active = true
        }
        if entitled && !active { Analytics.track(.entitlementLost) }
        entitled = active
    }
}
