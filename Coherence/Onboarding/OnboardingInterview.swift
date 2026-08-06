import SwiftUI

/// Screens 1–9: relief, a breath, and the six questions.
///
/// Copy rule throughout: we reflect, we never diagnose. The reference flow we
/// modelled on opens with "we've got some news to break to you" — that works on
/// someone who typed "quit porn" into the App Store. Meditation buyers arrive
/// aspirational, so ours opens by taking blame off.

/// Holds the chosen answer on screen briefly, then moves on. Without the pause
/// the tick never registers and the flow feels like it jumped; with it, the
/// selection is acknowledged and the advance reads as a response.
@MainActor
func advance(_ action: @escaping () -> Void) {
    Task {
        try? await Task.sleep(for: OnboardingFlowTiming.selectionDwell)
        guard !Task.isCancelled else { return }
        action()
    }
}

// MARK: - 1 · Relief

struct ReliefScreen: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Text("You're not\nbad at meditation.")
                .font(OnboardingType.headline)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            Text("You just never got told whether it was working.")
                .font(.system(size: 18))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.7).delay(0.5), value: appeared)

            Spacer()

            OnboardingCTA(title: "Show me my number", action: onContinue)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.1), value: appeared)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onboardingGround(.relief)
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { appeared = true } }
    }
}

// MARK: - 2 · Regulate

/// A three-second breath before any personal question. No haptics here —
/// silence is the point, and it's the only onboarding in the category that
/// opens by actually doing the thing it sells.
struct BreathScreen: View {
    let onContinue: () -> Void
    @State private var inhaled = false
    @State private var canContinue = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [AppColor.calmAccent.opacity(0.55),
                                                  AppColor.calmAccent.opacity(0.05)],
                                         center: .center, startRadius: 6, endRadius: 130))
                    .frame(width: 230, height: 230)
                Circle()
                    .stroke(AppColor.calmAccent.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 230, height: 230)
            }
            .scaleEffect(inhaled ? 1.0 : 0.55)
            .animation(.easeInOut(duration: 3.5), value: inhaled)

            Text(inhaled ? "and out" : "Breathe in")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 36)
                .animation(.easeInOut(duration: 0.5), value: inhaled)

            Text("Before we ask you anything.")
                .font(OnboardingType.sub)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 8)

            Spacer()

            OnboardingCTA(title: "I'm here", enabled: canContinue, action: onContinue)
                .opacity(canContinue ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: canContinue)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.relief)
        .onAppear {
            withAnimation { inhaled = true }
            Task {
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled else { return }
                withAnimation { canContinue = true }
            }
        }
    }
}

// MARK: - Q0 · The baseline

/// The first question, and the one everything later is measured against.
/// Their version asks how often you use porn; the job is identical — plant a
/// BEFORE so the app's work has something to move. The two answers most people
/// pick ("I've tried, it never stuck", "a few times a month") ARE the
/// inconsistency the product exists to fix, so they convict themselves gently
/// and nothing has to be asserted at them later.
struct BaselineScreen: View {
    @Binding var frequency: CurrentFrequency?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "How often do you\nmeditate right now?",
                         subtitle: "Honestly. This is the number we're going to move.",
                         ctaEnabled: frequency != nil,
                         autoAdvances: true,
                         onContinue: onContinue) {
            VStack(spacing: 10) {
                ForEach(CurrentFrequency.allCases) { f in
                    OnboardingOption(label: f.label, selected: frequency == f) { pick(f) }
                }
            }
            .sensoryFeedback(.selection, trigger: frequency)
        }
    }

    private func pick(_ f: CurrentFrequency) {
        frequency = f
        advance(onContinue)
    }
}

// MARK: - 3 · Q1 Why (multi-select)

struct MotivationScreen: View {
    @Binding var selected: Set<Motivation>
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "What are you hoping\nmeditation gives you?",
                         subtitle: "Pick as many as are true.",
                         ctaEnabled: !selected.isEmpty,
                         onContinue: onContinue) {
            VStack(spacing: 10) {
                ForEach(Motivation.allCases) { m in
                    OnboardingOption(label: m.label, icon: m.icon,
                                     selected: selected.contains(m)) {
                        if selected.contains(m) { selected.remove(m) } else { selected.insert(m) }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selected)
        }
    }
}

// MARK: - 4 · Q2 Stress (slider)

/// The input type changes here on purpose: six tap-lists in a row is where
/// drop-off lives.
struct StressScreen: View {
    @Binding var stress: Double
    let progress: Double
    let onContinue: () -> Void

    private var notch: Int { Int((stress * 4).rounded()) }

