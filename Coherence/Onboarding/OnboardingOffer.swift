import SwiftUI
import AuthenticationServices
import StoreKit
import SwiftData

/// Screens 23–25: the offer, the exit offer, and sign-in.
///
/// **Wired to StoreKit, dormant until products exist.** The paywall asks the
/// Store whether anything is on sale: when it is, Continue purchases and only
/// a verified transaction advances; until then the screen says plainly that
/// billing is off and nothing can be charged. No flag to flip, no beta copy
/// to remember to remove.
///
/// What we refuse to copy from the reference flow, and why it matters here
/// specifically: no countdown, no "94% off", no "9 spots remaining", no "you
/// will never see this again". A meditation app manufacturing panic contradicts
/// the thing it sells, and it's App-Review-adjacent besides.

enum SubscriptionPlan: String, CaseIterable, Identifiable {
    case monthly, yearly, lifetime
    /// The year at half price for the first year, and the ONLY discount 808
    /// offers (Melvin, 2026-09-22: "can we offer a half off of a year for
    /// users that deny both times? Otherwise thats just money on the table").
    ///
    /// **Its own product, because a product carries exactly one introductory
    /// offer.** Selling this as the yearly product would promise a discount
    /// the purchase sheet then contradicts, which is the mistake the deleted
    /// half-off-month rung made. It renews at the full yearly price, and
    /// every screen that shows it says so.
    case yearHalf
    /// The ladder's plans, each its own product because a product carries
    /// exactly one introductory offer (Melvin, 2026-09-29: the free trial is
    /// an upsell, hidden until someone declines). Rung 1, the free trial, puts
    /// `monthTrial` and `yearTrial` in Monthly's and Yearly's places, Yearly
    /// preselected ("should i not make a free trial version for yearly?"): a
    /// trial on the monthly alone would steer everyone who takes it away from
    /// the best value. Rung 2 is `monthHalf`, $3.99 every month after a trial.
    case monthTrial, monthHalf, yearTrial

    var id: String { rawValue }

    /// The free trial's length until the App Store says otherwise
    /// (`Store.trialDays` reads the real one off the trial rung's product).
    /// Three: the length the founders set (Melvin, 2026-09-29); only a build
    /// with no products ever shows it.
    static let fallbackTrialDays = 3

    /// The cards the paywall shows. `yearHalf` is not among them until
    /// somebody has been offered it, and then it takes the year's place
    /// rather than sitting beside it, because two yearly cards at different
    /// prices is a shell game.
    ///
    /// **Lifetime is back as the third card** (Melvin, 2026-09-29: "that
    /// should def be a thing"), as it was before Aziz's monthly-and-yearly-only
    /// paywall of 2026-09-26: one charge, no trial, nothing renews. The
    /// paywall still hides it while the App Store is selling without it
    /// (`PaywallScreen.cardsShown`), so a missing product never shows a
    /// fallback price beside live ones.
    static func cards(selecting plan: SubscriptionPlan) -> [SubscriptionPlan] {
        // A rung's plan takes the monthly card's place, the way the half-off
        // year takes the year's: two monthly cards at two prices is a shell
        // game. Nothing ever takes Lifetime's.
        switch plan {
        case .yearHalf: return [.monthly, .yearHalf, .lifetime]
        case .monthTrial, .yearTrial: return [.monthTrial, .yearTrial, .lifetime]
        case .monthHalf: return [.monthHalf, .yearly, .lifetime]
        default: return [.monthly, .yearly, .lifetime]
        }
    }

    var title: String {
        switch self {
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        case .lifetime: return "Lifetime"
        case .yearHalf: return "First year"
        // Named for what is bought, a monthly plan (Melvin, 2026-09-29). "Free
        // trial" as the title of a card that renews at $7.99 read as if the
        // card itself were free; the trial is stated on the cadence line.
        case .monthTrial: return "Monthly"
        case .monthHalf: return "Monthly, half price"
        case .yearTrial: return "Yearly"
        }
    }

    var price: String {
        switch self {
        case .monthly:  return "$7.99"
        case .yearly:   return "$29.99"
        case .lifetime: return "$99.99"
        case .yearHalf: return "$14.99"
        case .monthTrial: return "$7.99"
        case .monthHalf: return "$3.99"
        case .yearTrial: return "$29.99"
        }
    }

    /// The launch list price, struck through beside what you actually pay.
    ///
    /// **This is a legal object, not a design flourish.** A struck-through
    /// "was" price the product never actually sold at is a fake reference
    /// price under FTC pricing guidance and several state laws. Melvin cleared
    /// these with the attorney on the basis of documented prior intent to
    /// market at them (2026-08-18). If the plan ever changes so these were
    /// never really the list price, this property comes out, it does not get
    /// quietly re-pointed at a bigger number.
    ///
    /// **Monthly's anchor came out on 2026-08-25, per that exact rule.** The
    /// repriced stack ($7.99 / $29.99 / $99.99) makes $7.99 the real monthly
    /// price, and a strikethrough equal to the sale price is the fake
    /// reference this comment forbids. nil = no anchor shown.
    ///
    /// **Shown every time since 2026-09-29** (Melvin), not only beside our
    /// fallback prices: `Store.anchorPrice(for:)` says the same reference
    /// price in the live product's own currency. These dollar strings are the
    /// reference prices themselves, and the fallback when no product loaded.
    var anchorPrice: String? {
        switch self {
        case .monthly:  return nil
        case .yearly:   return "$59.99"
        case .lifetime: return "$199"
        // The year's real price, which this is genuinely half of, so the
        // strikethrough is a true reference price and not a fake one.
        case .yearHalf: return "$29.99"
        case .monthTrial: return nil
        // The month's real price, which this plan is genuinely half of,
        // every month (2026-09-27), so the strikethrough stays a true
        // reference price.
        case .monthHalf: return "$7.99"
        // The same yearly plan with a free trial first, so the same
        // reference price is true of it.
        case .yearTrial: return "$59.99"
        }
    }

