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
    private enum Step { case purpose, science, health, signIn }

    @Environment(\.modelContext) private var modelContext
    @State private var step: Step = .purpose
    @State private var errorText: String?
    @State private var showPrivacyPolicy = false

    var body: some View {
        ZStack {
            AppColor.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 16) {
                content
                    .id(step)   // fresh identity per page so transitions fire
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))

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
            docPage("PURPOSE", animated: true)   // the very first thing a user sees
        case .science:
            docPage("SCIENCE", animated: true)
        case .health:
            healthConsentPage
        case .signIn:
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                DrawnLogo()
                Text("808")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accentGold)
                    .fadeInUp(delay: 0.8)
                Text("Sign in to begin.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .fadeInUp(delay: 1.0)
                Text("Your sessions and streak stay yours. Apple handles sign-in — no password to create.")
                    .font(.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fadeInUp(delay: 1.2)
                Spacer(minLength: 0)
            }
        }
    }

    /// Health-data consent — shown before sign-in and before any measurement.
    /// Affirmative consent for consumer-health-data laws (e.g. WA MHMDA); the
    /// full policy is one tap away, and the footer button is the consent act.
    private var healthConsentPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DrawnLogo(markSize: 48, glowSize: 104)
                    .frame(maxWidth: .infinity)
                Text("Your health data")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fadeInUp(delay: 0.7)
                consentRow("applewatch", "Measured only during sessions",
                           "Your Apple Watch reads heart rate and movement only while a session you started is running.")
                    .fadeInUp(delay: 0.9)
                consentRow("iphone.and.arrow.forward", "Results stay on your device",
                           "Session results are computed on your devices and never uploaded — not to us, not to iCloud.")
                    .fadeInUp(delay: 1.05)
                consentRow("icloud", "Only your account syncs",
                           "Your account, preferences, and session log sync through your own private iCloud database.")
                    .fadeInUp(delay: 1.2)
                consentRow("hand.raised", "Never ads. Never sold.",
                           "Your health data is never used for advertising, never shared, never sold. Delete everything anytime in Settings.")
                    .fadeInUp(delay: 1.35)
                Button("Read the full Privacy Policy") { showPrivacyPolicy = true }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColor.accentGold)
                    .frame(maxWidth: .infinity)
                    .fadeInUp(delay: 1.5)
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationStack {
                ScrollView {
                    MarkdownView(markdown: DocLoader.load("PRIVACY_POLICY"))
                        .padding()
                }
                .background(AppColor.backgroundPrimary.ignoresSafeArea())
                .navigationTitle("Privacy Policy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showPrivacyPolicy = false }.tint(AppColor.accentGold)
                    }
                }
            }
        }
    }

    private func consentRow(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppColor.accentGold)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// A Purpose/Science page: the styled doc with a soft fade at the bottom edge
    /// so long copy visibly continues under the Continue button.
    private func docPage(_ name: String, animated: Bool) -> some View {
        ScrollView {
            MarkdownView(markdown: DocLoader.load(name), animated: animated)
                .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .mask(
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
            }
        )
    }

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .purpose:
            Button("Continue") { withAnimation(.easeInOut(duration: 0.4)) { step = .science } }
                .buttonStyle(PrimaryButtonStyle())
        case .science:
            Button("Continue") { withAnimation(.easeInOut(duration: 0.4)) { step = .health } }
                .buttonStyle(PrimaryButtonStyle())
        case .health:
            Button("I consent — continue") { withAnimation(.easeInOut(duration: 0.4)) { step = .signIn } }
                .buttonStyle(PrimaryButtonStyle())
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
            .fadeInUp(delay: 1.4)
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
