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

/// Two steps on purpose, and the second one is conditional.
///
/// Apple gives each user a very small number of review prompts a year and
/// **spends one whether they rate you or not**, so firing `requestReview` at
/// everybody burns that budget on the people most likely to leave two stars.
/// We ask our own question first and only surface Apple's sheet to people who
/// answered 4 or 5.
///
/// The honesty lives in the question: "does this sound like it'd work for you"
/// is answerable before anyone has used the app, where "enjoying 808?" is not.
/// Anyone who taps 1 to 3 simply moves on. No apology screen, no "help us
/// improve" detour, no attempt to talk them round.
struct RatingScreen: View {
    @Binding var rating: Int?
    let onContinue: () -> Void
    @Environment(\.requestReview) private var requestReview

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
        // Only spend Apple's prompt on someone who just told us it lands.
        if let rating, rating >= 4 {
            requestReview()
            // The sheet is presented by the system over this screen; give it a
            // beat before we navigate out from under it.
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                onContinue()
            }
        } else {
            onContinue()
        }
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
    @Binding var plan: SubscriptionPlan
    let onStartTrial: () -> Void
    let onRestore: () -> Void

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "Seven days free.",
                         subtitle: "See it work first. If a week of measured sessions doesn't convince you, walk away and pay nothing.",
                         ctaTitle: "Start my free week",
                         ctaFootnote: "7 days free, then \(plan.price) \(plan.cadence). Cancel any time in Settings.",
                         skipTitle: "Restore purchase",
                         onSkip: onRestore,
                         onContinue: { started = true; onStartTrial() }) {
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
                                Text(p.price)
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

                Text("No charge today. We'll remind you before the trial ends.")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 4)
            }
        }
    }
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
