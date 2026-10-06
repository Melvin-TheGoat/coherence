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
    @EnvironmentObject private var community: CommunityModel
    /// The plan the launch paywall has selected.
    @State private var lockPlan: SubscriptionPlan = .monthly
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the valley's sky is dark right now, so the status bar turns
    /// white (`statusScheme`). Re-read every minute and on every return.
    @State private var nightSky = RootView.skyIsDark
    @ObservedObject private var creamPages = CreamPages.shared
    @ObservedObject private var tourDim = TourDim.shared

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
    /// **It fails CLOSED** (Melvin, 2026-09-29: the app must never open free
    /// because the App Store could not load). An onboarded person with no
    /// entitlement meets the paywall whatever the store's state: `.ready`,
    /// `.unavailable` (offline, or a sandbox that did not answer), or a first
    /// fetch that has not answered in `storeWaitLimit`. The paywall then says
    /// the plans are not loading and offers Try again, Restore and Account.
    /// The rule itself is `LaunchLock.verdict`, pure and tested. A payer never
    /// meets it: StoreKit's on-device record is read before the plans. The
    /// side-by-side ".dev" beta, which owns no products, is the one build
    /// left open (`Monetization.isSideBySideBeta`).
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
        return launchVerdict == .lock
        #endif
    }

    /// The App Store has not answered yet, for somebody who may be locked.
    ///
    /// **The lock arrived a second late** (App Review, Melvin, 2026-09-29).
    /// The lock waited for `.ready`, so during the launch fetch the app itself
    /// showed, Home and all, and then the paywall slid in over it: a screen
    /// that reads as the app changing its mind, and a second of a paid app
    /// shown for free. So until the first answer, a non-member sees the
    /// valley with nothing on it, and then the lock or the app.
    ///
    /// `.loading` is only ever the launch state (`Store.load` moves it to
    /// `.ready` or `.unavailable` and never back), so this cannot come back
    /// mid-use. A payer is recognised from StoreKit's on-device record before
    /// the product fetch starts, so they go straight to the app.
    ///
    /// **The wait no longer ends in the app** (Melvin, same day, fail
    /// closed). A fetch that has not answered in `storeWaitLimit` ends in the
    /// paywall, whose Try again keeps asking; before, it opened the app, and
    /// so did `.unavailable`.
    private var awaitingStore: Bool {
        guard Monetization.premiumOnly else { return false }
        #if DEBUG
        // DEBUG never locks on the store's word (see `premiumLock`), so it
        // never has a reason to wait for it.
        return false
        #else
        return launchVerdict == .wait
        #endif
    }

    /// What the store's answer means for this launch (`LaunchLock`).
    private var launchVerdict: LaunchLock.Verdict {
        LaunchLock.verdict(state: store.state, entitled: store.entitled,
                           entitlementKnown: store.entitlementKnown,
                           waitExpired: storeWaitExpired,
                           sideBySideBeta: Monetization.isSideBySideBeta)
    }

    /// How long the launch waits for the App Store before showing the
    /// paywall in its "Plans aren't loading" state. Never before opening the
    /// app: that took a membership since 2026-09-29.
    private static let storeWaitLimit: Duration = .seconds(5)
    @State private var storeWaitExpired = false

    /// What the root shows once onboarding is done.
    private enum Face: Equatable { case onboarding, app, lock, waiting }

    /// Whether the app (`ContentView`) is what is on screen, as of the last
    /// render. The lock may only replace the app when this says no session
    /// is running inside it.
    @State private var appOnScreen = false

    private var face: Face {
        guard preferences.contains(where: { $0.onboardingComplete }) else { return .onboarding }
        // **Never swap the lock in over a running session** (Melvin,
        // 2026-09-29). Replacing ContentView tears down the live session's
        // cover mid-sit, so a subscription that lapses, or a store that only
        // now answers, waits until the session ends. Only a session inside
        // the app already on screen holds it: a Watch-started session arriving
        // while the lock is up does not open the app.
        if appOnScreen && coordinator.active != nil { return .app }
        if premiumLock { return .lock }
        // The wait is for the first answer only. Once the app is on screen it
        // stays there however the store's state moves.
        if awaitingStore && !appOnScreen { return .waiting }
        return .app
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
            } else if ProcessInfo.processInfo.environment["PREVIEW_SHIELD_REEL"] != nil {
                ShieldReel()
            } else if let mode = ProcessInfo.processInfo.environment["PREVIEW_STAGE_REEL"] {
                StageReel(onGreen: mode != "valley")
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
            switch face {
            case .onboarding:
                OnboardingView()
            case .lock:
                // It carries an Account link (manage, redeem, sign out,
                // delete: 5.1.1(v)), and for somebody who already has
                // sessions here, which is every 1.0 user who updates, the
                // line that says none of it is gone (Melvin, 2026-09-29).
                PaywallScreen(placement: "root_lock", memberNotice: hasPastSession,
                              plan: $lockPlan) { _ in }
            case .waiting:
                // The lock's own daytime valley with nothing on it, so the
                // lock arrives over the same sky rather than cutting to it.
                ValleyScene(progress: 0, showsFigure: false)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading")
            case .app:
                // Home's night dim, for every tab and every sheet.
                ContentView().environment(\.tileDim, ContentView.tileDim)
            }
        }
        .onChange(of: face, initial: true) { _, now in
            appOnScreen = now == .app
            // The home screen widget shows Otto to members only, so it hears
            // whenever the root moves between the app and the paywall.
            OttoWidgetPublisher.publish(context: context, member: now == .app)
        }
        .task {
            try? await Task.sleep(for: Self.storeWaitLimit)
            // A cancelled sleep throws and falls through; it must not end
            // the wait early.
            guard !Task.isCancelled else { return }
            storeWaitExpired = true
        }
        // Everything 808 draws stays light (see `colorScheme`); only what
        // iOS draws around it, the status bar above all, follows the sky.
        .environment(\.colorScheme, .light)
        .preferredColorScheme(statusScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                nightSky = Self.skyIsDark
                OttoWidgetPublisher.publish(context: context, member: face == .app)
            }
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
                // Friends forgets them too, exactly as a tapped sign-out does
                // (`AccountActions.signOut`): the profile stops showing and
                // stops being published to.
                community.signedOut()
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
    /// day. Onboarding, the launch paywall and the wait before it always draw
    /// a daytime valley, so they stay light.
    private var statusScheme: ColorScheme {
        // The tour dims the whole screen to near black at any hour, status
        // bar included, so its clock is white too (2026-10-01).
        if tourDim.showing { return .dark }
        return face == .app && nightSky && creamPages.showing == 0 ? .dark : .light
    }

    /// The same line the valley's words cross from dark ink to cream.
    private static var skyIsDark: Bool { DayLight.clockProgress() >= DayLight.inkTurn }
}