    private var readout: String {
        switch notch {
        case 0: return "Fine"
        case 1: return "A bit wound up"
        case 2: return "Carrying a lot"
        case 3: return "Close to the edge"
        default: return "Fried"
        }
    }

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "How stressed have you\nbeen lately?",
                         onContinue: onContinue) {
            VStack(spacing: 26) {
                Text(readout)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accentGold)
                    .animation(.easeOut(duration: 0.2), value: readout)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                VStack(spacing: 8) {
                    Slider(value: $stress, in: 0...1)
                        .tint(AppColor.accentGold)
                    HStack {
                        Text("Fine")
                        Spacer()
                        Text("Fried")
                    }
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                }
            }
            .sensoryFeedback(.selection, trigger: notch)
        }
    }
}

// MARK: - The escalation

/// Turns a static problem into a worsening one, which is where urgency comes
/// from — the only question in the reference flow that creates any.
///
/// The word **"still"** carries it: it presupposes you once could, so the
/// deterioration is inside the question rather than asserted at the user. That
/// distinction is the point. We may ask whether their attention has slipped; we
/// may never tell them it has, because that's a claim about their brain we
/// cannot measure. Same line the theta copy respects.
///
/// The ground turns red here — this is now the first pain question.
struct AloneWithThoughtsScreen: View {
    @Binding var answer: AloneWithThoughts?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, progress: progress,
                         title: "Can you still be alone\nwith your own thoughts?",
                         subtitle: "Compared with a few years ago.",
                         ctaEnabled: answer != nil,
                         autoAdvances: true,
                         onContinue: onContinue) {
            VStack(spacing: 10) {
                ForEach(AloneWithThoughts.allCases) { a in
                    OnboardingOption(label: a.label, selected: answer == a) { pick(a) }
                }
            }
            .sensoryFeedback(.selection, trigger: answer)
        }
    }

    private func pick(_ a: AloneWithThoughts) {
        answer = a
        advance(onContinue)
    }
}

// MARK: - The concrete cost

/// Sits immediately after the escalation question: that one asks whether it's
/// getting worse, this one asks for the proof in their own behaviour. The
/// subtitle names a real moment ("Standing in a queue. Waiting for a lift.")
/// so they recall something rather than estimate something.
///
/// It also aims at exactly what meditation treats — tolerance for being
/// unstimulated — which makes the product the answer to the question without
/// the question ever pitching.
struct DoingNothingScreen: View {
    @Binding var answer: DoingNothing?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, progress: progress,
                         title: "How long can you do\nnothing before you reach\nfor your phone?",
                         subtitle: "Standing in a queue. Waiting for a lift.",
                         ctaEnabled: answer != nil,
                         autoAdvances: true,
                         onContinue: onContinue) {
            VStack(spacing: 10) {
                ForEach(DoingNothing.allCases) { d in
                    OnboardingOption(label: d.label, selected: answer == d) { pick(d) }
                }
            }
            .sensoryFeedback(.selection, trigger: answer)
        }
    }

    private func pick(_ d: DoingNothing) {
        answer = d
        advance(onContinue)
    }
}

// MARK: - 5 · Q3 The admission

/// Where the ground turns red. The heavier haptic is deliberate: this is the
/// screen where the user admits the pattern to themselves.
struct RestartScreen: View {
    @Binding var restarts: RestartCount?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, progress: progress,
                         title: "How many times have you\ntried to make meditation stick?",
                         subtitle: "No judgement. This is the single most common thing there is.",
                         ctaEnabled: restarts != nil,
                         autoAdvances: true,
                         onContinue: onContinue) {
            VStack(spacing: 10) {
                ForEach(RestartCount.allCases) { r in
                    OnboardingOption(label: r.label, selected: restarts == r) { pick(r) }
                }
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: restarts)
        }
    }

    private func pick(_ r: RestartCount) {
        restarts = r
        advance(onContinue)
    }
}

// MARK: - How long it's been

/// Restarts gives the pattern a count; this gives it a length. Together they
/// say "this has been going on a long time and you've been losing to it" —
/// without us ever writing that sentence.
struct IntendedForScreen: View {
    @Binding var intended: IntendedFor?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, progress: progress,
                         title: "How long have you been\nmeaning to start?",
                         subtitle: "Not trying. Meaning to.",
                         ctaEnabled: intended != nil,
                         autoAdvances: true,
                         onContinue: onContinue) {
            VStack(spacing: 10) {
                ForEach(IntendedFor.allCases) { i in
                    OnboardingOption(label: i.label, selected: intended == i) { pick(i) }
                }
            }
            .sensoryFeedback(.selection, trigger: intended)
        }
    }

    private func pick(_ i: IntendedFor) {
        intended = i
        advance(onContinue)
    }
}

// MARK: - 6 · Q4 The cause

