import SwiftUI
import SwiftData

/// Gates the app on onboarding: until a User has completed onboarding (real
/// sign-in, or the dev skip), show `OnboardingView`; otherwise the app. Also
/// applies the user's theme app-wide. Reads Preferences reactively via `@Query`.
struct RootView: View {
    @Query private var preferences: [Preferences]

    var body: some View {
        Group {
            if preferences.contains(where: { $0.onboardingComplete }) {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch preferences.first?.themeValue {
        case .light: return .light
        case .dark: return .dark
        default: return nil   // system
        }
    }
}
