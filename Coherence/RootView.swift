import SwiftUI
import SwiftData
import AuthenticationServices

/// Gates the app on onboarding: until a User has completed onboarding (real
/// sign-in, or the dev skip), show `OnboardingView`; otherwise the app. Also
/// applies the user's theme app-wide. Reads Preferences reactively via `@Query`.
struct RootView: View {
    @Query private var preferences: [Preferences]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: Store
    @State private var lockedPlan: SubscriptionPlan = .yearly

    /// Paying unlocks the entire app (Aziz, 2026-08-11). The gate lives HERE,
    /// not in onboarding, because onboarding runs once and entitlement is a
    /// living fact: a lapsed subscription must re-lock the app, and StoreKit's
    /// cached entitlements flipping `store.entitled` is exactly that.
    ///
    /// The gate only exists while the store is actually SELLING. While
    /// products can't load (`.loading`, `.unavailable`) the app stays open:
    /// that is what keeps every beta tester in during the pre-billing era with
    /// no flag to remember, and it means a network hiccup can never lock out a
    /// paying user, because entitlements are cached on device and don't need
    /// the network to say yes.
    private var locked: Bool {
        store.state == .ready && !store.entitled
    }

    var body: some View {
        Group {
            if preferences.contains(where: { $0.onboardingComplete }) {
                if locked {
                    // The same paywall onboarding uses. Purchase and restore
                    // both flip `store.entitled`, which re-renders this view
                    // into the app; the closure has nothing left to do.
                    PaywallScreen(plan: $lockedPlan) { _ in }
                } else {
                    ContentView()
                }
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(colorScheme)
        .task {
            // A Sign in with Apple credential can be revoked from iOS Settings
            // at any moment, and Apple's SIWA rules require apps to verify the
            // credential at launch and treat a revoked one as signed out.
            // Without this, someone who cut 808 off in Settings would stay
            // signed in here forever on a dead identity. Only an explicit
            // .revoked signs out: .notFound fires transiently on simulators
            // and fresh installs, and signing out on it would be a trap.
            let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
            guard let signedIn = users.first(where: { $0.appleUserID != "" && $0.deletedAt == nil })
            else { return }
            let state = try? await ASAuthorizationAppleIDProvider()
                .credentialState(forUserID: signedIn.appleUserID)
            if state == .revoked {
                SessionStore.signOut(in: context)
            }
        }
        #if DEBUG
        // Headless previews (simulator automation): jump straight past onboarding.
        .onAppear {
            if ProcessInfo.processInfo.environment["SKIP_ONBOARDING"] == "1",
               !preferences.contains(where: { $0.onboardingComplete }) {
                SessionStore.completeOnboardingWithoutSignIn(in: context)
            }
        }
        #endif
    }

    private var colorScheme: ColorScheme? {
        switch preferences.first?.themeValue {
        case .light: return .light
        case .dark: return .dark
        default: return nil   // system
        }
    }
}
