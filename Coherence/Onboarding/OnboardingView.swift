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
    /// Monthly, preselected (Aziz, 2026-08-24): the 7-day trial renews into
    /// Monthly, and the plan under the CTA must be the plan the footnote
    /// describes. Yearly and Lifetime stay one tap away for anyone who wants
    /// them.
    @State private var plan: SubscriptionPlan = .monthly
    @State private var waitlistEmail = ""
    @State private var planRating: Int?
    /// Whether the user actually turned the daily reminder on: tapped "Turn on
    /// my reminder" AND granted the OS dialog. The privacy policy says a
    /// reminder is sent "only if you enable it", and an earlier version set
    /// remindersEnabled from the anchor alone, which flipped it on for people
    /// who had just tapped "Not right now".
    @State private var reminderAllowed = false

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
        case blindSpot                                         // the regular's question
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
        /// Nil outside the interview. The denominator is filled in by the view
        /// from the persona's ACTUAL question list — a rail that counts twelve
        /// when this person will only be asked eight is a lie that gets more
        /// obvious the closer it gets to the end.
        var isInterview: Bool {
            OnboardingView.interviewPairs.contains { $0.0 == self }
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

    /// How far through THIS person's interview we are.
    private var interviewProgress: Double {
        guard let here = Self.interviewPairs.first(where: { $0.0 == step })?.1,
              let i = answers.interview.firstIndex(of: here) else { return 0 }
        return Double(i + 1) / Double(answers.interview.count)
    }

    /// The interview screens, paired with their pure-Foundation counterpart in
    /// `InterviewStep`. The branching lives in the model (and is exhaustively
    /// tested there); this is only the translation.
    static let interviewPairs: [(Step, InterviewStep)] = [
        (.baseline, .baseline), (.motivation, .motivation), (.stress, .stress),
        (.aloneWithThoughts, .aloneWithThoughts), (.doingNothing, .doingNothing),
        (.restarts, .restarts), (.intendedFor, .intendedFor), (.causes, .causes),
        (.blindSpot, .blindSpot), (.watchGate, .watchGate),
        (.anchor, .anchor), (.you, .you), (.referral, .referral),
    ]

    /// The next screen after `current`, skipping every question whose premise
    /// this user's answers contradict.
    ///
    /// This is the fix for the flow asking "What made you stop meditating?"
    /// immediately after someone answered "Never. This would be the start".
    /// Nothing downstream hardcodes an ordering any more.
    private func nextAfter(_ current: Step) -> Step {
        guard let here = Self.interviewPairs.first(where: { $0.0 == current })?.1 else {
            return .calculating
        }
        let remaining = answers.interview.drop { $0 != here }.dropFirst()
        guard let next = remaining.first,
              let step = Self.interviewPairs.first(where: { $0.1 == next })?.0 else {
            return .calculating     // interview over
        }
        return step
    }

    /// Where they've been, so the chevron can undo a wrong tap. A stack rather
    /// than `Step.allCases` order, because the flow branches: the Watch gate
    /// sends people to the waitlist, and back from there has to mean the gate.
    @State private var history: [Step] = []

    var body: some View {
        // The step haptic hangs off the ZStack, NOT off `content`.
        //
        // `.id(step)` gives the screen a new identity on every advance, and a
        // `.sensoryFeedback` inside that identity is rebuilt along with it: the
        // new modifier has no previous trigger value to compare against, so it
        // treats the current step as its initial one and stays silent. It was
        // written directly under `.id(step)` and never fired once. The ZStack's
        // identity is structural and survives, so the comparison survives too.
        //
        // Note for testing: the Simulator plays no haptics at all. Judging any
        // of this needs a device.
        ZStack {
            content
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))
                .animation(.easeInOut(duration: 0.32), value: step)
        }
            .environment(\.onboardingBack,
                         history.isEmpty || !step.allowsBack ? nil : goBack)
        #if DEBUG
            // Jump straight to one screen, with plausible answers already filled
            // in, so copy can be reviewed without tapping through the interview:
            //   SIMCTL_CHILD_ONBOARDING_STEP=14 xcrun simctl launch ...
            // Screens that reflect answers back (result, profile, projection)
            // need those answers to render, hence the sample set. Add
            // ONBOARDING_PERSONA=newcomer|restarter|regular to review the same
            // screen on each path, since they are answered differently.
            .onAppear {
                guard let raw = ProcessInfo.processInfo.environment["ONBOARDING_STEP"],
                      let index = Int(raw), let target = Step(rawValue: index) else { return }
                answers = .sample
                step = target
            }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .relief:
            ReliefScreen(onContinue: { go(.breath) }, onSignIn: { go(.signIn) })

        case .breath:
            BreathScreen { go(.baseline) }

        case .baseline:
            BaselineScreen(frequency: $answers.currentFrequency,
                           progress: interviewProgress) { go(nextAfter(.baseline)) }

        case .motivation:
            MotivationScreen(selected: $answers.motivations,
                             otherText: $answers.motivationOther,
                             progress: interviewProgress) { go(nextAfter(.motivation)) }

        case .stress:
            StressScreen(stress: $answers.stress,
                         progress: interviewProgress) { go(nextAfter(.stress)) }

        case .aloneWithThoughts:
            AloneWithThoughtsScreen(answer: $answers.aloneWithThoughts,
                                    progress: interviewProgress) { go(nextAfter(.aloneWithThoughts)) }

        case .doingNothing:
            DoingNothingScreen(answer: $answers.doingNothing,
                               progress: interviewProgress) { go(nextAfter(.doingNothing)) }

        case .restarts:
            RestartScreen(restarts: $answers.restarts,
                          progress: interviewProgress) { go(nextAfter(.restarts)) }

        case .intendedFor:
            IntendedForScreen(intended: $answers.intendedFor,
                              progress: interviewProgress) { go(nextAfter(.intendedFor)) }

        case .causes:
            CauseScreen(causes: $answers.causes,
                        progress: interviewProgress) { go(nextAfter(.causes)) }

        case .blindSpot:
            BlindSpotScreen(blindSpot: $answers.blindSpot,
                            progress: interviewProgress) { go(nextAfter(.blindSpot)) }

        case .watchGate:
            WatchGateScreen(hasWatch: $answers.hasWatch,
                            progress: interviewProgress,
                            onYes: {
                                Analytics.track(.watchGate(outcome: "hasWatch"))
                                go(nextAfter(.watchGate))
                            },
                            onNo: {
                                Analytics.track(.watchGate(outcome: "waitlist"))
                                go(.waitlist)
                            })

        case .waitlist:
            // Joining is optional either way: declining clears the email so
            // nothing half-typed gets stored at finish.
            WaitlistScreen(email: $waitlistEmail,
                           onJoin: { go(.anchor) },
                           onDecline: { waitlistEmail = ""; go(.anchor) })

        case .anchor:
            AnchorScreen(anchor: $answers.anchor,
                         progress: interviewProgress) { go(nextAfter(.anchor)) }

        case .you:
            NameScreen(firstName: $answers.firstName,
                       ageBracket: $answers.ageBracket,
                       progress: interviewProgress) { go(nextAfter(.you)) }

        case .referral:
            ReferralScreen(referral: $answers.referral,
                           progress: interviewProgress) { go(nextAfter(.referral)) }

        case .calculating:
            CalculatingScreen(firstName: answers.firstName,
                              answerCount: answeredCount) { go(.result) }

        case .result:
            // The cost screen is skipped (Melvin, 2026-08-25: another round
            // of questions right after the interview reads as being made to
            // work). The Step case and CostScreen stay so ONBOARDING_STEP
            // indices hold and the screen can come back with one edit; with
            // no costs ticked, downstream echoes (`primaryCost`) are nil and
            // every reader already handles nil.
            ResultScreen(answers: answers) { go(.wall) }

        case .cost:
            CostScreen(costs: $answers.costs) { go(.wall) }

        case .proofBody:
            ProofScreen(beat: .body) { go(.sampleStart) }

        // The start/build pair: the last beat of the cost arc asks "so what's
        // possible?", and the first beat of the win answers it.
        case .sampleStart:
            SampleSessionScreen(phase: .start) { go(.sampleBuild) }

        case .sampleBuild:
            SampleSessionScreen(phase: .build,
                                motivations: answers.motivations) { go(.proofYourWay) }

        case .proofYourWay:
            ProofScreen(beat: .yourWay) { go(.profile) }

        // The wall comes BEFORE the mechanism screen. Testers said the
        // company they'd be in was what opened them up; the explanation
        // lands better once they already want it to be true.
        case .wall:
            WallScreen { go(.proofBody) }

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
                             onAllow: { Task { reminderAllowed = await requestNotifications(); go(.week) } },
                             onSkip: { reminderAllowed = false; go(.week) })

        case .week:
            WeekPreviewScreen { go(.rating) }

        case .rating:
            RatingScreen(rating: $planRating) { go(.health) }

        case .health:
            HealthConsentScreen {
                // No-Watch users never see the paywall, whether or not they
                // joined the waitlist: we don't sell a subscription to someone
                // the app cannot yet work for.
                go(Self.paywallInsideOnboarding && answers.hasWatch != false ? .paywall : .signIn)
            }

        case .paywall:
            // Whether they bought or not, sign-in stays optional: a purchase
            // rides the Apple ID via StoreKit and needs no account of ours,
            // and 5.1.1(v) forbids requiring registration after a purchase
            // that isn't account-based. Sessions made before signing in are
            // folded into the account later by the bootstrap-adopt flow.
            PaywallScreen(plan: $plan) { _ in go(.signIn) }

        case .signIn:
            SignInScreen(onSignedIn: handleSignIn,
                         onSkip: finish)
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
        // One line covers the whole 26-screen funnel: the step being LEFT is
        // the one that was completed.
        Analytics.track(.onboardingStep(id: String(describing: step)))
        withAnimation { step = next }
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        withAnimation { step = previous }
    }

    // MARK: - Side effects

    /// True only if the user granted the OS dialog — declining there declines
    /// the reminder too, whatever button brought the dialog up.
    private func requestNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
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
        // The no-Watch waitlist. Until now the typed email was bound into a
        // @State and then dropped on the floor, which made the screen's
        // promise unkeepable. It lands on the local user row, where the
        // marketing export (stubbed, Phase 7) will read from, and it flips
        // the same product-emails opt-in Settings can undo.
        let joined = waitlistEmail.contains("@") && waitlistEmail.contains(".")
        if joined {
            if (user.email ?? "").isEmpty { user.email = waitlistEmail }
            user.marketingOptIn = true
        }
        Analytics.track(.onboardingCompleted)
        if let prefs = preferences.first(where: { $0.userID == user.id }) ?? preferences.first {
            prefs.onboardingComplete = true
            if let anchor = answers.anchor {
                // The time is stored either way: it is their stated anchor and
                // the default Settings offers if they enable reminders later.
                // Whether the reminder is ON is the permission screen's answer,
                // never the anchor's: picking a time of day is not consent to
                // be notified at it.
                prefs.reminderTime = Calendar.current.date(
                    bySettingHour: anchor.defaultHour, minute: 0, second: 0, of: Date())
                prefs.remindersEnabled = reminderAllowed
                NotificationScheduler.apply(enabled: reminderAllowed, at: prefs.reminderTime)
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
                    .foregroundStyle(AppColor.accentGoldText)
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
                        Button("Done") { showPrivacyPolicy = false }.tint(AppColor.accentGoldText)
                    }
                }
            }
        }
    }

    private func consentRow(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppColor.accentGoldText)
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
