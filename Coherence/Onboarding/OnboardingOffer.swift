import SwiftUI
import AuthenticationServices

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

// MARK: - 23 · Paywall

struct PaywallScreen: View {
    @Binding var plan: SubscriptionPlan
    let onStartTrial: () -> Void
    let onDecline: () -> Void

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "Seven days free.",
                         subtitle: "See it work first. If a week of measured sessions doesn't convince you, walk away and pay nothing.",
                         ctaTitle: "Start my free week",
                         ctaFootnote: "7 days free, then \(plan.price) \(plan.cadence). Cancel any time in Settings.",
                         onSkip: onDecline,
                         onContinue: onStartTrial) {
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

                Text("No charge today. We'll remind you before the trial ends.")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - 24 · Exit offer

/// A real, larger offer — not a fake discount and not a countdown. If seven
/// days isn't enough to prove it, thirty is a fair thing to give.
struct ExitOfferScreen: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "Take a month\ninstead.",
                         subtitle: "No catch and no discount theatre. Meditation takes longer than a week to show up in the numbers, so have thirty days on us. Cancel whenever.",
                         ctaTitle: "Start my 30 days",
                         ctaFootnote: "30 days free. Cancel any time in Settings.",
                         onSkip: onDecline,
                         onContinue: onAccept) {
            HStack(spacing: 13) {
                Image(systemName: "calendar")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColor.accentGold)
                Text("Long enough to see a trend, not just a session.")
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(15)
            .background(AppColor.backgroundSecondary.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - 25 · Sign in

/// Framed as saving the streak they just committed to, which is the honest
/// reason to have an account at all.
struct SignInScreen: View {
    let onSignedIn: (ASAuthorizationAppleIDCredential) -> Void
    let onSkip: () -> Void
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

            Text("Sign in so your sessions and your streak survive a new phone. Apple handles it — there's no password to make.")
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

            Button("Not now", action: onSkip)
                .font(.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.win)
    }
}
