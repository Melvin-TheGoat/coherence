import SwiftUI
import AuthenticationServices
import StoreKit

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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        case .lifetime: return "Lifetime"
        }
    }

    var price: String {
        switch self {
        case .monthly:  return "$4.99"
        case .yearly:   return "$29.99"
        case .lifetime: return "$49.99"
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
    var anchorPrice: String {
        switch self {
        case .monthly:  return "$7.99"
        case .yearly:   return "$59.99"
        case .lifetime: return "$199"
        }
    }

    var cadence: String {
        switch self {
        case .monthly:  return "per month"
        case .yearly:   return "per year"
        case .lifetime: return "once"
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
        // $59.88 a year over 52 weeks. Weekly rather than daily: a cent
        // figure reads as a rounding trick, $1.15 reads as a price.
        case .monthly:  return "About $1.15 a week"
        // $29.99 over 12 months, and half the monthly plan, both true.
        case .yearly:   return "$2.50 a month"
        // $49.99 against $4.99 a month is 10.02 months.
        case .lifetime: return "Ten months, then never again"
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
                .padding(.top, 22)
                .sensoryFeedback(.success, trigger: rating)

                Text(rating == nil ? "Tap to answer" : "Thank you.")
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

/// The end of the road, not a negotiation. Seven days free or nothing: no
/// decline, no second offer, and no chevron back into the interview. A larger
/// offer one tap behind a "no" teaches people the first price was never real.
///
/// **Restore is not optional.** Apple requires a restore mechanism on any
/// screen selling an auto-renewable subscription (3.1.1), and with no decline
/// it is also the only honest way through for someone who already subscribed
/// and is reinstalling. It is wired to nothing today because StoreKit is not
/// wired to anything today; it must do real work before submission.
struct PaywallScreen: View {
    /// Where this paywall stands: "onboarding" or "root_lock". Analytics only.
    var placement: String = "onboarding"
    @State private var trackedView = false

    @State private var started = false
    /// The deepest rung the user actually saw, so `free_tier_entered` can say
    /// how far the ladder got before they settled.
    @State private var lastRung: DownsellRung?
    @State private var legalDoc: LegalDoc?
    /// What is covering the prices right now. Nil means the prices are showing.
    ///
    /// One cover, switching on a route, for the same reason the results screen
    /// has one sheet: stacking presentation modifiers on a single view is the
    /// documented only-one-presents trap.
    @State private var route: PaywallRoute?

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
    private var selling: Bool { store.state == .ready }

    /// Apple's price string when there is a real product, ours otherwise.
    /// A hardcoded dollar amount beside a live purchase button is wrong in
    /// every country but one.
    private var priceLine: String {
        store.displayPrice(for: plan).map { "\($0) \(plan.cadence)" }
            ?? "\(plan.price) \(plan.cadence)"
    }

    /// Whether the free week may be promised. StoreKit knows if this person
    /// already used the introductory offer; promising it anyway would put a
    /// claim on screen that the purchase sheet contradicts one tap later.
    private var offerTrial: Bool { store.trialEligible }

    var body: some View {
        OnboardingScreen(section: .win,
                         title: selling ? (offerTrial ? "Seven days free." : "Welcome back.")
                                        : "Free while we're testing.",
                         subtitle: selling
                            ? (offerTrial
                               ? "See it work first. If a week of measured sessions doesn't convince you, walk away and pay nothing."
                               : "Pick a plan to keep going. Every plan unlocks everything.")
                            : "Billing isn't switched on yet, so there's nothing to buy. Here's what it will cost when it is, and we'd genuinely like to know what you make of it.",
                         // The free week is the subscriptions' introductory
                         // offer. Lifetime has none: it is one charge, today,
                         // and both the button and the footnote must say so
                         // rather than promising a trial that won't happen.
                         ctaTitle: selling
                            ? (plan == .lifetime ? "Buy Lifetime"
                               : offerTrial ? "Start my free week" : "Subscribe")
                            : "Continue",
                         // 3.1.2 wants auto-renewal SAID, not implied: "cancel
                         // any time" hints at it and reviewers reject paywalls
                         // that only hint. Lifetime is the exception, it is a
                         // one-time purchase and claiming it renews would be
                         // its own lie.
                         ctaFootnote: selling
                            ? (plan == .lifetime
                               ? "\(priceLine), charged today. Nothing renews."
                               : offerTrial
                               ? "7 days free, then \(priceLine). Renews automatically until you cancel in Settings."
                               : "\(priceLine). Renews automatically until you cancel in Settings.")
                            : "Nothing is charged. There is no payment set up on this build.",
                         skipTitle: "Restore purchase",
                         onSkip: selling ? { restore() } : nil,
                         onContinue: { advance() }) {
            VStack(spacing: 11) {
                ForEach(SubscriptionPlan.allCases) { p in
                    Button { plan = p } label: {
                        HStack(spacing: 13) {
                            Image(systemName: plan == p ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 19))
                                .foregroundStyle(plan == p ? AppColor.accentGold
                                                           : AppColor.textSecondary.opacity(0.4))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColor.textPrimary)
                                if let note = p.note {
                                    Text(note)
                                        .font(.caption2)
                                        .foregroundStyle(AppColor.accentGoldText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 1) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    // Only shown against OUR price. Apple's
                                    // localized string is a different currency
                                    // in most countries, and a dollar anchor
                                    // beside a euro price is nonsense.
                                    if store.displayPrice(for: p) == nil {
                                        Text(p.anchorPrice)
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundStyle(AppColor.textSecondary.opacity(0.7))
                                            .strikethrough(true, color: AppColor.textSecondary.opacity(0.7))
                                    }
                                    Text(store.displayPrice(for: p) ?? p.price)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppColor.textPrimary)
                                }
                                Text(p.cadence)
                                    .font(.caption2)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                        .padding(16)
                        .background(plan == p ? AppColor.accentGold.opacity(0.10)
                                              : AppColor.backgroundSecondary.opacity(0.7),
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(plan == p ? AppColor.accentGold : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(CardButtonStyle())
                }
                .sensoryFeedback(.success, trigger: plan)
                .sensoryFeedback(.success, trigger: started)

                Text(selling ? "No charge today. We'll remind you before the trial ends."
                            : "Planned pricing. Nothing here can be bought yet.")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 4)

                // Guideline 3.1.2: any screen selling an auto-renewable
                // subscription must carry FUNCTIONAL links to the privacy
                // policy and Terms of Use, on the purchase screen itself, not
                // just in App Store Connect metadata. Kept visible in the beta
                // too: the documents are true regardless of whether billing is
                // on, and a link that appears only when money is involved is a
                // link someone forgot to test.
                HStack(spacing: 22) {
                    Button("Privacy Policy") { legalDoc = .privacy }
                    Button("Terms of Use") { legalDoc = .terms }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 2)

                // The way out. Only when there is something to decline, and
                // worded as a decision rather than an escape, because the
                // ladder behind it is an offer and not a trap.
                if selling || ProcessInfo.processInfo.isPreviewingDownsell {
                    Button("Not right now") {
                        Analytics.track(.paywallDismissed)
                        route = .rung(.trial)
                    }
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.top, 8)
                }
            }
            .fullScreenCover(item: $route) { destination in
                switch destination {
                case .rung(let current):
                    DownsellSheet(rung: current, plan: plan) {
                        // Taking a rung buys the plan that rung sells. A rung
                        // that congratulated someone and then charged them for
                        // a different plan would be the deception this ladder
                        // avoids.
                        plan = current.plan
                        route = nil
                        advance()
                    } onDecline: {
                        // Straight to the next rung, or to the free tier. No
                        // rung repeats, and the ladder no longer dead-ends:
                        // 808 is usable without paying, so the last thing it
                        // says should be that.
                        route = current.next.map { .rung($0) } ?? .freeTier
                        lastRung = current
                    }
                case .freeTier:
                    FreeTierScreen {
                        route = nil
                        advance()
                    } onContinueFree: {
                        Analytics.track(.freeTierEntered(
                            afterRung: lastRung?.analyticsName ?? "none"))
                        route = nil
                        onDone(false)
                    }
                }
            }
            .sheet(item: $legalDoc) { doc in
                NavigationStack {
                    ScrollView { MarkdownView(markdown: DocLoader.load(doc.file)).padding() }
                        .navigationTitle(doc.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .onAppear {
                guard !trackedView else { return }
                trackedView = true
                Analytics.track(.paywallViewed(placement: placement))
            }
        }
    }

    /// Continue. When nothing is on sale this is navigation; when something
    /// is, it is a purchase, and the screen only moves once StoreKit confirms.
    /// A cancelled or failed purchase stays put without comment, because the
    /// system sheet the user just dismissed IS the comment.
    private func advance() {
        guard selling else {
            #if DEBUG
            // Review mode: the "purchase" that StoreKit cannot run happens as
            // a simulated entitlement, so the unlock is real on this build and
            // the free → trial → unlocked loop can be reviewed end to end.
            if Store.previewFreeByDefault { store.setPreviewEntitled(true) }
            #endif
            onDone(false); return
        }
        Task { @MainActor in
            if await store.purchase(plan) == .bought {
                if store.trialEligible { Analytics.track(.trialStarted) }
                Analytics.track(.purchase(plan: plan.rawValue))
                started = true
                onDone(true)
            }
        }
    }

    private func restore() {
        Task { @MainActor in
            await store.restore()
            if store.entitled {
                Analytics.track(.restore)
                onDone(true)
            }
        }
    }
}

/// The two documents the purchase screen must link to (guideline 3.1.2).
private enum LegalDoc: String, Identifiable {
    case privacy, terms
    var id: String { rawValue }
    var file: String { self == .privacy ? "PRIVACY_POLICY" : "TERMS_OF_SERVICE" }
    var title: String { self == .privacy ? "Privacy Policy" : "Terms of Use" }
}

// MARK: - 24 · (removed)

// The thirty-day exit offer is gone, along with the paywall's decline. The
// offer is seven days free or nothing, and the paywall is the end of the
// road rather than a negotiation. Anything that reads as a second, better
// price teaches people that the first one was never the real one.

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
            Spacer()

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
                Button("Not now", action: onSkip)
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.win)
    }
}
