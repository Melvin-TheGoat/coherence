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
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the valley's sky is dark right now, so the status bar turns
    /// white (`statusScheme`). Re-read every minute and on every return.
    @State private var nightSky = RootView.skyIsDark

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
        // Otherwise a development build is never locked. The simulator on
        // Melvin's Mac reaches the real sandbox monthly and yearly, so since
        // the lock stopped waiting for Lifetime and the half-off year
        // (2026-09-28) every DEBUG launch, the laptop demo included, opened
        // on a paywall it could not get past without a sandbox account.
        return false
        #else
        return store.state == .ready && !store.entitled
        #endif
    }

    /// Whether any session is stored on this phone. A count with a limit of
    /// one, read only while the lock is up, so it costs nothing elsewhere.
    private var hasPastSession: Bool {
        var d = FetchDescriptor<Session>()
        d.fetchLimit = 1
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }

    var body: some View {
        Group {
            #if DEBUG
            if let hat = ProcessInfo.processInfo.environment["PREVIEW_HAT_GALLERY"] {
                HatGallery(firstID: hat)
            } else if ProcessInfo.processInfo.environment["PREVIEW_HAT_REEL"] != nil {
                HatReel()
            } else {
                app
            }
            #else
            app
            #endif
        }
    }

    @ViewBuilder private var app: some View {
        Group {
            if preferences.contains(where: { $0.onboardingComplete }) {
                if premiumLock {
                    // It carries an Account link (manage, redeem, sign out,
                    // delete: 5.1.1(v)), and for somebody who already has
                    // sessions here, which is every 1.0 user who updates, the
                    // line that says none of it is gone (Melvin, 2026-09-29).
                    PaywallScreen(placement: "root_lock", memberNotice: hasPastSession,
                                  plan: $lockPlan) { _ in }
                } else {
                    // Home's night dim, for every tab and every sheet.
                    ContentView().environment(\.tileDim, ContentView.tileDim)
                }
            } else {
                OnboardingView()
            }
        }
        // Everything 808 draws stays light (see `colorScheme`); only what
        // iOS draws around it, the status bar above all, follows the sky.
        .environment(\.colorScheme, .light)
        .preferredColorScheme(statusScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { nightSky = Self.skyIsDark }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                if nightSky != Self.skyIsDark { nightSky = Self.skyIsDark }
            }
        }
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
                // Signed out by iOS, not by a tap, so no `signed_out`; still a
                // new anonymous person from here.
                Analytics.reset()
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

    /// What iOS is told, as opposed to what 808 draws (Aziz, 2026-09-29:
    /// "make the status bar white at night too"). A light app has a dark
    /// status bar, which vanished into the night sky, and SwiftUI offers no
    /// status bar style of its own. So after dark iOS is told the app is
    /// dark, which turns the clock and battery white, while every view below
    /// is handed `.light` through the environment and renders exactly as by
    /// day. Onboarding and the launch paywall always draw a daytime valley,
    /// so they stay light.
    private var statusScheme: ColorScheme {
        let inApp = preferences.contains(where: { $0.onboardingComplete }) && !premiumLock
        return inApp && nightSky ? .dark : .light
    }

    /// The same line the valley's words cross from dark ink to cream.
    private static var skyIsDark: Bool { DayLight.clockProgress() >= DayLight.inkTurn }
}
