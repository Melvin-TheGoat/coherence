import SwiftUI
import SwiftData
import AuthenticationServices

/// First-run onboarding: Purpose → Science → Sign in with Apple. Gated by
/// `Preferences.onboardingComplete` (see `RootView`). On successful sign-in the
/// bootstrap User is adopted so any pre-account sessions + streak survive.
///
/// NOTE: the copy here is a concise version; the full Purpose/Science pages
/// (`PURPOSE.md` / `SCIENCE.md`) can be surfaced here and re-read from Settings in
/// the rest of Phase 7.
struct OnboardingView: View {
    private enum Step { case purpose, science, signIn }

    @Environment(\.modelContext) private var modelContext
    @State private var step: Step = .purpose
    @State private var errorText: String?

    var body: some View {
        ZStack {
            AppColor.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer(minLength: 0)

                switch step {
                case .purpose:
                    page(
                        title: "808",
                        heading: "Meditation you can see.",
                        body: "Most people meditate blind — no way to know if it landed. 808 measures your practice on your Apple Watch and shows you the evidence afterward, session after session."
                    )
                case .science:
                    page(
                        title: "The evidence",
                        heading: "Three real signals.",
                        body: "Your stillness, your heart rate settling, and — when you lie down — your breathing slowing toward resonance. All measured on the Watch, all shown after, never as a live score to chase."
                    )
                case .signIn:
                    page(
                        title: "Save your progress",
                        heading: "Sign in to begin.",
                        body: "Your sessions and streak stay yours. Apple handles sign-in — no password to create."
                    )
                }

                Spacer(minLength: 0)

                footer

                if let errorText {
                    Text(errorText)
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(28)
        }
    }

    @ViewBuilder
    private func page(title: String, heading: String, body: String) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(AppColor.accentGold)
            Text(heading)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .purpose:
            Button("Continue") { step = .science }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accentGold)
        case .science:
            Button("Continue") { step = .signIn }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accentGold)
        case .signIn:
            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .frame(maxWidth: 320)

                #if DEBUG
                Button("Skip for now (dev)") {
                    SessionStore.completeOnboardingWithoutSignIn(in: modelContext)
                }
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
                #endif
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
                errorText = "Unexpected credential."
                return
            }
            SessionStore.signIn(
                appleUserID: cred.user,
                email: cred.email,
                displayName: cred.fullName.flatMap(formattedName),
                in: modelContext
            )
            // RootView's @Query on Preferences re-renders into the app.
        case .failure(let error):
            // User-cancelled is not an error worth surfacing.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorText = error.localizedDescription
        }
    }

    private func formattedName(_ comps: PersonNameComponents) -> String? {
        let formatter = PersonNameComponentsFormatter()
        let s = formatter.string(from: comps)
        return s.isEmpty ? nil : s
    }
}