/// Cream pages that fill the screen, top edge included, and are on screen
/// right now (`keepsDarkStatusBar()`). After dark RootView turns the status
/// bar white for the night sky, and white on cream is no status bar at all,
/// so while one of these shows the root asks for the dark one again.
///
/// Counted here and decided at the root, never with a `preferredColorScheme`
/// on the page itself: that was tried first (2026-09-29) and SwiftUI kept
/// the pushed page's preference after it was popped, leaving a dark status
/// bar on the night sky behind it.
/// Whether the onboarding tour's dim is up (`TourHomeScreen`), for the
/// status bar.
@MainActor
final class TourDim: ObservableObject {
    static let shared = TourDim()
    @Published var showing = false
}

@MainActor
final class CreamPages: ObservableObject {
    static let shared = CreamPages()
    @Published private(set) var showing = 0
    func enter() { showing += 1 }
    func leave() { showing = max(0, showing - 1) }
}

private struct KeepsDarkStatusBar: ViewModifier {
    @State private var counted = false
    func body(content: Content) -> some View {
        content
            .onAppear { if !counted { counted = true; CreamPages.shared.enter() } }
            .onDisappear { if counted { counted = false; CreamPages.shared.leave() } }
    }
}

extension View {
    /// For a cream page pushed or covered full screen, reaching under the
    /// status bar: keeps the status bar dark at every hour. Not for sheets,
    /// whose status bar belongs to the page underneath.
    func keepsDarkStatusBar() -> some View { modifier(KeepsDarkStatusBar()) }

    /// The root's status bar rule, for the top view of a full-screen cover
    /// (2026-09-30). A cover takes its status bar from its own content, not
    /// from RootView, so a cream page inside one (Settings' documents,
    /// Otto's notes) kept the night's white bar. Applied at the cover's root,
    /// never on a pushed page, so there is nothing for a pop to leave behind.
    func followsStatusBarRule() -> some View { modifier(StatusBarRule()) }
}

private struct StatusBarRule: ViewModifier {
    @ObservedObject private var creamPages = CreamPages.shared
    func body(content: Content) -> some View {
        let night = DayLight.clockProgress() >= DayLight.inkTurn
        content.preferredColorScheme(night && creamPages.showing == 0 ? .dark : .light)
    }
}