    /// The anchor against the price it anchors, both in dollars: the factor
    /// `Store.anchorPrice(for:)` scales a live price by (the yearly's
    /// $59.99 / $29.99). nil when the plan has no anchor.
    var anchorRatio: Decimal? {
        guard let anchor = anchorPrice.flatMap(Self.dollars),
              let price = Self.dollars(price), price > 0 else { return nil }
        return anchor / price
    }

    /// Whether the dollar anchor ends the way the dollar price does ($59.99
    /// beside $29.99), so a live anchor keeps the live price's cents; or not
    /// (Lifetime's $199 beside $99.99), so it rounds to a whole unit.
    var anchorKeepsCents: Bool {
        guard let anchor = anchorPrice.flatMap(Self.dollars),
              let price = Self.dollars(price) else { return true }
        return Self.cents(anchor) == Self.cents(price)
    }

    private static func cents(_ value: Decimal) -> Decimal {
        var input = value
        var whole = Decimal()
        NSDecimalRound(&whole, &input, 0, .down)
        return value - whole
    }

    /// "$59.99" as a Decimal.
    private static func dollars(_ text: String) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: "$", with: ""),
                locale: Locale(identifier: "en_US"))
    }

    /// The plans designed to open with a free trial: the paywall's own two
    /// while `Monetization.freeTrial` is on, and the ladder's. Whether a
    /// given person actually gets one is the App Store's answer
    /// (`Store.freeTrialDays(for:)`), never this.
    var designedWithTrial: Bool {
        switch self {
        case .monthTrial, .monthHalf, .yearTrial: return true
        case .monthly, .yearly: return Monetization.freeTrial
        case .lifetime, .yearHalf: return false
        }
    }

    /// The cadence as it is true right now. A plan whose trial this person
    /// gets says what the price follows ("per month after the trial"); one
    /// whose trial they will not get says "per month", never promising a
    /// trial the purchase sheet will not give.
    func cadence(withTrial trial: Bool) -> String {
        switch self {
        case .monthly, .monthTrial, .monthHalf:
            return trial ? "per month after the trial" : "per month"
        case .yearly, .yearTrial:
            return trial ? "per year after the trial" : "per year"
        case .lifetime, .yearHalf:
            return cadence
        }
    }

    var cadence: String {
        switch self {
        case .monthly:  return "per month"
        case .yearly:   return "per year"
        case .lifetime: return "once"
        // The renewal price rides the cadence, so it is beside the number
        // everywhere the number appears (3.1.2, and plain honesty).
        case .yearHalf: return "first year, then $29.99 a year"
        case .monthTrial: return "per month after the trial"
        case .monthHalf: return "per month after the trial"
        case .yearTrial: return "per year after the trial"
        }
    }

    /// The price restated in the smallest honest unit.
    ///
    /// This is the one piece of pricing psychology the flow does use, and it is
    /// used because it is TRUE rather than because it converts: every figure
    /// here is arithmetic on the price beside it, and a test recomputes all
    /// three. Headspace and Calm both show an annual plan's effective monthly
    /// for the same reason, since $29.99 once a year and $2.50 a month are the
    /// same fact and only one of them is easy to picture.
    ///
    /// What it is not allowed to become: a comparison we cannot support. "Less
    /// than a coffee" survives because $2.50 genuinely is. "Less than you spend
    /// on X" does not, because we have no idea what anyone spends on X.
    var note: String? {
        switch self {
        // $95.88 a year over 52 weeks. Weekly rather than daily: a cent
        // figure reads as a rounding trick, $1.84 reads as a price.
        case .monthly:  return "About $1.84 a week"
        // $29.99 over 12 months, and under a third of the monthly plan.
        case .yearly:   return "$2.50 a month"
        // $99.99 against $7.99 a month is 12.5 months.
        case .lifetime: return "A year of monthly, then never again"
        // $14.99 over 12 months, the same arithmetic as the year above it.
        case .yearHalf: return "$1.25 a month for the first year"
        case .monthTrial: return "Nothing to pay today"
        case .monthHalf: return "Half the monthly price, every month"
        // $29.99 over 12 months, the same arithmetic as Yearly.
        case .yearTrial: return "$2.50 a month"
        }
    }
}

// MARK: - 22b · Rating

