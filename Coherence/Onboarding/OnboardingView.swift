import SwiftUI
import SwiftData
import AuthenticationServices
import WatchConnectivity

/// The onboarding flow — the interview, the reflection, the proof, the offer.
/// Spec and copy decisions live in `ONBOARDING.md`; the arithmetic behind the
/// projection and profile lives in `OnboardingModel.swift` (tested).
///
/// Gated by `Preferences.onboardingComplete` (see `RootView`). Answers are held
/// in memory and written once at the end: first name to the User, the anchor's
/// hour to the reminder time, so nothing is asked twice.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var community: CommunityModel
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
    /// FALSE since 2026-09-15 (Melvin): the paywall comes after the first
    /// meditation, from ContentView (`FirstSessionOffer`), once the person has
    /// seen their own score, curves and readings. Onboarding sells nothing.
    private static let paywallInsideOnboarding = false

    enum Step: Int, CaseIterable {
        case relief, breath                                    // 1–2
        case baseline                                          // where they are today
        case motivation, stress                                // 3–4
        case aloneWithThoughts, doingNothing                   // escalation, then the evidence
        case restarts, intendedFor                             // 5–6
        case bodyCuriosity, bodyProof, bodyTracking            // the body questions
        case hardware                                          // the accessibility reveal
        case blindSpot                                         // the regular's question
        case watchGate, waitlist                               // 7, 7b
        case watchSetup                                        // 7c: getting 808 on the wrist
        case anchor, you, referral                             // 8–9, then attribution
        case calculating, result, cost                         // 10–12
        case proofBody, sampleStart, sampleBuild, proofYourWay // 13–15 (the pair replaced "so you get a number")
        case wall, commitment                                  // 16, 20
        case permission, week, rating                          // 21–22, 22b
        case health                                            // consent, kept from the old flow
        case tourHome, watchConnect, breathe, sessionResults   // the walkthrough
        case paywall, signIn                                   // 23, 25
        case profile                                           // Friends: photo + @username
        /// Added for the v3 opening (2026-09-20), screens 3 and 7.
        ///
        /// **THEY ARE LAST ON PURPOSE AND EVERY NEW CASE MUST BE.** `Step` is
        /// `Int`-backed, so a case inserted in the middle renumbers every one
        /// after it, and a saved resume record then reopens somebody on a
        /// different screen than the one they left. They were briefly added
        /// after `breath`, which shifted thirty-odd cases by two before this
        /// was caught.
        case breathing, whatsWaiting
        /// Added 2026-09-20: how many questions are coming, declared before
        /// the first one. Last in the enum, for the reason above.
        case questionCount

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
        /// Screens that were cut and now only pass the reader on (`Color.clear`
        /// that calls `go` on appear). They never enter the Back history:
        /// the last question routes through `.calculating` on its way to
        /// What's waiting, so Back from there landed on `.calculating`, which
        /// immediately sent the reader forward again, and Back did nothing.
        var onlyPassesThrough: Bool {
            switch self {
            case .aloneWithThoughts, .doingNothing, .bodyProof, .anchor, .you,
                 .calculating, .result, .cost, .proofBody, .sampleStart,
                 .sampleBuild, .proofYourWay, .commitment, .wall, .week,
                 .rating, .watchConnect, .breathe, .sessionResults, .paywall,
                 .watchGate, .watchSetup, .waitlist:
                return true
            default:
                return false
            }
        }

        var allowsBack: Bool {
            switch self {
            case .paywall, .signIn, .profile: return false
            // Mid-practice and mid-result: backing into the interview from a
            // running Watch session would strand the session. The wall sits
            // just after them now, so it gets no chevron either.
            case .breathe, .sessionResults, .wall: return false
            default: return true
            }
        }
    }

    /// How far through THIS person's interview we are.
    /// This reader's position in their own interview. Nil off the interview.
    private var interviewCount: InterviewCount {
        guard let here = Self.interviewPairs.first(where: { $0.0 == step })?.1,
              let i = answers.interview.firstIndex(of: here) else {
            return InterviewCount(index: 1, total: max(1, answers.interview.count))
        }
        return InterviewCount(index: i + 1, total: answers.interview.count)
    }

    /// The interview screens, paired with their pure-Foundation counterpart in
    /// `InterviewStep`. The branching lives in the model (and is exhaustively
    /// tested there); this is only the translation.
    static let interviewPairs: [(Step, InterviewStep)] = [
        (.referral, .referral),
        (.baseline, .baseline), (.motivation, .motivation), (.stress, .stress),
        (.restarts, .restarts), (.intendedFor, .intendedFor),
        (.bodyCuriosity, .bodyCuriosity),
        (.bodyTracking, .bodyTracking),
        (.blindSpot, .blindSpot),
    ]

    /// The interview's first screen, read from the model's order rather than
    /// hardcoded, so reordering `InterviewStep` moves the door with it.
    private var firstInterviewStep: Step {
        answers.interview.first.flatMap { first in
            Self.interviewPairs.first { $0.1 == first }?.0
        } ?? .baseline
    }

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

    /// The session the walkthrough's breathing practice produced.
    @State private var walkthroughSessionID: UUID?

    /// After the wall: sign-in (optional), then the tour for Watch owners.
    /// The wall sits between health consent and sign-in for everyone: the
    /// company they'd be in, right before the app asks them for anything.
    private var afterWall: Step {
        Self.paywallInsideOnboarding ? .paywall : .signIn
    }

    /// Whether this iPhone has an Apple Watch paired. It replaced the
    /// question "Do you have an Apple Watch?" (2026-09-22): the phone already
    /// knows. Only a paired Watch measures anything, so only then do the
    /// health consent screen and the Health prompt behind it have something
    /// to be about. `SessionCoordinator` activates the session at launch,
    /// long before anyone reaches the screen that asks.
    private var watchPaired: Bool {
        WCSession.isSupported()
            && WCSession.default.activationState == .activated
            && WCSession.default.isPaired
    }

    /// Reminders lead to health consent on a phone with a Watch, and past it
    /// on one without, so the skipped screen never enters the Back history.
    private var afterPermission: Step { watchPaired ? .health : .wall }

    /// Ask for Health here, on the phone, one screen after the one that
    /// explains what is read. HealthKit authorization is SHARED with the
    /// companion Watch app and the system can only present the sheet on the
    /// iPhone, so asking from the Watch mid-session (what the app used to do)
    /// put the prompt on a screen nobody was looking at: the workout ran, no
    /// heart rate arrived, and the 30-second watchdog aborted the first
    /// session. Four of ten start failures in the first week of live data
    /// were exactly that.
    private var healthConsent: some View {
        HealthConsentScreen {
            Task {
                await HealthScope.request()
                // Route after the sheet is dismissed, so the tour never
                // starts underneath a system prompt.
                await MainActor.run { go(.wall) }
            }
        }
    }

    /// After the account step (sign-in, and Create your profile on Friends
    /// builds): everyone gets the tour, since a session no longer needs a
    /// Watch (2026-09-22).
    private func afterAccount() {
        go(.tourHome)
    }

    @State private var resumed = false

    /// Where they've been, so the chevron can undo a wrong tap. A stack rather
    /// than `Step.allCases` order, because the flow branches: the Watch gate
    /// sends people to the waitlist, and back from there has to mean the gate.
    @State private var history: [Step] = []

    /// Which way the next screen change slides. **Back slides the other
    /// way** (Melvin, 2026-09-21: Back looked like progressing): the screen
    /// you return to comes in from the left and the one you leave exits
    /// right.
    enum Motion { case forward, back }
    @State private var motion: Motion = .forward

    /// The identity each step is drawn under. The invitation to breathe and
    /// the breaths are one screen, so they share one identity and changing
    /// between them is not a transition at all.
    private var screenIdentity: Step { Self.identity(of: step) }
    private static func identity(of step: Step) -> Step { step == .breathing ? .breath : step }

    private var screenTransition: AnyTransition {
        switch motion {
        case .forward:
            return .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                               removal: .move(edge: .leading).combined(with: .opacity))
        case .back:
            return .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                               removal: .move(edge: .trailing).combined(with: .opacity))
        }
    }

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
                .id(screenIdentity)
                .transition(screenTransition)
                .animation(.easeInOut(duration: 0.32), value: screenIdentity)
        }
            .environment(\.onboardingBack,
                         history.isEmpty || !step.allowsBack ? nil : goBack)
            .onAppear {
                #if DEBUG
                // A DEBUG jump to one screen wins over saved progress.
                if ProcessInfo.processInfo.environment["ONBOARDING_STEP"] != nil { return }
                #endif
                resumeIfSaved()
            }
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
                // Jumping to the walkthrough's results needs a session to
                // show; seed the demo one so the tour is reviewable without
                // breathing at a Watch first.
                if target == .sessionResults {
                    walkthroughSessionID = DemoData.seedResults(in: context)
                }
                step = target
            }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .relief:
            WelcomeScreen { go(.breath) }

        // ONE case for both steps, so SwiftUI sees one view: "I'm ready"
        // moves the step (analytics and resume stay exactly as they were)
        // and the screen simply starts breathing. Two cases would be two
        // views, and the change between them would be a transition.
        case .breath, .breathing:
            BreathExerciseScreen(breathing: step == .breathing,
                                 onReady: { go(.breathing) },
                                 onContinue: { go(.questionCount) })

        case .questionCount:
            QuestionCountScreen { go(firstInterviewStep) }

        case .baseline:
            BaselineScreen(frequency: $answers.currentFrequency,
                           count: interviewCount) { go(nextAfter(.baseline)) }

        case .motivation:
            MotivationScreen(selected: $answers.motivations,
                             otherText: $answers.motivationOther,
                             count: interviewCount) { go(nextAfter(.motivation)) }

        case .stress:
            StressScreen(stress: $answers.stress,
                         count: interviewCount) { go(nextAfter(.stress)) }

        // Cut 2026-09-15 (doingNothing) and 2026-09-19 (aloneWithThoughts,
        // Melvin). The Step cases stay so resume records and ONBOARDING_STEP
        // indices hold; anyone landing here moves on from the stress screen,
        // which is the last question still asked before this point.
        case .aloneWithThoughts, .doingNothing:
            Color.clear.onAppear { go(nextAfter(.stress)) }

        case .restarts:
            guarded(.restarts) {
                RestartScreen(restarts: $answers.restarts,
                              count: interviewCount) { go(nextAfter(.restarts)) }
            }

        case .intendedFor:
            guarded(.intendedFor) {
                IntendedForScreen(intended: $answers.intendedFor,
                                  count: interviewCount) { go(nextAfter(.intendedFor)) }
            }

        case .bodyCuriosity:
            guarded(.bodyCuriosity) {
                BodyCuriosityScreen(answer: $answers.bodyCuriosity,
                                    count: interviewCount) { go(nextAfter(.bodyCuriosity)) }
            }

        // Cut 2026-09-15, same arrangement.
        case .bodyProof:
            Color.clear.onAppear { go(nextAfter(.bodyCuriosity)) }

        case .bodyTracking:
            BodyTrackingScreen(tracking: $answers.bodyTracking,
                               count: interviewCount) { go(nextAfter(.bodyTracking)) }

        // No longer on the path (Melvin, 2026-09-14). A tester with no Watch
        // met "$400" mid-interview and read it as an upsell aimed at someone
        // else. The screen now lives in the paywall ladder, shown only to a
        // person who has just declined to pay, where an anchor belongs. The
        // Step case stays so ONBOARDING_STEP can still jump to it.
        case .hardware:
            HardwareScreen(onContinue: { go(nextAfter(.bodyTracking)) })

        case .blindSpot:
            guarded(.blindSpot) {
                BlindSpotScreen(blindSpot: $answers.blindSpot,
                                count: interviewCount) { go(nextAfter(.blindSpot)) }
            }

        // CUT 2026-09-22 (Melvin: "get rid of the watch screen"). A session
        // runs on the phone with or without a Watch since Aziz's valley
        // change, so the gate, its setup screen and the no-Watch waitlist
        // sorted people for a difference the app no longer makes. The Step
        // cases and screens stay for resume records; anyone landing on one
        // goes on to what's waiting, where the interview used to end.
        case .watchGate, .watchSetup, .waitlist:
            Color.clear.onAppear { go(.whatsWaiting) }

        // Cut 2026-09-15 (Melvin: nobody wants to be made to commit to a
        // time of day). The reminder time is picked on the permission screen.
        case .anchor:
            Color.clear.onAppear { go(.whatsWaiting) }

        // Cut 2026-09-19 (Melvin): the name is asked on Create your profile
        // beside the handle, and the age was never used. Anyone resuming
        // here goes straight to the sum.
        case .you:
            Color.clear.onAppear { go(.whatsWaiting) }

        case .referral:
            ReferralScreen(referral: $answers.referral,
                           count: interviewCount) { go(nextAfter(.referral)) }

        // CUT 2026-09-20 (Melvin: redo onboarding in Headspace's shape).
        // The whole payoff block goes: calculating, the result, the cost, the
        // sample-session pair, the commitment and the wall. The mockup has
        // nine screens and this block was most of the twenty that were not in
        // it. **The analytics said this block loses nobody**, which is why it
        // survived the 09-15 cut; it goes now because it is not in the shape,
        // not because it was failing. Watch `onboarding_completed` against
        // the pre-cut rate: if finishing drops, this is the first suspect.
        //
        // Every Step case and answer field stays, per the standing rule, so
        // resume records decode and ONBOARDING_STEP indices hold. Nothing
        // outside Onboarding/ reads `daysPerWeek`, `primaryCost` or
        // `PersonalPlan`, checked before cutting, so no other screen loses a
        // number it was drawing.
        case .calculating, .result, .cost, .proofBody, .sampleStart,
             .sampleBuild, .proofYourWay, .commitment:
            Color.clear.onAppear { go(.whatsWaiting) }

        // Cut with the payoff block (2026-09-20). Kept as a case for resume
        // records; `WallScreen` stays in the file because bringing the quotes
        // back is then one line rather than a rewrite.
        case .wall:
            Color.clear.onAppear { go(afterWall) }

        case .whatsWaiting:
            WhatsWaitingScreen { go(.permission) }

        case .permission:
            PermissionScreen(reminderTime: $answers.reminderTime,
                             onAllow: { Task { reminderAllowed = await requestNotifications(); go(afterPermission) } },
                             onSkip: { reminderAllowed = false; go(afterPermission) })

        case .week:
            Color.clear.onAppear { go(afterPermission) }

        case .rating:
            Color.clear.onAppear { go(afterPermission) }

        case .health:
            if watchPaired {
                healthConsent
            } else {
                // A resume record from before the gate went, on a phone with
                // no Watch: nothing will be measured, so nothing to consent to.
                Color.clear.onAppear { go(.wall) }
            }

        // MARK: The walkthrough (see OnboardingWalkthrough.swift)

        // The tour is the whole tutorial now (Melvin, 2026-09-19: "I don't
        // want them forced to put their Watch on immediately, let them
        // explore the app on their own"). Continue on the last note finishes
        // onboarding and Home opens with nothing else asked of them; the
        // first session starts when they press the plus.
        case .tourHome:
            TourHomeScreen { finish() }

        // Cut 2026-09-19, one day after replacing the practice sit. The Step
        // case stays for resume records; anyone landing here is done.
        case .watchConnect:
            Color.clear.onAppear { finish() }

        case .breathe:
            Color.clear.onAppear { finish() }

        case .sessionResults:
            Color.clear.onAppear { finish() }

        case .paywall:
            // No paywall inside onboarding since 2026-09-15; it opens after
            // the first meditation from ContentView. A saved resume record
            // pointing here moves on to sign-in.
            Color.clear.onAppear { go(.signIn) }

        case .signIn:
            SignInScreen(onSignedIn: { credential in
                             signInCredential(credential)
                             afterSignIn()
                         },
                         onSkip: afterSignIn)

        case .profile:
            // Friends builds only: routing never reaches here when the flag
            // is off, and a resumed record from a Friends build lands safely.
            CreateProfileView(model: community,
                              suggested: answers.username,
                              nickname: answers.firstName) { handle in
                if let handle { answers.username = handle }
                afterAccount()
            }
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
        if answers.bodyCuriosity != nil { n += 1 }
        if answers.bodyProof != nil { n += 1 }
        if !answers.bodyTracking.isEmpty { n += 1 }
        if answers.hasWatch != nil { n += 1 }
        if answers.anchor != nil { n += 1 }
        if !answers.firstName.trimmingCharacters(in: .whitespaces).isEmpty { n += 1 }
        if answers.referral != nil { n += 1 }
        return n
    }

    // MARK: - Navigation

    private func go(_ requested: Step) {
        // Someone who already pays (a reinstall, a new phone) is never shown
        // an offer for what they own. Decided here, on the way IN, and not by
        // the paywall view watching `store.entitled`: that version also fired
        // when a purchase completed ON the paywall, advancing twice.
        let next: Step = (requested == .paywall && store.entitled) ? .signIn : requested
        guard next != step else { return }
        if !step.onlyPassesThrough { history.append(step) }
        // One line covers the whole 26-screen funnel: the step being LEFT is
        // the one that was completed.
        Analytics.track(.onboardingStep(id: String(describing: step)))
        show(next, motion: .forward)
    }

    /// Changes the screen with the given motion.
    ///
    /// **When the motion changes, the outgoing screen has to be drawn with
    /// the new transition BEFORE it is removed**, or it leaves the way the
    /// previous change did: SwiftUI takes a removal transition from the view
    /// as it was last rendered. So a change of direction sets `motion`, lets
    /// that render happen, and moves on the next turn of the run loop.
    private func show(_ target: Step, motion wanted: Motion) {
        let apply = {
            // Within one screen (I'm ready starting the breaths) nothing
            // animates: the words change and Otto breathes, that is all.
            if Self.identity(of: target) == screenIdentity {
                step = target
            } else {
                withAnimation { step = target }
            }
            saveProgress()
        }
        if motion != wanted {
            motion = wanted
            DispatchQueue.main.async(execute: apply)
        } else {
            apply()
        }
    }

    // MARK: - Resume

    /// Screens whose content died with the app: the live practice session
    /// and the results it produced. They reopen on the Watch connect screen
    /// that leads into them.
    private static let unresumable: Set<Step> = [.breathe, .sessionResults]

    private func saveProgress() {
        OnboardingResume(step: step.rawValue,
                           history: history.map(\.rawValue),
                           answers: answers,
                           plan: plan.rawValue,
                           waitlistEmail: waitlistEmail,
                           planRating: planRating,
                           reminderAllowed: reminderAllowed).save()
    }

    /// Reopens where they left off. Runs once, on the first appearance of a
    /// fresh OnboardingView; a finished onboarding cleared the record.
    private func resumeIfSaved() {
        guard !resumed, let saved = OnboardingResume.load() else { return }
        resumed = true
        let point = saved.resumePoint(unresumable: Set(Self.unresumable.map(\.rawValue)),
                                      fallback: Step.tourHome.rawValue)
        guard var target = Step(rawValue: point.step), target != .relief else { return }
        if target == .paywall, store.entitled { target = .signIn }
        answers = saved.answers
        history = point.history.compactMap(Step.init(rawValue:))
        plan = SubscriptionPlan(rawValue: saved.plan) ?? .monthly
        waitlistEmail = saved.waitlistEmail
        planRating = saved.planRating
        reminderAllowed = saved.reminderAllowed
        step = target
        Analytics.track(.onboardingResumed(id: String(describing: target)))
    }

    /// Belt and suspenders for the interview's branching (Melvin, 2026-08-29:
    /// he selected "first time meditating" and was still shown "what made you
    /// stop?" on an earlier build). The model decides who is asked what and is
    /// exhaustively tested, but routing has more roads into a screen than
    /// `nextAfter`: back navigation followed by a changed answer, a resumed
    /// flow, a future edit. So every persona-gated question also validates its
    /// own premise on arrival and silently skips itself when the answers
    /// contradict it. Skips bypass `go()` on purpose: no history entry (or the
    /// back button would bounce), no analytics step event for a screen never
    /// seen.
    @ViewBuilder
    private func guarded<V: View>(_ step: Step, @ViewBuilder screen: () -> V) -> some View {
        if let interview = Self.interviewPairs.first(where: { $0.0 == step })?.1,
           !answers.interview.contains(interview) {
            Color.clear.onAppear {
                // NOT nextAfter: that helper assumes its argument is in the
                // interview, and for a contradicted step it drops the whole
                // list and lands on .calculating, skipping every remaining
                // question including the Watch gate (caught in verification,
                // 2026-08-29). Walk the canonical order instead: the first
                // question this person IS asked at or after this position.
                let canonical = Self.interviewPairs.map(\.1)
                let here = canonical.firstIndex(of: interview) ?? 0
                let next = answers.interview.first {
                    (canonical.firstIndex(of: $0) ?? .max) > here
                }
                let target = next.flatMap { q in
                    Self.interviewPairs.first { $0.1 == q }?.0
                } ?? .calculating
                withAnimation { self.step = target }
            }
        } else {
            screen()
        }
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        show(previous, motion: .back)
    }

    // MARK: - Side effects

    /// True only if the user granted the OS dialog — declining there declines
    /// the reminder too, whatever button brought the dialog up.
    private func requestNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Records the Apple credential. Finishing happens in `afterSignIn`,
    /// which may first route through Create your profile.
    private func signInCredential(_ credential: ASAuthorizationAppleIDCredential) {
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")
        if answers.firstName.trimmingCharacters(in: .whitespaces).isEmpty, !name.isEmpty {
            answers.firstName = credential.fullName?.givenName ?? name
        }
        _ = SessionStore.signIn(appleUserID: credential.user,
                                email: credential.email,
                                displayName: name.isEmpty ? typedName : name,
                                in: context)
    }

    /// Friends builds end on Create your profile; everything else finishes.
    private func afterSignIn() {
        if FeatureFlags.friends { go(.profile) } else { afterAccount() }
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
        if let handle = Username.normalize(answers.username),
           (user.username ?? "").isEmpty || FeatureFlags.friends {
            // In Friends builds the handle was just reserved on Create your
            // profile, so it replaces any older cosmetic one.
            user.username = handle
        }
        // The no-Watch waitlist. The address lands on the local user row (the
        // product-emails opt-in Settings can undo) AND, since 2026-09-14, is
        // sent to the "808 no watch waitlist" sheet. Before that it stayed on
        // the phone only, so the screen's "we'll write to you" could never
        // happen. `WaitlistClient` never blocks this path and retries offline
        // signups on the next launch.
        let joined = waitlistEmail.contains("@") && waitlistEmail.contains(".")
        if joined {
            if (user.email ?? "").isEmpty { user.email = waitlistEmail }
            user.marketingOptIn = true
            WaitlistClient.submit(waitlistEmail)
        }
        Analytics.track(.onboardingCompleted)
        OnboardingResume.clear()
        if let prefs = preferences.first(where: { $0.userID == user.id }) ?? preferences.first {
            prefs.onboardingComplete = true
            // The time is stored either way: it is what they picked (or the
            // 8 AM default) and what Settings offers if they enable reminders
            // later. Whether the reminder is ON is the permission screen's
            // answer, never the time's: picking a time of day is not consent
            // to be notified at it.
            let time = answers.reminderTime
                ?? Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())
            prefs.reminderTime = time
            prefs.remindersEnabled = reminderAllowed
            NotificationScheduler.apply(enabled: reminderAllowed, at: time)
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
