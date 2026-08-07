import SwiftUI
import SwiftData
import AuthenticationServices

/// The onboarding flow — the interview, the reflection, the proof, the offer.
/// Spec and copy decisions live in `ONBOARDING.md`; the arithmetic behind the
/// projection and profile lives in `OnboardingModel.swift` (tested).
///
/// Gated by `Preferences.onboardingComplete` (see `RootView`). Answers are held
/// in memory and written once at the end: first name to the User, the anchor's
/// hour to the reminder time, so nothing is asked twice.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query private var preferences: [Preferences]

    @State private var step: Step = .relief
    @State private var answers = OnboardingAnswers()
    @State private var plan: SubscriptionPlan = .yearly
    @State private var waitlistEmail = ""
    @State private var planRating: Int?
    @State private var didJoinWaitlist = false

    /// Where the paywall sits. The spec's flow places it inside onboarding
    /// (screen 23), while its open-questions section argues for after the first
    /// session. Kept as one switch so moving it is a one-line change, not a
    /// re-plumb — see ONBOARDING.md "Open — needs a decision before building".
    private static let paywallInsideOnboarding = true

    enum Step: Int, CaseIterable {
        case relief, breath                                    // 1–2
        case baseline                                          // where they are today
        case motivation, stress                                // 3–4
        case aloneWithThoughts, doingNothing                   // escalation, then the evidence
        case restarts, intendedFor, causes                     // 5–6
        case watchGate, waitlist                               // 7, 7b
        case anchor, you, referral                             // 8–9, then attribution
        case calculating, result, cost                         // 10–12
        case proofBody, sampleStart, sampleBuild, proofYourWay // 13–15 (the pair replaced "so you get a number")
        case wall, profile, commitment, projection, how        // 16–16d, 20
        case permission, week, rating                          // 21–22, 22b
        case health                                            // consent, kept from the old flow
        case paywall, signIn                                   // 23, 25

        /// Progress rail: only the interview shows one. Once we're reflecting
        /// back and selling, a progress bar just tells them how much sales
        /// copy is left.
        var interviewProgress: Double? {
            let interview: [Step] = [.baseline, .motivation, .stress, .aloneWithThoughts,
                                     .doingNothing, .restarts, .intendedFor, .causes,
                                     .watchGate, .anchor, .you, .referral]
            guard let i = interview.firstIndex(of: self) else { return nil }
            return Double(i + 1) / Double(interview.count)
        }

        /// The offer is one way. Once someone reaches the paywall there is no
        /// chevron: reversing out of a price into the interview turns a
        /// decision into something to be negotiated around, which is the same
        /// reason the thirty-day exit offer is gone.
        var allowsBack: Bool {
            switch self {
            case .paywall, .signIn: return false
            default: return true
            }
        }
    }

    /// Where they've been, so the chevron can undo a wrong tap. A stack rather
    /// than `Step.allCases` order, because the flow branches: the Watch gate
    /// sends people to the waitlist, and back from there has to mean the gate.
    @State private var history: [Step] = []

    var body: some View {
        content
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)))
            .animation(.easeInOut(duration: 0.32), value: step)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: step)
            .environment(\.onboardingBack,
                         history.isEmpty || !step.allowsBack ? nil : goBack)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .relief:
            ReliefScreen { go(.breath) }

        case .breath:
            BreathScreen { go(.baseline) }

        case .baseline:
            BaselineScreen(frequency: $answers.currentFrequency,
                           progress: step.interviewProgress ?? 0) { go(.motivation) }

        case .motivation:
            MotivationScreen(selected: $answers.motivations,
                             progress: step.interviewProgress ?? 0) { go(.stress) }

        case .stress:
            StressScreen(stress: $answers.stress,
                         progress: step.interviewProgress ?? 0) { go(.aloneWithThoughts) }

        case .aloneWithThoughts:
            AloneWithThoughtsScreen(answer: $answers.aloneWithThoughts,
                                    progress: step.interviewProgress ?? 0) { go(.doingNothing) }

        case .doingNothing:
            DoingNothingScreen(answer: $answers.doingNothing,
                               progress: step.interviewProgress ?? 0) { go(.restarts) }

        case .restarts:
            RestartScreen(restarts: $answers.restarts,
                          progress: step.interviewProgress ?? 0) { go(.intendedFor) }

        case .intendedFor:
            IntendedForScreen(intended: $answers.intendedFor,
                              progress: step.interviewProgress ?? 0) { go(.causes) }

        case .causes:
            CauseScreen(causes: $answers.causes,
                        progress: step.interviewProgress ?? 0) { go(.watchGate) }

        case .watchGate:
            WatchGateScreen(hasWatch: $answers.hasWatch,
                            progress: step.interviewProgress ?? 0,
                            onYes: { go(.anchor) },
                            onNo: { go(.waitlist) })

        case .waitlist:
            // No "Skip" here any more: it sat under the CTA reading like it
            // skipped the waitlist when it actually went back to the gate. The
            // chevron does that now, and says so.
            WaitlistScreen(email: $waitlistEmail) {
                didJoinWaitlist = true
                // They can still look around; we just never sell them
                // something that can't work for them yet.
                go(.anchor)
            }

        case .anchor:
            AnchorScreen(anchor: $answers.anchor,
                         progress: step.interviewProgress ?? 0) { go(.you) }

        case .you:
            NameScreen(firstName: $answers.firstName,
                       ageBracket: $answers.ageBracket,
                       progress: step.interviewProgress ?? 0) { go(.referral) }

        case .referral:
            ReferralScreen(referral: $answers.referral,
                           progress: step.interviewProgress ?? 0) { go(.calculating) }

        case .calculating:
            CalculatingScreen(firstName: answers.firstName,
                              answerCount: answeredCount) { go(.result) }

        case .result:
            ResultScreen(answers: answers) { go(.cost) }

        case .cost:
            CostScreen(costs: $answers.costs) { go(.proofBody) }

        case .proofBody:
            ProofScreen(beat: .body) { go(.sampleStart) }

        // The start/build pair: the last beat of the cost arc asks "so what's
        // possible?", and the first beat of the win answers it.
        case .sampleStart:
            SampleSessionScreen(phase: .start) { go(.sampleBuild) }

        case .sampleBuild:
            SampleSessionScreen(phase: .build) { go(.proofYourWay) }

        case .proofYourWay:
            ProofScreen(beat: .yourWay) { go(.wall) }

        case .wall:
            WallScreen { go(.profile) }

        case .profile:
            ProfileScreen(answers: answers) { go(.commitment) }

        // Commitment comes BEFORE the projection: the projection is arithmetic
        // from the days-per-week they commit to, so we can't draw it first.
        case .commitment:
            CommitmentScreen(daysPerWeek: $answers.daysPerWeek,
                             anchor: answers.anchor,
                             cost: answers.primaryCost) { go(.projection) }

        case .projection:
            ProjectionScreen(daysPerWeek: answers.daysPerWeek) { go(.how) }

        case .how:
            HowScreen(answers: answers) { go(.permission) }

        case .permission:
            PermissionScreen(anchor: answers.anchor,
                             onAllow: { Task { await requestNotifications(); go(.week) } },
                             onSkip: { go(.week) })

        case .week:
            WeekPreviewScreen { go(.rating) }

        case .rating:
            RatingScreen(rating: $planRating) { go(.health) }

        case .health:
            HealthConsentScreen {
                go(Self.paywallInsideOnboarding && !didJoinWaitlist ? .paywall : .signIn)
            }

        case .paywall:
            PaywallScreen(plan: $plan,
                          onStartTrial: { go(.signIn) },
                          onRestore: { go(.signIn) })

        case .signIn:
            SignInScreen(onSignedIn: handleSignIn, onSkip: finish)
        }
    }

    /// How many interview questions they actually answered — spoken aloud on
    /// the calculating screen, so it has to be the real count rather than a
    /// hardcoded number that a skipped question would make a lie.
    private var answeredCount: Int {
        var n = 0
        if answers.currentFrequency != nil { n += 1 }
        if !answers.motivations.isEmpty { n += 1 }
        n += 1                                        // stress slider always has a value
        if answers.aloneWithThoughts != nil { n += 1 }
        if answers.doingNothing != nil { n += 1 }
        if answers.restarts != nil { n += 1 }
        if answers.intendedFor != nil { n += 1 }
        if !answers.causes.isEmpty { n += 1 }
        if answers.hasWatch != nil { n += 1 }
        if answers.anchor != nil { n += 1 }
        if !answers.firstName.trimmingCharacters(in: .whitespaces).isEmpty { n += 1 }
        if answers.referral != nil { n += 1 }
        return n
    }

    // MARK: - Navigation

    private func go(_ next: Step) {
        history.append(step)
        withAnimation { step = next }
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        withAnimation { step = previous }
    }

    // MARK: - Side effects

    private func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func handleSignIn(_ credential: ASAuthorizationAppleIDCredential) {
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")
        _ = SessionStore.signIn(appleUserID: credential.user,
                                email: credential.email,
                                displayName: name.isEmpty ? typedName : name,
                                in: context)
        persistAnswers()
    }

    private var typedName: String? {
        let n = answers.firstName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? nil : n
    }

    private func finish() {
        persistAnswers()
    }

    /// Written once, at the end. The anchor becomes the reminder time so we
    /// never ask twice for a fact they already gave us.
    private func persistAnswers() {
        let user = SessionStore.currentUser(in: context)
        if let typedName, (user.displayName ?? "").isEmpty {
            user.displayName = typedName
        }
        if let prefs = preferences.first(where: { $0.userID == user.id }) ?? preferences.first {
            prefs.onboardingComplete = true
            if let anchor = answers.anchor {
                prefs.reminderTime = Calendar.current.date(
                    bySettingHour: anchor.defaultHour, minute: 0, second: 0, of: Date())
                prefs.remindersEnabled = true
                NotificationScheduler.apply(enabled: true, at: prefs.reminderTime)
            }
        }
        try? context.save()
    }
}

