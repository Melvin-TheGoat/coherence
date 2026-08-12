import SwiftUI
import AuthenticationServices
import StoreKit

/// Screens 23–25: the offer, the exit offer, and sign-in.
///
/// **Not wired to StoreKit.** There are no products configured yet, so the
/// trial button advances the flow and records intent locally. Nothing here
/// claims a charge has happened, and nothing pretends to be a receipt —
/// wiring real products is a separate, deliberate step.
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
        case .monthly:  return "$5"
        case .yearly:   return "$30"
        case .lifetime: return "$50"
        }
    }

    var cadence: String {
        switch self {
        case .monthly:  return "per month"
        case .yearly:   return "per year"
        case .lifetime: return "once"
        }
    }

    /// True arithmetic only — $30/yr against $5/mo is a real 50% saving.
    var note: String? {
        switch self {
        case .monthly:  return nil
        case .yearly:   return "Half the monthly price"
        case .lifetime: return "Pay once, keep it"
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
                                .foregroundStyle(AppColor.accentGold)
                                .opacity((rating ?? 0) >= star ? 1 : 0.35)
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                .padding(.top, 22)
                .sensoryFeedback(.selection, trigger: rating)

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
    @State private var started = false
    @State private var legalDoc: LegalDoc?
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

    var body: some View {
        OnboardingScreen(section: .win,
                         title: selling ? "Seven days free." : "Free while we're testing.",
                         subtitle: selling
                            ? "See it work first. If a week of measured sessions doesn't convince you, walk away and pay nothing."
                            : "Billing isn't switched on yet, so there's nothing to buy. Here's what it will cost when it is, and we'd genuinely like to know what you make of it.",
                         ctaTitle: selling ? "Start my free week" : "Continue",
                         ctaFootnote: selling
                            ? "7 days free, then \(priceLine). Cancel any time in Settings."
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
                                        .foregroundStyle(AppColor.accentGold)
                                }
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(store.displayPrice(for: p) ?? p.price)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColor.textPrimary)
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
                .sensoryFeedback(.selection, trigger: plan)
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
            }
            .sheet(item: $legalDoc) { doc in
                NavigationStack {
                    ScrollView { MarkdownView(markdown: DocLoader.load(doc.file)).padding() }
                        .navigationTitle(doc.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    /// Continue. When nothing is on sale this is navigation; when something
    /// is, it is a purchase, and the screen only moves once StoreKit confirms.
    /// A cancelled or failed purchase stays put without comment, because the
    /// system sheet the user just dismissed IS the comment.
    private func advance() {
        guard selling else { onDone(false); return }
        Task { @MainActor in
            if await store.purchase(plan) == .bought {
                started = true
                onDone(true)
            }
        }
    }

    private func restore() {
        Task { @MainActor in
            await store.restore()
            if store.entitled { onDone(true) }
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
struct SignInScreen: View {
    let onSignedIn: (ASAuthorizationAppleIDCredential) -> Void
    /// Nil once someone has paid: a paying customer's sessions and streak
    /// must survive a new phone, so the account stops being optional at the
    /// exact moment there's something worth protecting. The waitlist path
    /// (no Watch, nothing measured yet) keeps its way past.
    let onSkip: (() -> Void)?
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "flame.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.accentGold)

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
