import SwiftUI
import SwiftData
import AuthenticationServices

/// Gates the app on onboarding: until a User has completed onboarding (real
/// sign-in, or the dev skip), show `OnboardingView`; otherwise the app. Also
/// applies the user's theme app-wide. Reads Preferences reactively via `@Query`.
struct RootView: View {
    @Query private var preferences: [Preferences]
    @Environment(\.modelContext) private var context
    /// **808 is no longer a hard paywall** (Aziz, 2026-08-24), reversing the
    /// 2026-08-11 decision that paying unlocked the entire app. The app opens
    /// for everyone; what paying unlocks is the EVIDENCE behind the score.
    ///
    /// The gate did not disappear, it moved down a level into `Entitlements`,
    /// which each screen consults for the part it owns. Three reasons for the
    /// reversal, ascending: free users cost nothing because there is no
    /// backend; a hard paywall throttles installs by roughly 8x at median
    /// conversion; and asking for money before anyone has seen a single
    /// reading contradicts the one thing 808 sells, which is not being asked
    /// to take a claim on faith. See ENTITLEMENTS.md.

    var body: some View {
        Group {
            if preferences.contains(where: { $0.onboardingComplete }) {
                ContentView()
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
