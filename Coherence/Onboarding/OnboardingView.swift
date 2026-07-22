import SwiftUI
import SwiftData
import AuthenticationServices

/// First-run onboarding: the full Purpose page → the full Science page → Sign in
/// with Apple. Gated by `Preferences.onboardingComplete` (see `RootView`). On
/// successful sign-in the bootstrap User is adopted so any pre-account sessions +
/// streak survive.
///
/// The Purpose/Science copy is the real, full `PURPOSE.md` / `SCIENCE.md`,
/// bundled and rendered (single source of truth — edits to the docs flow through).
struct OnboardingView: View {
    private enum Step { case purpose, science, signIn }

    @Environment(\.modelContext) private var modelContext
    @State private var step: Step = .purpose
    @State private var errorText: String?

    var body: some View {
        ZStack {
            AppColor.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 16) {
                content

                if let errorText {
                    Text(errorText)
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                footer
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .purpose:
            ScrollView { MarkdownView(markdown: DocLoader.load("PURPOSE")).padding(.vertical, 8) }
        case .science:
            ScrollView { MarkdownView(markdown: DocLoader.load("SCIENCE")).padding(.vertical, 8) }
        case .signIn:
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                Text("808")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppColor.accentGold)
                Text("Sign in to begin.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Your sessions and streak stay yours. Apple handles sign-in — no password to create.")
                    .font(.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
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