/// An internal question, and ONLY an internal question.
///
/// An earlier version called `requestReview` here for anyone who answered 4 or
/// 5. That is review gating: routing happy users to Apple's rating sheet and
/// quietly not asking anyone else, which App Review treats as manipulating
/// ratings, and which reviewers have been rejecting for. The sentiment
/// question itself is fine, because it feeds our own signal and nothing else.
/// So the stars stay and Apple's prompt is gone from onboarding entirely.
///
/// When the store prompt returns it must be UNCONDITIONAL where it fires, and
/// it belongs after a completed session, not before the first one: Apple's own
/// guidance is to ask once someone has demonstrated engagement, and a person
/// mid-onboarding has not used the app yet.
///
/// The honesty lives in the question: "does this sound like it'd work for you"
/// is answerable before anyone has used the app, where "enjoying 808?" is not.
/// Anyone who taps 1 to 3 simply moves on. No apology screen, no "help us
/// improve" detour, no attempt to talk them round.
struct RatingScreen: View {
    @Binding var rating: Int?
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "Does this sound like\nit'd work for you?",
                         subtitle: "Every part of it came out of your own answers. Tell us how it lands.",
                         // No skip: Continue already works with no stars
                         // tapped, so a second way to say nothing was just
                         // two buttons doing one job.
                         onContinue: { finish() }) {
            VStack(spacing: 6) {
                // Stars and legend share one width: the VStack is sized to the
                // star row, and the legend's Spacer stretches to exactly that.
                VStack(spacing: 8) {
                    HStack(spacing: 9) {
                        ForEach(1...5, id: \.self) { star in
                            Button { rating = star } label: {
                                Image(systemName: (rating ?? 0) >= star ? "star.fill" : "star")
                                    .font(.system(size: 30))
                                    .foregroundStyle(AppColor.accentGoldText)
                                    .opacity((rating ?? 0) >= star ? 1 : 0.35)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                    .sensoryFeedback(.success, trigger: rating)

                    // What the ends of the scale mean. Five stars with no
                    // legend left a tester unsure what he was rating
                    // (2026-09-14).
                    HStack {
                        Text("Not for me")
                        Spacer(minLength: 12)
                        Text("Exactly what I need")
                    }
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary.opacity(0.8))
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, 22)

                Text(rating == nil ? "Tap a star" : "Thank you.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func finish() {
        onContinue()
    }
}

// MARK: - 23 · Paywall

/// The plans, with no free trial (it is an upsell, Melvin, 2026-09-29), and
/// two answers to a "no" (`DownsellRung.ladder`): the free trial on Monthly
/// or Yearly, then half price. Each comes back to this screen to be bought. No chevron back into the
/// interview. The paywall owns every purchase and every disclosure.
///
/// **It fails closed** (Melvin, 2026-09-29). When the App Store cannot give
/// the plans, the screen says so and Continue becomes Try again. It never
/// walks a non-member into the app; only a purchase or a restore does.
///
/// **Restore is not optional.** Apple requires a restore mechanism on any
/// screen selling an auto-renewable subscription (3.1.1), and with no decline
/// it is also the only honest way through for someone who already subscribed
/// and is reinstalling. It is wired to nothing today because StoreKit is not
/// wired to anything today; it must do real work before submission.
struct PaywallScreen: View {
    /// Where this paywall stands: "onboarding", "block" or "root_lock".
    /// Analytics, plus the Account link (`offersAccount`).
    var placement: String = "onboarding"
    /// The launch lock for somebody with sessions on this phone: 1.0 was
    /// free, so an update meets them here, and the first thing to say is that
    /// nothing they did is gone (Melvin, 2026-09-29).
    var memberNotice: Bool = false
    @State private var trackedView = false

    @State private var started = false
    /// A purchase is in flight. Without it, taps landing while the StoreKit
    /// sheet animates up each queue their own purchase.
    @State private var buying = false
    /// `paywall_dismissed` is sent at most once per visit.
    @State private var trackedDismiss = false
    /// The one sheet this screen presents: a legal document, or the launch
    /// lock's Account page. One `.sheet(item:)` over an enum, never two
    /// stacked `.sheet` modifiers (the only-one-presents trap).
    @State private var sheet: PaywallSheet?
    /// What a Restore found, when there is something to say.
    @State private var restoreFeedback: RestoreFeedback?

    private enum PaywallSheet: Identifiable {
        case legal(LegalDoc)
        case account
        var id: String {
            switch self {
            case .legal(let doc): return "legal-" + doc.rawValue
            case .account: return "account"
            }
        }
    }

    /// The launch lock is the only 808 a lapsed or updating member can reach,
    /// so it carries the way to their account: manage the subscription,
    /// redeem a code, sign out, delete (App Review 5.1.1(v), Melvin,
    /// 2026-09-29).
    ///
    /// **Onboarding's paywall carries it too, whenever this phone already
    /// holds somebody's data** (same day). Signing out lands a person back in
    /// onboarding, and there sign-in comes AFTER the paywall, so a signed-out
    /// non-member could never reach Delete account again. A first install
    /// holds nothing yet and sees no Account link.
    private var offersAccount: Bool {
        placement == "root_lock" || (placement == "onboarding" && holdsAccountData)
    }
    @Environment(\.modelContext) private var context
    /// Read once on appear (`deviceHoldsAccountData`).
    @State private var holdsAccountData = false

    /// A signed-in account (a User with an Apple ID) or any session. The
    /// bootstrap User every install creates at launch has no Apple ID, so a
    /// first run is not mistaken for a returning one.
    static func deviceHoldsAccountData(in context: ModelContext) -> Bool {
        var users = FetchDescriptor<User>(predicate: #Predicate { $0.appleUserID != "" })
        users.fetchLimit = 1
        if ((try? context.fetchCount(users)) ?? 0) > 0 { return true }
        var sessions = FetchDescriptor<Session>()
        sessions.fetchLimit = 1
        return ((try? context.fetchCount(sessions)) ?? 0) > 0
    }
    /// What is covering the prices right now. Nil means the prices are showing.
    ///
    /// One cover, switching on a route, for the same reason the results screen
    /// has one sheet: stacking presentation modifiers on a single view is the
    /// documented only-one-presents trap.
    @State private var route: PaywallRoute?

    /// Apple's localized prices when live, our fallback otherwise, so the
    /// anchor never states dollars to someone about to be shown euros.
    private var anchorPriceLine: String {
        let monthly = store.displayPrice(for: .monthly) ?? SubscriptionPlan.monthly.price
        let yearly = store.displayPrice(for: .yearly) ?? SubscriptionPlan.yearly.price
        let base = "808 Premium is \(monthly) a month or \(yearly) a year"
        return offerTrial ? base + ", and the first \(TrialCopy.length(store.trialDays)) are free." : base + "."
    }

    enum PaywallRoute: Identifiable {
        case rung(DownsellRung)
        case freeTier

        var id: String {
            switch self {
            case .rung(let r): return "rung-\(r.rawValue)"
            case .freeTier:    return "free"
            }
        }
    }
    @EnvironmentObject private var store: Store
    @Binding var plan: SubscriptionPlan
    /// The one exit. `true` means a VERIFIED purchase or restore completed;
    /// `false` means the user moved on without buying anything, which today is
    /// every user, since nothing is on sale. The parent uses this to decide
    /// whether sign-in may be skipped, so it must never report a sale that
    /// didn't happen: an earlier version hardcoded it and forced every beta
    /// tester to sign in for a purchase that did not exist.
    let onDone: (Bool) -> Void

    /// Can this build actually sell anything?
    ///
    /// Not a build flag, deliberately. Before the Paid Applications agreement
    /// is signed there are no products to fetch, so the app can simply ask,
    /// and the answer flips by itself the day billing is switched on. A flag
    /// would need remembering, and the failure mode of forgetting is a beta
    /// screen shipped to paying customers.
    private var selling: Bool { store.state == .ready || Self.demoSelling }

    /// DEBUG builds sell even before StoreKit has products, so the whole
    /// offer (prices, trial, ladder, free tier) demos exactly as it will
    /// ship: full sell copy, and the buy button grants the simulated
    /// entitlement Aziz's preview machinery already persists. Release builds
    /// are untouched: before billing exists they keep the honest
    /// nothing-for-sale copy, and the flag needs no remembering because it
    /// compiles away.
    #if DEBUG
    private static let demoSelling = true
    #else
    private static let demoSelling = false
    #endif

    /// The Simulator reaches the App Store's sandbox, so the plans load and
    /// Continue opened a real purchase that needs an Apple ID the Simulator
    /// does not have, which left onboarding stuck on this screen (Melvin,
    /// 2026-09-28). A DEBUG build on the Simulator grants the simulated
    /// entitlement instead. `REAL_PURCHASE=1` puts the real purchase sheet
    /// back, for a StoreKit rehearsal. A phone is untouched.
    #if DEBUG && targetEnvironment(simulator)
    private static let simulatesPurchase = ProcessInfo.processInfo.environment["REAL_PURCHASE"] != "1"
    #else
    private static let simulatesPurchase = false
    #endif

    /// Apple's price string when there is a real product, ours otherwise.
    /// A hardcoded dollar amount beside a live purchase button is wrong in
    /// every country but one.
    private var priceLine: String { priceLine(withTrial: trialNow) }

    /// `withTrial: false` in the trial footnote, which already says "free,
    /// then": the rung's "per month after the trial" there read "then $7.99
    /// per month after the trial".
    private func priceLine(withTrial trial: Bool) -> String {
        let cadence = plan.cadence(withTrial: trial)
        return store.displayPrice(for: plan).map { "\($0) \(cadence)" }
            ?? "\(plan.price) \(cadence)"
    }

    private var notSellingFootnote: String {
        #if DEBUG
        "Nothing is charged. There is no payment set up on this build."
        #else
        Monetization.isSideBySideBeta
            ? "Nothing is charged. This test build has no plans to sell."
            : "Nothing is charged while plans can't load."
        #endif
    }

    private var notSellingTitle: String {
        #if DEBUG
        "Free while we're testing."
        #else
        // The launch's first fetch has not answered yet: it is on its way,
        // not failing.
        store.state == .loading ? "Loading the plans." : "Plans aren't loading."
        #endif
    }

    /// The Release copy says what to do about it, and nothing about walking
    /// on: since 2026-09-29 there is no way past this screen but a purchase
    /// or a restore (Melvin: the app never opens free because the App Store
    /// could not load). The side-by-side beta, which owns no products, is the
    /// one build that may carry on.
    private var notSellingSubtitle: String {
        #if DEBUG
        "Billing isn't switched on yet, so there's nothing to buy. Here's what it will cost when it is, and we'd genuinely like to know what you make of it."
        #else
        if Monetization.isSideBySideBeta {
            "This test build has no plans to sell, so you can carry on."
        } else if store.state == .loading {
            "They'll be here in a moment."
        } else {
            "The App Store didn't answer just now. Check your connection, then tap Try again."
        }
        #endif
    }

    /// Continue while nothing can be sold: Try again, which asks the App
    /// Store for the plans once more.
    private var notSellingButton: String {
        if Monetization.isSideBySideBeta { return "Continue" }
        return waitingOnStore ? "One moment" : "Try again"
    }

    /// The App Store is being asked right now: the launch's first fetch, or
    /// a Try again. The button waits rather than asking twice.
    private var waitingOnStore: Bool {
        retrying || (store.state == .loading && !Monetization.isSideBySideBeta)
    }

    /// A Try again is asking the App Store right now.
    @State private var retrying = false

    /// "Three days free.", from the chosen plan's own trial length.
    private func trialTitle(_ days: Int) -> String {
        days == 1 ? "One day free." : "\(TrialCopy.spelled(days)) days free."
    }

    /// Whether the free trial may be promised: 808 offers one at all
    /// (`Monetization.freeTrial`, back on since 2026-09-29), and StoreKit
    /// says this person has not used it. Promising it anyway would put a
    /// claim on screen that the purchase sheet contradicts one tap later.
    private var offerTrial: Bool { store.trialOffered }
    /// The plan being bought right now starts with a free trial.
    private var trialNow: Bool { trialLength != nil }

    /// The free days the plan being bought starts with, or nil for none.
    /// Every plan's trial is its OWN product's offer and this person's
    /// eligibility for it (`Store.freeTrialDays(for:)`), never another
    /// product's: a yearly with no trial in App Store Connect must not
    /// borrow the monthly's, and the half-price plan must not promise days
    /// its purchase sheet will not give. Lifetime and the half-off year
    /// carry no free trial (the year's offer is a discount paid up front).
    private var trialLength: Int? { trialLength(for: plan) }

    /// The same for any plan, so each card's cadence says exactly what its
    /// own purchase would start with.
    private func trialLength(for p: SubscriptionPlan) -> Int? {
        switch p {
        case .monthTrial, .monthHalf, .yearTrial: return store.freeTrialDays(for: p)
        case .lifetime, .yearHalf: return nil
        case .monthly, .yearly: return offerTrial ? store.freeTrialDays(for: p) : nil
        }
    }

    /// A rung can be offered only if it is on the ladder and its product
    /// exists (a DEBUG build demos it), and the trial rung only to someone
    /// its product would give free days to.
    private func available(_ rung: DownsellRung) -> Bool {
        guard selling, DownsellRung.ladder.contains(rung) else { return false }
        let exists = store.product(for: rung.plan) != nil || Self.demoSelling
        // "Try it free first" over a charge is the lie.
        return exists && (rung != .trial || store.freeTrialDays(for: .monthTrial) != nil)
    }
    private func firstRung(after rung: DownsellRung? = nil) -> DownsellRung? {
        var next = rung.map { $0.next } ?? DownsellRung.ladder.first
        while let r = next, !available(r) { next = r.next }
        return next
    }
    /// Declined every rung once: the link goes, so "no" is not a loop.
    @State private var declinedAll = false

    @StateObject private var otto = OttoRigHolder()

    /// The pale green the onboarding cards use, for the chosen plan.
    private static let chosenWash = Color(red: 0.87, green: 0.95, blue: 0.85)

    /// The headline: the chosen plan's free trial when this person gets one,
    /// otherwise Otto, who the reader just raised to his brightest on the
    /// ascend screen.
    private var title: String {
        guard selling else { return notSellingTitle }
        if let days = trialLength { return trialTitle(days) }
        return "Keep Otto glowing."
    }

    private var subtitle: String {
        guard selling else { return notSellingSubtitle }
        if memberNotice {
            return "808 is now a membership. Your sessions, streak and awards are saved and waiting."
        }
        // The trial's cancel terms live in the footnote under the button,
        // said once. Repeating them here pushed Otto off the screen on an
        // iPhone 17 (Melvin, 2026-09-29).
        return trialNow ? "Try all of 808 first." : Self.includesLine
    }

    /// What a membership opens, stated on the purchase screen itself (3.1.2:
    /// a subscription says what it gives; Melvin, 2026-09-29). Only what THIS
    /// build contains, read off the flags: Block, hats and Friends while each
    /// is on (all three ship in 1.1), never Otto's chat, which is off.
    static var includesLine: String {
        let block = FeatureFlags.block ? "Block, " : ""
        let hats = FeatureFlags.shop ? " and hats" : ""
        let friends = FeatureFlags.friends ? ", Friends" : ""
        // Named before anything is bought (3.1.2: the purchase screen names
        // the subscription; Melvin, 2026-09-29), and the same name the App
        // Store listing and the purchase sheet use.
        return "808 Premium: full access to \(block)timed and guided sessions, sounds, Otto's glow\(hats), streaks and awards\(friends), and heart, stillness and breathing readings with an Apple Watch."
    }

    /// The includes line in small type under a subtitle that says something
    /// else (the member notice, the trial), so what a membership opens is on
    /// every selling version of this screen.
    private var showsIncludesBelow: Bool { selling && subtitle != Self.includesLine }

    /// 3.1.2 wants auto-renewal SAID, not implied: "cancel any time" hints at
    /// it and reviewers reject paywalls that only hint. And WHERE to cancel is
    /// named (Melvin, 2026-09-29): "in Settings" read as 808's own Settings,
    /// which cannot cancel anything.
    private var footnote: String {
        guard selling else { return notSellingFootnote }
        return Self.terms(for: plan, priceLine: priceLine(withTrial: false), trialDays: trialLength)
    }

    /// The terms under the button, for the plan it buys. Pure, so the one
    /// sentence that must never be wrong is tested.
    ///
    /// Lifetime is one charge today and never renews, so it says exactly
    /// that and nothing about a trial or cancelling (restored 2026-09-29 as
    /// it read before 2026-09-26): claiming it renews would be its own lie.
    nonisolated static func terms(for plan: SubscriptionPlan, priceLine: String, trialDays: Int?) -> String {
        if plan == .lifetime {
            return "\(priceLine), charged today. Nothing renews."
        }
        let whereToCancel = "in the Settings app under your name, then Subscriptions."
        if let days = trialDays {
            return "\(TrialCopy.length(days)) free, then \(priceLine). Renews automatically until you cancel. Cancel at least 24 hours before the trial ends to pay nothing, \(whereToCancel)"
        }
        return "\(priceLine). Renews automatically until you cancel. Cancel any time, at least 24 hours before it renews, \(whereToCancel)"
    }

    /// The button that buys: "Buy Lifetime" for the one charge (restored
    /// 2026-09-29), "Start my free trial" when the plan starts with one,
    /// otherwise "Continue".
    nonisolated static func buyButtonTitle(for plan: SubscriptionPlan, trialDays: Int?) -> String {
        if plan == .lifetime { return "Buy Lifetime" }
        return trialDays != nil ? "Start my free trial" : "Continue"
    }

    /// The cards on screen. Lifetime shows whenever its product loaded, and
    /// beside the fallback prices when nothing has; while the App Store is
    /// selling WITHOUT it, it hides rather than show a dollar fallback
    /// beside live prices and a button that could not buy it.
    private var cardsShown: [SubscriptionPlan] {
        SubscriptionPlan.cards(selecting: plan)
            .map { $0 == .yearTrial && !yearTrialOnSale ? .yearly : $0 }
            .filter { $0 != .lifetime || lifetimeOnSale }
    }

    /// The yearly-with-trial plan exists in the App Store (or nothing has
    /// loaded yet, a DEBUG demo). When it does not, taking the trial puts the
    /// trial on Monthly only and Yearly stays as it was.
    private var yearTrialOnSale: Bool {
        store.state != .ready || store.product(for: .yearTrial) != nil
    }

    /// The plan the paywall preselects when a rung is taken: the trial rung
    /// lands on Yearly with the trial where it exists, the best value.
    private func landing(_ rung: DownsellRung) -> SubscriptionPlan {
        rung == .trial && yearTrialOnSale ? .yearTrial : rung.plan
    }

    private var lifetimeOnSale: Bool {
        store.state != .ready || store.product(for: .lifetime) != nil
    }

    /// In the valley, like the rest of onboarding (Aziz, 2026-09-26: "make it
    /// consistent with the theme"): the sky and the hills, Otto floating at his
    /// brightest where the ascend screen left him, and the plans on a white
    /// panel with the onboarding's green for the choice and the button.
    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 700
            ZStack(alignment: .top) {
                ValleyScene(progress: 0, showsFigure: false)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // **The screen scrolls when it does not fit** (App Review,
                // Melvin, 2026-09-29). On an iPhone SE at the largest text
                // sizes the links row and "No, I don't want to pay" fell below
                // the screen with no way to reach them, and at accessibility
                // sizes the renewal terms were cut off mid-sentence: an
                // unreadable disclosure and an unreachable Account link are
                // both rejections. `ViewThatFits` keeps today's layout
                // wherever it fits whole, so the default size looks exactly as
                // before, and falls back to one scroll holding everything.
                ViewThatFits(in: .vertical) {
                    // Otto at full size where he fits, then smaller, before
                    // giving him up for the scroll (Melvin, 2026-09-29): with
                    // the trial header and Lifetime back as a third card, the
                    // full-size layout ran about 40pt over on an iPhone 17.
                    fixedLayout(compact: compact, geo: geo,
                                ottoSize: compact ? (showsIncludesBelow ? 90 : 110) : 150)
                    fixedLayout(compact: compact, geo: geo,
                                ottoSize: compact ? 72 : 96)

                    // No Otto here: at a text size this large the screen is
                    // for reading, and a second rig beside the first is not
                    // worth drawing.
                    ScrollView {
                        VStack(spacing: 0) {
                            header(compact: compact)
                            panel(compact: compact, bottomInset: geo.safeAreaInsets.bottom)
                                .padding(.top, 20)
                                // White past the panel's end, so pulling the
                                // scroll up never shows sky under the terms.
                                .background(alignment: .bottom) {
                                    Color.white.frame(height: 600).offset(y: 600)
                                }
                        }
                    }
                    .scrollIndicators(.visible)
                    // Kept below the status bar, where the fixed layout
                    // ends too, so the words never run under the clock.
                    .clipped()
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .fullScreenCover(item: $route) { destination in
            switch destination {
            case .rung(let current):
                DownsellSheet(rung: current, plan: plan, first: firstRung() == current,
                              yearlyPrice: store.displayPrice(for: .yearly)
                                  ?? SubscriptionPlan.yearly.price,
                              monthlyPrice: store.displayPrice(for: .monthly)
                                  ?? SubscriptionPlan.monthly.price,
                              halfMonthPrice: store.displayPrice(for: .monthHalf)
                                  ?? SubscriptionPlan.monthHalf.price,
                              trialPlanPrice: store.displayPrice(for: .monthTrial)
                                  ?? SubscriptionPlan.monthTrial.price,
                              trialYearPrice: yearTrialOnSale
                                  ? (store.displayPrice(for: .yearTrial) ?? SubscriptionPlan.yearTrial.price)
                                  : nil,
                              trialDays: store.freeTrialDays(for: current.plan)) {
                    // Taking a rung PRESELECTS the plan and returns to the
                    // paywall; the purchase happens there and only there.
                    // The rungs used to buy in place, which put a
                    // purchase-initiating CTA on a screen carrying no
                    // price, no renewal statement and no legal links: the
                    // textbook 3.1.2 rejection. One screen holds every
                    // disclosure; every sale goes through it.
                    Analytics.track(.offerAccepted(rung: current.analyticsName))
                    plan = landing(current)
                    route = nil
                } onDecline: {
                    Analytics.track(.offerDeclined(rung: current.analyticsName))
                    // Straight to the next rung. After the last one: the
                    // free tier, or, while 808 is premium only
                    // (`Monetization`), back to the plans, since there is
                    // no free 808 to settle into.
                    if let next = firstRung(after: current) {
                        showRung(next)
                    } else {
                        declinedAll = true
                        route = Monetization.premiumOnly ? nil : .freeTier
                    }
                }
            case .freeTier:
                FreeTierScreen(trialEligible: offerTrial, trialDays: store.trialDays) {
                    // Same rule, plus the bug it fixes: this closure used
                    // to call advance() with whatever plan was last
                    // selected, so a "Start 7 days free" button could
                    // charge $99.99 for a Lifetime someone had tapped
                    // minutes earlier. Select monthly, return, let the
                    // paywall sell it.
                    plan = .monthly
                    route = nil
                } onContinueFree: {
                    route = nil
                    onDone(false)
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .legal(let doc): LegalDocSheet(doc: doc)
            case .account: AccountSheet()
            }
        }
        .restoreFeedbackAlert($restoreFeedback)
        .sensoryFeedback(.success, trigger: plan)
        .sensoryFeedback(.success, trigger: started)
        .onAppear {
            holdsAccountData = Self.deviceHoldsAccountData(in: context)
            // Lifetime is offered again (2026-09-29), but only while its
            // product is on sale; a plan that lands on a card not shown
            // falls back to monthly.
            if plan == .lifetime && !lifetimeOnSale { plan = .monthly }
            // A transient fetch failure should not be a permanent state:
            // every arrival at the paywall retries the load.
            if store.state != .ready {
                Task { await store.load() }
            }
            guard !trackedView else { return }
            trackedView = true
            Analytics.track(.paywallViewed(placement: placement))
        }
        // The plans arriving can take Lifetime away (App Store Connect
        // selling without it); the choice moves to a card that is there.
        .onChange(of: store.state) { _, _ in
            if plan == .lifetime && !lifetimeOnSale { plan = .monthly }
        }
        // Closed without buying: a sheet swiped away, or moved past while the
        // plans could not load. Not while a rung covers the prices (a full
        // screen cover takes the paywall off screen too), and not once they
        // own it: a purchase or restore is not a dismissal.
        .onDisappear {
            guard route == nil, !started, !store.entitled, !trackedDismiss else { return }
            trackedDismiss = true
            Analytics.track(.paywallDismissed(placement: placement))
        }
    }

    /// The headline, the line under it, and what a membership includes.
    /// The whole screen without a scroll: words, Otto floating between them
    /// and the plans, the panel. Smaller on a short phone when the includes
    /// line sits under the subtitle, or his halo rises into the words.
    private func fixedLayout(compact: Bool, geo: GeometryProxy, ottoSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            header(compact: compact)

            Spacer(minLength: 0)
            OttoAuraFigure(stage: .nirvana, look: 13, size: ottoSize, rig: otto)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Spacer(minLength: 12)

            panel(compact: compact, bottomInset: geo.safeAreaInsets.bottom)
        }
    }

    private func header(compact: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: compact ? 28 : 32, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: compact ? 16 : 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary.opacity(0.7))
            if showsIncludesBelow {
                Text(Self.includesLine)
                    .font(.system(size: compact ? 13 : 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.6))
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, AppMetrics.screenPadding + 4)
        .padding(.top, compact ? 8 : 20)
    }

    /// Restore, the two documents and Account. One row wherever the words
    /// fit on one line unshrunk; a column of full-size links wherever they
    /// do not (2026-09-29). The row used to shrink its words to fit, which at
    /// the largest text sizes cut "Terms of Use" and "Account" off.
    @ViewBuilder private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: offersAccount ? 14 : 18) { linkButtons }
                .lineLimit(1)
            VStack(spacing: 12) { linkButtons }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppColor.textSecondary)
        .multilineTextAlignment(.center)
    }

    /// Restore is here even while the plans cannot load (2026-09-29): with
    /// no way past this screen but a purchase or a restore, a payer whose
    /// on-device record went missing must always have the second.
    @ViewBuilder private var linkButtons: some View {
        Button("Restore") { restore() }
        Button("Privacy Policy") { sheet = .legal(.privacy) }
        Button("Terms of Use") { sheet = .legal(.terms) }
        if offersAccount {
            Button("Account") { sheet = .account }
        }
    }

    /// The plans, the button and everything Apple requires beside them
    /// (price, renewal, Restore, Privacy Policy, Terms of Use: 3.1.1, 3.1.2).
    private func panel(compact: Bool, bottomInset: CGFloat) -> some View {
        VStack(spacing: compact ? 9 : 12) {
            ForEach(cardsShown) { p in
                planCard(p, compact: compact)
            }

            OnboardingCTA(title: selling ? Self.buyButtonTitle(for: plan, trialDays: trialLength) : notSellingButton,
                          enabled: selling || !waitingOnStore,
                          action: { advance() })
                .padding(.top, 4)

            // Directly under the button that buys, both documents one tap
            // away (3.1.2, Melvin, 2026-09-29). The links are handled here,
            // never opened as URLs: they open the same bundled documents the
            // row below does.
            if selling {
                Text("By continuing you agree to the [Terms of Use](legal://terms) and [Privacy Policy](legal://privacy).")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .tint(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        sheet = .legal(url.host == "privacy" ? .privacy : .terms)
                        return .handled
                    })
            }

            Text(footnote)
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            links

            // No free version to decline into (Aziz, 2026-09-26), but a "no"
            // is answered with the ladder (Melvin, 2026-09-29): the free trial
            // on Monthly or Yearly, then half price every month. Once both
            // are declined the link goes, and the plans are what is left.
            if !declinedAll, let first = firstRung() {
                Button("No, I don't want to pay") { showRung(first) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, compact ? 16 : 22)
        // Clear of the home indicator's strip: a tap that low goes to iOS as
        // the start of a swipe home, and "Not right now" never fired.
        .padding(.bottom, max(bottomInset, 12) + 14)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.10), radius: 16, y: -4)
        )
    }

    private func planCard(_ p: SubscriptionPlan, compact: Bool) -> some View {
        let chosen = plan == p
        return Button { select(p) } label: {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .stroke(chosen ? OnboardingGreen.shade : AppColor.textSecondary.opacity(0.35),
                                lineWidth: 2)
                    if chosen {
                        Circle().fill(OnboardingGreen.fill).padding(4)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    // The notes are arithmetic on OUR dollar prices ("About
                    // $1.84 a week"). Beside Apple's localized price they
                    // would be a dollar claim about a euro charge, so they
                    // render only with our fallback prices.
                    if store.displayPrice(for: p) == nil, let note = p.note {
                        Text(note)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(OnboardingGreen.shade)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // Every time, in the live price's own currency
                        // (Melvin, 2026-09-29; `Store.anchorPrice(for:)`),
                        // and in dollars only beside the dollar fallback.
                        if let anchor = store.anchorPrice(for: p) {
                            Text(anchor)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColor.textSecondary.opacity(0.7))
                                .strikethrough(true, color: AppColor.textSecondary.opacity(0.7))
                                .accessibilityLabel("Was \(anchor)")
                        }
                        Text(store.displayPrice(for: p) ?? p.price)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    // Wraps rather than truncating: the half-off year's
                    // renewal price rides this line and must be read whole.
                    Text(p.cadence(withTrial: trialLength(for: p) != nil))
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 130, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, compact ? 12 : 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(chosen ? Self.chosenWash : Color(white: 0.965)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(chosen ? OnboardingGreen.fill : .clear, lineWidth: 2.5))
            // A tag on the card's top edge. True arithmetic, not a slogan:
            // the year costs under a third of twelve months.
            .overlay(alignment: .topLeading) {
                if p == .yearly || p == .yearHalf || p == .yearTrial {
                    Text("Best value")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(OnboardingGreen.fill))
                        .fixedSize()
                        .offset(x: 50, y: -9)
                }
            }
        }
        .buttonStyle(CardButtonStyle())
        // VoiceOver hears which plan is chosen; the ring and the wash are
        // colour and shape only.
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Continue. When something is on sale it is a purchase, and the screen
    /// only moves once StoreKit confirms. A cancelled or failed purchase stays
    /// put without comment, because the system sheet the user just dismissed
    /// IS the comment.
    ///
    /// **When nothing is on sale it is Try again, never a way in** (Melvin,
    /// 2026-09-29). It used to call `onDone(false)`, which walked onboarding
    /// on into a paid app whenever the App Store was slow or unreachable.
    private func advance() {
        // One sale per visit to this screen. StoreKit returns `.bought`
        // IMMEDIATELY for a product this Apple ID already owns, so a second
        // tap on the button logged a second purchase: the live data showed one
        // person firing four `purchase` events in eighteen seconds (2026-09-12),
        // which made every event-count of sales wrong. `buying` also blocks the
        // taps that land while the system sheet is coming up.
        guard !started, !buying else { return }
        guard store.state == .ready, !Self.simulatesPurchase else {
            #if DEBUG
            // The purchase StoreKit cannot run happens as a simulated
            // entitlement instead, so the unlock is real on this build and
            // buy → unlock reviews end to end with no demo tell on screen.
            store.setPreviewEntitled(true)
            onDone(true)
            #else
            if Monetization.isSideBySideBeta {
                // Owns no products, so there is nothing to wait for.
                onDone(false)
            } else {
                retryLoad()
            }
            #endif
            return
        }
        buying = true
        let buyingPlan = plan
        Analytics.track(.purchaseStarted(plan: buyingPlan.rawValue, placement: placement))
        Task { @MainActor in
            defer { buying = false }
            switch await store.purchase(buyingPlan) {
            case .bought:
                // Lifetime carries no introductory offer, so it can never be a
                // trial however eligible the buyer still is for the
                // subscription group's free trial.
                if trialNow { Analytics.track(.trialStarted(plan: buyingPlan.rawValue)) }
                Analytics.track(.purchase(plan: buyingPlan.rawValue, placement: placement))
                started = true
                onDone(true)
            case .cancelled:
                Analytics.track(.purchaseFailed(plan: buyingPlan.rawValue, placement: placement, reason: "cancelled"))
            case .pending:
                Analytics.track(.purchaseFailed(plan: buyingPlan.rawValue, placement: placement, reason: "pending"))
            case .unavailable:
                Analytics.track(.purchaseFailed(plan: buyingPlan.rawValue, placement: placement, reason: "failed"))
            }
        }
    }

    /// Try again: ask the App Store for the plans once more. The screen
    /// turns into the selling paywall by itself when they arrive.
    private func retryLoad() {
        guard !retrying else { return }
        retrying = true
        Task { @MainActor in
            await store.load()
            retrying = false
        }
    }

    /// A plan card tapped. Only a change is sent: a second tap on the lit
    /// card says nothing new.
    private func select(_ p: SubscriptionPlan) {
        if p != plan { Analytics.track(.planSelected(plan: p.rawValue, placement: placement)) }
        plan = p
    }

    /// Covers the prices with a rung of the "No, I don't want to pay" ladder.
    private func showRung(_ rung: DownsellRung) {
        Analytics.track(.offerViewed(rung: rung.analyticsName))
        route = .rung(rung)
    }

    private func restore() {
        Task { @MainActor in
            let synced = await store.restore()
            let outcome = store.entitled ? "restored" : synced ? "nothing" : "failed"
            Analytics.track(.restore(source: "paywall", outcome: outcome))
            if store.entitled {
                onDone(true)
            } else {
                // A Restore that finds nothing used to say nothing, which
                // reads as a broken button (Melvin, 2026-09-29).
                restoreFeedback = RestoreFeedback(entitled: false, synced: synced)
            }
        }
    }
}

