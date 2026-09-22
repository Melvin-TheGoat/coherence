import SwiftUI
import SwiftData
import AuthenticationServices

/// The app's root. Applies the one appearance and verifies the Sign in with
/// Apple credential at launch.
///
/// **There is no onboarding any more** (Aziz, 2026-09-21). The app opens on
/// Home, on the first launch and every launch after it. Nothing is asked
/// before the first sit: no interview, no projection, no Watch gate, no
/// account. The plus starts a session and the session is the app.
///
/// What the data said: of sixteen strangers who reached the first screen in
/// thirty days, twelve left on the second, and two of the twelve who finished
/// the whole flow ever pressed Begin. A flow that loses three quarters of the
/// people it meets before they have done the thing is not an introduction to
/// the product, it is a wall in front of it.
///
/// `Preferences.onboardingComplete` still exists and is still set, on first
/// launch, by `bootstrapIfNeeded` below. Dropping a synced property is a
/// migration hazard, several call sites read it as "this install is set up"
/// (`ReviewPrompt`, the Watch's start gate), and it is now simply true from
/// the beginning. The screens under `Coherence/Onboarding/` are no longer
/// reachable from anywhere; they are kept, unrouted, because the tour anchors
/// and the paywall ladder still live among them.
struct RootView: View {
    @Query private var preferences: [Preferences]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var coordinator: SessionCoordinator
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
        ContentView()
        .preferredColorScheme(colorScheme)
        // First launch has no Preferences row at all, and several things read
        // one. Write it before anything asks, and write it again if sign-out
        // clears it: there is nothing left to send anyone back to.
        .onChange(of: preferences.contains { $0.onboardingComplete }, initial: true) { _, done in
            if !done { SessionStore.completeOnboardingWithoutSignIn(in: context) }
            // The Watch gates its own Begin on this, so the wrist stays open
            // for as long as the phone is installed.
            coordinator.setOnboarded(true)
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
