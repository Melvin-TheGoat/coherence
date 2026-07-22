import SwiftUI
import SwiftData

/// Gates the app on onboarding: until a User has completed onboarding (real
/// sign-in, or the dev skip), show `OnboardingView`; otherwise the app.
/// Reads `Preferences.onboardingComplete` reactively via `@Query`.
struct RootView: View {
    @Query private var preferences: [Preferences]

    var body: some View {
        if preferences.contains(where: { $0.onboardingComplete }) {
            ContentView()
        } else {
            OnboardingView()
        }
    }
}
