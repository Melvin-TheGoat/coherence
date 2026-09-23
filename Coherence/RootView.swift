import SwiftUI
import SwiftData
import AuthenticationServices

/// Gates the app on onboarding: until a User has completed onboarding (real
/// sign-in, or the dev skip), show `OnboardingView`; otherwise the app. Also
/// applies the one appearance and verifies the Sign in with Apple credential
/// at launch. Reads Preferences reactively via `@Query`.
///
/// **Onboarding is back** (Melvin, 2026-09-22). Aziz removed it on 2026-09-21
/// (`d4ddbfc`), and Melvin, who had been rebuilding it that week, reversed
/// that the next day. It returns without the Watch gate, since a session no
/// longer needs a Watch.
struct RootView: View {
    @Query private var preferences: [Preferences]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var coordinator: SessionCoordinator
    @EnvironmentObject private var store: Store
    /// The plan the launch paywall has selected.
    @State private var lockPlan: SubscriptionPlan = .monthly

    /// **808 is premium only again** (Melvin and Aziz, 2026-09-23;
    /// `Monetization`). A person with no subscription meets the paywall at
    /// launch, the way they met it at the end of onboarding, and buying or
    /// restoring opens the app by itself (the store publishes `entitled`).
    ///
    /// History, so nobody re-derives it: the first hard paywall (2026-08-11)
    /// was reversed for a free tier on 2026-08-24, whose reasoning is in
    /// ENTITLEMENTS.md and whose code is still here, unreachable while
    /// `Monetization.premiumOnly` is true.
    ///
    /// **Only a store that can sell locks anything.** Offline, or before the
    /// products exist, the app stays open; see `Monetization`.
    private var premiumLock: Bool {
        guard Monetization.premiumOnly else { return false }
        #if DEBUG
        // Review the lock on a build with no products: HARD_PAYWALL=1. The
        // paywall's button then simulates the purchase, which opens the app.
        if ProcessInfo.processInfo.environment["HARD_PAYWALL"] == "1" {
            return !store.entitled && !store.previewEntitled
        }
        #endif
        return store.state == .ready && !store.entitled
    }

    var body: some View {
        Group {
            if preferences.contains(where: { $0.onboardingComplete }) {
                if premiumLock {
                    PaywallScreen(placement: "root_lock", plan: $lockPlan) { _ in }
                } else {
                    ContentView()
                }
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(colorScheme)
        // The Watch mirrors the onboarding fact. Reported at launch and on
        // every change, so finishing onboarding unlocks the wrist and signing
        // out re-locks it.
        .onChange(of: preferences.contains { $0.onboardingComplete }, initial: true) { _, done in
            coordinator.setOnboarded(done)
        }
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
                OttoChatStore.deleteAll()
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


    /// **808 has one appearance** (2026-09-19, Aziz: "get rid of the dark
    /// mode"). Not a default, not a preference: light, always, on every phone.
    ///
    /// The reason is Otto. The palette is sampled out of his artwork and the
    /// artwork is cream, so a dark build would need a second drawing of him
    /// and a second set of every tint, and the two would drift the moment one
    /// of them was touched. A product with one character is allowed one room
    /// for him to sit in. Every colour in the catalog now carries the same
    /// value in both appearances as a belt and braces, so even a view that
    /// escaped this override renders correctly.
    ///
    /// `Preferences.theme` and the `Theme` enum survive on purpose. Dropping a
    /// stored SwiftData property is a migration hazard, the field syncs
    /// through CloudKit to phones still running older builds, and nothing is
    /// bought by removing it. It is simply no longer read.
    private var colorScheme: ColorScheme? { .light }
}