struct CauseScreen: View {
    @Binding var causes: Set<DropoutCause>
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, progress: progress,
                         title: "What made you stop\nmeditating?",
                         subtitle: "Pick whatever rings true.",
                         ctaEnabled: !causes.isEmpty,
                         onContinue: onContinue) {
            VStack(spacing: 10) {
                ForEach(DropoutCause.allCases) { c in
                    OnboardingOption(label: c.label, selected: causes.contains(c)) {
                        if causes.contains(c) { causes.remove(c) } else { causes.insert(c) }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: causes)
        }
    }
}

// MARK: - 7 · Q5 The gate

/// Plain language, no spin. A "no" here goes to the waitlist, never to a
/// paywall — we will not take money for an app that can't do its one job.
struct WatchGateScreen: View {
    @Binding var hasWatch: Bool?
    let progress: Double
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "Do you have an\nApple Watch?",
                         subtitle: "808 measures from the Watch. Without one there's nothing to measure, so we'd rather tell you now.",
                         ctaTitle: hasWatch == false ? "Join the waitlist" : "Continue",
                         ctaEnabled: hasWatch != nil,
                         onContinue: { hasWatch == false ? onNo() : onYes() }) {
            VStack(spacing: 10) {
                OnboardingOption(label: "Yes", icon: "applewatch",
                                 selected: hasWatch == true) { hasWatch = true }
                OnboardingOption(label: "No, not yet", icon: "applewatch.slash",
                                 selected: hasWatch == false) { hasWatch = false }
            }
            .sensoryFeedback(.selection, trigger: hasWatch)
        }
    }
}

// MARK: - 7b · No Watch → waitlist

struct WaitlistScreen: View {
    @Binding var email: String
    let onSubmit: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScreen(section: .body,
                         title: "We'll tell you the day\nit works for you.",
                         subtitle: "We're not going to take your money for an app that can't do its one job. Leave your email and we'll write when there's a version that doesn't need a Watch.",
                         ctaTitle: "Join the waitlist",
                         ctaEnabled: email.contains("@") && email.contains("."),
                         onSkip: onBack,
                         onContinue: onSubmit) {
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(OnboardingType.option)
                .foregroundStyle(AppColor.textPrimary)
                .padding(16)
                .background(AppColor.backgroundSecondary.opacity(0.8),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - 8 · Q6 The anchor

/// Anchoring practice to an existing daily routine measurably lowered
/// abandonment (Mindfulness, 2023). This answer also becomes the reminder time,
/// so we never ask twice for the same fact.
struct AnchorScreen: View {
    @Binding var anchor: Anchor?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "When will you\nactually meditate?",
                         subtitle: "Pick something you already do every day. Attaching it to an existing habit is the single biggest predictor of sticking with it.",
                         ctaEnabled: anchor != nil,
                         autoAdvances: true,
                         onContinue: onContinue) {
            VStack(spacing: 10) {
                ForEach(Anchor.allCases) { a in
                    OnboardingOption(label: a.label, selected: anchor == a) { pick(a) }
                }
            }
            .sensoryFeedback(.selection, trigger: anchor)
        }
    }

    private func pick(_ a: Anchor) {
        anchor = a
        advance(onContinue)
    }
}

// MARK: - 9 · You

struct NameScreen: View {
    @Binding var firstName: String
    @Binding var ageBracket: String?
    let progress: Double
    let onContinue: () -> Void

    private let brackets = ["Under 25", "25–34", "35–44", "45–54", "55+"]

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "Last thing.",
                         subtitle: "So the app can talk to you like a person.",
                         ctaEnabled: !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
                         onContinue: onContinue) {
            VStack(alignment: .leading, spacing: 20) {
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                    .font(OnboardingType.option)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(16)
                    .background(AppColor.backgroundSecondary.opacity(0.8),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Age")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                    ForEach(brackets, id: \.self) { b in
                        OnboardingOption(label: b, selected: ageBracket == b) { ageBracket = b }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: ageBracket)
        }
    }
}

// MARK: - Attribution (last interview question)

/// Dead last on purpose: it's the least interesting thing we ask, so a
/// drop-off here costs the least — and by now they've answered ten questions
/// and won't bail on the eleventh. Watch the "a friend told me" row; when it
/// climbs, word of mouth is working.
struct ReferralScreen: View {
    @Binding var referral: ReferralSource?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "One last thing.\nHow did you find us?",
                         subtitle: "It's the only way we know where to show up.",
                         ctaEnabled: referral != nil,
                         autoAdvances: true,
                         onSkip: onContinue,
                         onContinue: onContinue) {
            VStack(spacing: 9) {
                ForEach(ReferralSource.allCases) { r in
                    OnboardingOption(label: r.label, icon: r.icon,
                                     selected: referral == r) { pick(r) }
                }
            }
            .sensoryFeedback(.selection, trigger: referral)
        }
    }

    private func pick(_ r: ReferralSource) {
        referral = r
        advance(onContinue)
    }
}