// MARK: - Health consent (kept from the pre-MVP flow)

/// Affirmative consent for consumer-health-data laws (e.g. WA MHMDA), shown
/// before any measurement. The continue button is the consent act, and the
/// full policy is one tap away.
struct HealthConsentScreen: View {
    let onContinue: () -> Void
    @State private var showPrivacyPolicy = false

    var body: some View {
        OnboardingScreen(section: .win,
                         title: "Your health data.",
                         subtitle: "Before anything gets measured, here's exactly what happens to it.",
                         ctaTitle: "I understand",
                         onContinue: onContinue) {
            VStack(spacing: 12) {
                consentRow("applewatch", "Measured only during sessions",
                           "Your Watch reads heart rate and movement only while a session you started is running.")
                consentRow("iphone.and.arrow.forward", "Results stay on your device",
                           "Session results are computed on your devices and never uploaded. Not to us, not to iCloud.")
                consentRow("icloud", "Only your account syncs",
                           "Your account, preferences, and session log sync through your own private iCloud database.")
                consentRow("hand.raised", "Never ads. Never sold.",
                           "Your health data is never used for advertising, never shared, never sold. Delete everything any time in Settings.")

                Button("Read the full Privacy Policy") { showPrivacyPolicy = true }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColor.accentGold)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationStack {
                ScrollView {
                    MarkdownView(markdown: DocLoader.load("PRIVACY_POLICY")).padding()
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColor.backgroundSecondary.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