/// The two documents the purchase screen must link to (guideline 3.1.2).
/// Also opened by Create your profile, for the community rules.
enum LegalDoc: String, Identifiable {
    case privacy, terms
    var id: String { rawValue }
    var file: String { self == .privacy ? "PRIVACY_POLICY" : "TERMS_OF_SERVICE" }
    var title: String { self == .privacy ? "Privacy Policy" : "Terms of Use" }
}

/// One bundled legal document in a sheet, the same way everywhere it opens.
struct LegalDocSheet: View {
    let doc: LegalDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView { MarkdownView(markdown: DocLoader.load(doc.file)).padding() }
                .navigationTitle(doc.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

// MARK: - 24 · (removed)

// The thirty-day exit offer is gone. The answers to a "no" are the ladder's
// free trial and its half-price plan (`DownsellRung.ladder`), a real cheaper plan rather than a
// second, better price for the same one, which would teach people that the
// first price was never the real one.

// MARK: - 25 · Sign in

/// Framed as saving the streak they just committed to, which is the honest
/// reason to have an account at all.
///
/// **The skip must exist for buyers too.** An earlier version hid it once
/// someone paid, on the theory that a purchase needs an account to attach to.
/// It doesn't: StoreKit entitlements ride the Apple ID and survive a new
/// phone with no account of ours, and 5.1.1(v) is explicit that registration
/// after a purchase that isn't account-based must be optional — apps get
/// rejected for exactly this. Sessions recorded before sign-in are safe
/// besides: the bootstrap-User adopt flow folds them into whichever account
/// is created later.
struct SignInScreen: View {
    let onSignedIn: (ASAuthorizationAppleIDCredential) -> Void
    let onSkip: (() -> Void)?
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            // A third of the way down rather than centred: in the valley the
            // middle of the screen is the ridge, and the words belong on sky.
            Spacer(minLength: 40)

            Image(systemName: "flame.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.accentGoldText)

            Text("Keep your streak\nsafe.")
                .font(OnboardingType.headline)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)

            Text("Sign in so your sessions and your streak survive a new phone. Apple handles it, so there's no password to make.")
                .font(OnboardingType.sub)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if let errorText {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
            }

            Spacer()
            Spacer()

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    if let cred = auth.credential as? ASAuthorizationAppleIDCredential {
                        onSignedIn(cred)
                    }
                case .failure(let error):
                    // A user-cancelled sign-in isn't an error worth shouting about.
                    let code = (error as NSError).code
                    if code != ASAuthorizationError.canceled.rawValue {
                        errorText = "Sign-in didn't complete. You can try again."
                    }
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

            if let onSkip {
                Button(action: onSkip) {
                    Text("Not now").modifier(FootnoteInk())
                }
                .font(.footnote.weight(.semibold))
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.win)
    }
}
