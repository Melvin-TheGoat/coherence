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
///
/// **One shot per screen.** During the dwell the Continue button is still live,
/// so tapping an option and then Continue fired `onContinue` twice and skipped
/// a screen. `AdvanceGate` makes the second call a no-op.
@MainActor
final class AdvanceGate: ObservableObject {
    private var fired = false

    func advance(_ action: @escaping () -> Void) {
        guard !fired else { return }
        fired = true
        Task {
            try? await Task.sleep(for: OnboardingFlowTiming.selectionDwell)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// Continue tapped directly, with no selection dwell to wait out.
    func now(_ action: @escaping () -> Void) {
        guard !fired else { return }
        fired = true
        action()
    }
}

// MARK: - 1 · Relief

struct ReliefScreen: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // The first thing anyone ever sees of 808. Centred mark over one
            // sentence reads as a title card rather than a form, and the mark
            // is the real LogoMark geometry so it matches the icon exactly.
            VStack(spacing: 9) {
                LogoMark()
                    .frame(width: 68, height: 68)
                Text("808")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(3.3)
                    .foregroundStyle(AppColor.accentGoldText)
            }
            .padding(.bottom, 34)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            Text("You're not\nbad at meditation.")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.7).delay(0.35), value: appeared)

            Text("You just never got told whether it was working.")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.7).delay(0.75), value: appeared)

            Spacer()

            // "Show me my number" promised a number this screen hasn't earned:
            // the first real score is a whole session away. An invitation also
            // suits a page whose job is taking blame off.
            OnboardingCTA(title: "Let's find out", action: onContinue)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(1.25), value: appeared)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No ambient wave: this is a title card, and the space around the mark
        // is what makes it read as one.
        .onboardingGround(.relief, ambient: false)
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { appeared = true } }
    }
}

// MARK: - 2 · Regulate

/// A three-second breath before any personal question. No haptics here —
/// silence is the point, and it's the only onboarding in the category that
/// opens by actually doing the thing it sells.
struct BreathScreen: View {
    let onContinue: () -> Void

    /// A real breath has two halves, and the copy has to track the orb rather
    /// than run ahead of it. The first build set the phase in `onAppear`, so
    /// the label flipped to "and out" instantly while the orb was still
    /// growing: "Breathe in" was never once on screen and no exhale happened.
    /// `.ready` exists so the very first frame is already small AND already
    /// says "Breathe in". Starting at `.exhale` would flash "and out" for a
    /// frame before the inhale began, which is the same bug in miniature.
    private enum Breath { case ready, inhale, exhale, settled }
    @State private var breath: Breath = .ready
    @State private var canContinue = false

    /// The label is state, faded by hand, NOT derived from `breath` and
    /// cross-dissolved.
    ///
    /// Both earlier attempts let two strings share the screen. `.id` plus
    /// `.transition` rendered them as two views at once ("Breatheout"), and
    /// `.contentTransition(.opacity)` cross-dissolves, which means the glyphs
    /// of both are on screen together for the length of the fade ("aGood.t").
    /// The only way two strings can never overlap is if the first one is gone
    /// before the second arrives, so: fade to nothing, swap, fade back.
    @State private var labelText = "Breathe in"
    @State private var labelOpacity: Double = 0

    /// The intro. The line arrives first and alone, sits still for two
    /// seconds, then hands over to the orb.
    ///
    /// It used to open large and shrink into its slot, deriving the peak scale
    /// from measured widths because `scaleEffect` neither wraps nor truncates.
    /// All of that is gone: Melvin's call is that the line simply holds its
    /// size and position, and the pause alone does the work of letting someone
    /// read it before anything starts moving.
    @State private var titleOpacity: Double = 0
    @State private var orbOpacity: Double = 0

    /// The screen's own horizontal inset.
    private static let hPadding: CGFloat = 24

    private static let halfBreath: TimeInterval = 3
    private static let labelFade: TimeInterval = 0.25

    private var scale: CGFloat {
        switch breath {
        case .ready:   return 0.55
        case .inhale:  return 1.0
        case .exhale:  return 0.55
        case .settled: return 0.62
        }
    }

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
            .scaleEffect(scale)
            .opacity(orbOpacity)

            Text(labelText)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 36)
                .opacity(labelOpacity)

            Text("Before we ask you anything.")
                .font(OnboardingType.sub)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 8)
                .opacity(titleOpacity)

            Spacer()

            OnboardingCTA(title: "I'm here", enabled: canContinue, action: onContinue)
                .opacity(canContinue ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: canContinue)
        }
        .padding(.horizontal, Self.hPadding)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Emptiness is this screen's whole point. A drifting line behind the
        // orb would compete with the one thing the user is meant to follow.
        .onboardingGround(.relief, ambient: false)
        .task { await breathe() }
    }

    /// One full breath, driven in sequence so the orb and the words can't
    /// disagree. No haptics anywhere in here: silence is the point of the
    /// screen, and this is the only place in onboarding with none.
    private func breathe() async {
        await intro()
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: Self.halfBreath)) { breath = .inhale }
        try? await Task.sleep(for: .seconds(Self.halfBreath))
        guard !Task.isCancelled else { return }

        // The label swap runs inside the exhale rather than before it, so the
        // orb's rhythm stays exactly one breath either way.
        withAnimation(.easeInOut(duration: Self.halfBreath)) { breath = .exhale }
        await swapLabel(to: "and out")
        try? await Task.sleep(for: .seconds(Self.halfBreath - Self.labelFade * 2))
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: 0.8)) { breath = .settled }
        await swapLabel(to: "Good.")
        guard !Task.isCancelled else { return }
        withAnimation { canContinue = true }
    }

    /// Line, pause, orb, breath.
    ///
    /// The two-second hold is the whole intro now. It is there so the line is
    /// read before anything moves, and so the inhale reads as something
    /// starting rather than something already underway.
    ///
    /// Every sleep is followed by a cancellation check. A cancelled
    /// `Task.sleep` throws, `try?` swallows it, and the next line runs
    /// immediately: without the guards, backing out of this screen fires the
    /// whole sequence at once.
    private func intro() async {
        withAnimation(.easeOut(duration: 0.5)) { titleOpacity = 1 }
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.4)) {
            orbOpacity = 1
            labelOpacity = 1
        }
        try? await Task.sleep(for: .seconds(0.5))
    }

    /// Out, swap, in. Never both.
    private func swapLabel(to next: String) async {
        guard next != labelText else { return }
        withAnimation(.easeOut(duration: Self.labelFade)) { labelOpacity = 0 }
        try? await Task.sleep(for: .seconds(Self.labelFade))
        guard !Task.isCancelled else { return }
        labelText = next
        withAnimation(.easeIn(duration: Self.labelFade)) { labelOpacity = 1 }
        try? await Task.sleep(for: .seconds(Self.labelFade))
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
    @StateObject private var gate = AdvanceGate()
    @Binding var frequency: CurrentFrequency?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "How often do you\nmeditate right now?",
                         subtitle: "Honestly. This is the number we're going to move.",
                         ctaEnabled: frequency != nil,
                         autoAdvances: true,
                         onContinue: { gate.now(onContinue) }) {
            VStack(spacing: 10) {
                ForEach(CurrentFrequency.allCases) { f in
                    OnboardingOption(label: f.label, icon: f.icon,
                                     selected: frequency == f) { pick(f) }
                }
            }
            .sensoryFeedback(.selection, trigger: frequency)
        }
    }

    private func pick(_ f: CurrentFrequency) {
        frequency = f
        gate.advance(onContinue)
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
///
/// The waveform is driven by the slider, so the answer is drawn as well as
/// named: slow and even at Fine, fast and ragged at Fried. It replaced roughly
/// 420 pt of black, the emptiest screen in the flow.
///
/// **Teal to red, never gold.** Gold means a chosen or achieved thing, and it
/// is what the results screen spends on the one number this whole product is
/// selling. Spending it here on someone's stress level would both misuse the
/// grammar and blunt the payoff. Watching your own line go red is the better
/// argument anyway.
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

    /// Calm teal, through the relief section's amber, to the cost section's
    /// red. Three stops rather than two: interpolating teal straight to red in
    /// RGB passes through a washed-out pink, which looked like a mistake at
    /// exactly the midpoint most people leave the slider on.
    private var tint: Color {
        let t = min(max(stress, 0), 1)
        let calm  = (r: 0.45, g: 0.66, b: 0.63)   // AppColor.calmAccent
        // A warm orange, pushed deliberately off the gold. The obvious midpoint
        // sits so close to AccentGold that the wave and the Continue button
        // below it read as the same colour, which is both flat to look at and
        // the exact borrowing of gold this screen is avoiding.
        let amber = (r: 0.88, g: 0.50, b: 0.18)
        let hot   = (r: 0.78, g: 0.26, b: 0.22)   // .cost
        let (from, to, k) = t < 0.5 ? (calm, amber, t * 2) : (amber, hot, (t - 0.5) * 2)
        return Color(red:   from.r + (to.r - from.r) * k,
                     green: from.g + (to.g - from.g) * k,
                     blue:  from.b + (to.b - from.b) * k)
    }

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "How stressed have you\nbeen lately?",
                         onContinue: onContinue) {
            VStack(spacing: 22) {
                StressWave(level: stress, closed: true)
                    .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        StressWave(level: stress, closed: false)
                            .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    }
                    .frame(height: 150)
                    .animation(.easeOut(duration: 0.18), value: stress)

                Text(readout)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .animation(.easeOut(duration: 0.2), value: readout)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    Slider(value: $stress, in: 0...1)
                        .tint(tint)
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

/// The stress line. Frequency and amplitude both climb with `level`, and a
/// deterministic wobble is added on top that only becomes visible near the
/// upper end — so "Fried" is genuinely ragged while "Fine" is a clean sine.
///
/// The wobble is a fixed function of x rather than random, so the line stays
/// still while the user drags instead of shimmering under their thumb.
private struct StressWave: Shape {
    /// 0 calm, 1 fried.
    let level: Double
    /// Closed down to the baseline for the gradient fill; open for the stroke,
    /// so the fill's bottom edge never gets drawn as part of the line.
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        let t = min(max(level, 0), 1)
        let mid = rect.midY
        let cycles = 1.6 + t * 5.5
        let amp = rect.height * (0.08 + t * 0.23)
        let jag = t * t * rect.height * 0.16

        var p = Path()
        var x: CGFloat = 0
        while x <= rect.width {
            let phase = (x / rect.width) * cycles * 2 * .pi
            // Low frequency on purpose. A fast wobble renders as static, which
            // reads as a broken graphic; a slow one reads as an uneven beat,
            // which is what being wound up actually looks like.
            let wobble = jag * sin(x * 0.31) * cos(x * 0.11)
            let y = mid - sin(phase) * amp - wobble
            if x == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
            x += 2
        }
        if closed {
            p.addLine(to: CGPoint(x: rect.width, y: rect.maxY))
            p.addLine(to: CGPoint(x: 0, y: rect.maxY))
            p.closeSubpath()
        }
        return p
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
    @StateObject private var gate = AdvanceGate()
    @Binding var answer: AloneWithThoughts?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, progress: progress,
                         title: "Can you be alone\nwith your thoughts?",
                         subtitle: "Compared to a few years ago.",
                         ctaEnabled: answer != nil,
                         autoAdvances: true,
                         onContinue: { gate.now(onContinue) }) {
            VStack(spacing: 10) {
                ForEach(AloneWithThoughts.allCases) { a in
                    OnboardingOption(label: a.label, icon: a.icon,
                                     selected: answer == a) { pick(a) }
                }
            }
            .sensoryFeedback(.selection, trigger: answer)
        }
    }

    private func pick(_ a: AloneWithThoughts) {
        answer = a
        gate.advance(onContinue)
    }
}

// MARK: - The concrete cost

/// Sits immediately after the escalation question: that one asks whether it's
/// getting worse, this one asks for the proof in their own behaviour. The
/// subtitle names a real moment ("Standing in a line. Waiting for an elevator.")
/// so they recall something rather than estimate something.
///
/// It also aims at exactly what meditation treats — tolerance for being
/// unstimulated — which makes the product the answer to the question without
/// the question ever pitching.
struct DoingNothingScreen: View {
    @StateObject private var gate = AdvanceGate()
    @Binding var answer: DoingNothing?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, progress: progress,
                         title: "How long can you do\nnothing before you reach\nfor your phone?",
                         subtitle: "Standing in a line. Waiting for an elevator.",
                         ctaEnabled: answer != nil,
                         autoAdvances: true,
                         onContinue: { gate.now(onContinue) }) {
            VStack(spacing: 10) {
                ForEach(DoingNothing.allCases) { d in
                    OnboardingOption(label: d.label, icon: d.icon,
                                     selected: answer == d) { pick(d) }
                }
            }
            .sensoryFeedback(.selection, trigger: answer)
        }
    }

    private func pick(_ d: DoingNothing) {
        answer = d
        gate.advance(onContinue)
    }
}

// MARK: - 5 · Q3 The admission

/// Where the ground turns red. The heavier haptic is deliberate: this is the
/// screen where the user admits the pattern to themselves.
struct RestartScreen: View {
    @StateObject private var gate = AdvanceGate()
    @Binding var restarts: RestartCount?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, progress: progress,
                         title: "How many times have you\ntried to make meditation stick?",
                         subtitle: "No judgement. This is the single most common thing there is.",
                         ctaEnabled: restarts != nil,
                         autoAdvances: true,
                         onContinue: { gate.now(onContinue) }) {
            VStack(spacing: 10) {
                ForEach(RestartCount.allCases) { r in
                    OnboardingOption(label: r.label, icon: r.icon,
                                     selected: restarts == r) { pick(r) }
                }
            }
            .sensoryFeedback(.impact(flexibility: .rigid), trigger: restarts)
        }
    }

    private func pick(_ r: RestartCount) {
        restarts = r
        gate.advance(onContinue)
    }
}

// MARK: - How long it's been

/// Restarts gives the pattern a count; this gives it a length. Together they
/// say "this has been going on a long time and you've been losing to it" —
/// without us ever writing that sentence.
struct IntendedForScreen: View {
    @StateObject private var gate = AdvanceGate()
    @Binding var intended: IntendedFor?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, progress: progress,
                         title: "How long have you been\nmeaning to start?",
                         subtitle: "Not trying. Meaning to.",
                         ctaEnabled: intended != nil,
                         autoAdvances: true,
                         onContinue: { gate.now(onContinue) }) {
            VStack(spacing: 10) {
                ForEach(IntendedFor.allCases) { i in
                    OnboardingOption(label: i.label, icon: i.icon,
                                     selected: intended == i) { pick(i) }
                }
            }
            .sensoryFeedback(.selection, trigger: intended)
        }
    }

    private func pick(_ i: IntendedFor) {
        intended = i
        gate.advance(onContinue)
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
                    OnboardingOption(label: c.label, icon: c.icon,
                                     selected: causes.contains(c)) {
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
    @StateObject private var gate = AdvanceGate()
    @Binding var hasWatch: Bool?
    let progress: Double
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "Do you have an\nApple Watch?",
                         subtitle: "808 measures from the Watch. Without one there's nothing to measure, so we'd rather tell you now.",
                         ctaEnabled: hasWatch != nil,
                         // Single select, so it advances on the tap like the
                         // rest. A "no" lands on the waitlist without a warning
                         // label, which is fine: that screen explains itself in
                         // its first line and the chevron comes straight back.
                         autoAdvances: true,
                         onContinue: { gate.now { hasWatch == false ? onNo() : onYes() } }) {
            VStack(spacing: 22) {
                // Two options left over 400 pt of black on the one screen that
                // decides whether the product can work for this person at all.
                // Showing the instrument turns "yes" into "yes, I own that"
                // rather than a form field.
                VStack(spacing: 8) {
                    WatchIllustration()
                        .frame(width: 150, height: 190)
                    Text("Heart rate and stillness, read from the wrist.")
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    OnboardingOption(label: "Yes", icon: "applewatch",
                                     selected: hasWatch == true) { pick(true) }
                    OnboardingOption(label: "No, not yet", icon: "applewatch.slash",
                                     selected: hasWatch == false) { pick(false) }
                }
            }
            .sensoryFeedback(.selection, trigger: hasWatch)
        }
    }

    private func pick(_ yes: Bool) {
        hasWatch = yes
        gate.advance { yes ? onYes() : onNo() }
    }
}

/// A Watch with a pulse trace crossing its face, drawn rather than
/// screenshotted so it inherits the app's colours and needs no asset.
///
/// **The proportions are the real ones.** The first draft made the case 70 by
/// 132, nearly twice as tall as it is wide, which reads as a fitness band
/// rather than an Apple Watch. A 46 mm case is 46 by 39 mm, so the case is
/// about 1.2 tall per unit wide and the strap is roughly two thirds the case
/// width. Everything here is derived from `caseWidth` to keep that true.
///
/// The numbers on the face are illustrative. That's defensible here because it
/// reads unmistakably as a drawing; it would not be on any screen that reports
/// a reading. Teal for the trace: it's a body signal, not an achievement.
private struct WatchIllustration: View {
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let caseWidth: CGFloat = 96
    private var caseHeight: CGFloat { caseWidth * 1.18 }
    private var bandWidth: CGFloat { caseWidth * 0.62 }
    private var faceInset: CGFloat { 7 }

    var body: some View {
        ZStack {
            // Band
            VStack(spacing: 0) {
                bandSegment
                Spacer(minLength: 0)
                bandSegment
            }

            // Case. Opaque, or the band shows straight through it.
            RoundedRectangle(cornerRadius: caseWidth * 0.30, style: .continuous)
                .fill(Color.black)
                .overlay(RoundedRectangle(cornerRadius: caseWidth * 0.30, style: .continuous)
                    .stroke(AppColor.textSecondary.opacity(0.28), lineWidth: 1.5))
                .frame(width: caseWidth, height: caseHeight)

            // Digital crown
            Capsule()
                .fill(AppColor.textSecondary.opacity(0.32))
                .frame(width: 5, height: 22)
                .offset(x: caseWidth / 2 + 1, y: -caseHeight * 0.14)

            // Face
            RoundedRectangle(cornerRadius: caseWidth * 0.24, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .frame(width: caseWidth - faceInset * 2, height: caseHeight - faceInset * 2)
                .overlay {
                    VStack(spacing: 0) {
                        Text("62")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("BPM")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(AppColor.textSecondary)

                        // The trace is always fully drawn underneath, with a
                        // bright head sweeping across it like a monitor. An
                        // earlier version trimmed the only copy of the line,
                        // so for half of every cycle the face was empty and
                        // the illustration looked broken rather than alive.
                        ZStack {
                            PulseTrace()
                                .stroke(AppColor.calmAccent.opacity(0.3),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            PulseTrace()
                                .trim(from: 0, to: sweep ? 1 : 0)
                                .stroke(AppColor.calmAccent,
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                        .frame(height: 26)
                        .padding(.top, 7)

                        Text("STILL")
                            .font(.system(size: 8.5, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(AppColor.accentGoldText)
                            .padding(.top, 7)
                    }
                    .padding(.horizontal, 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: caseWidth * 0.24, style: .continuous))
        }
        .onAppear {
            guard !reduceMotion else { sweep = true; return }
            // No autoreverse: the head sweeps left to right and restarts, which
            // is how a monitor behaves. Reversing would draw it backwards.
            withAnimation(.linear(duration: 1.7).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
    }

    /// Rounded on all four corners: the inner ends tuck under the case, so only
    /// the outer ones are ever seen and both segments can share one shape.
    private var bandSegment: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(AppColor.textSecondary.opacity(0.14))
            .frame(width: bandWidth, height: 46)
    }
}

/// One heartbeat, in the shape everyone recognises.
private struct PulseTrace: Shape {
    func path(in rect: CGRect) -> Path {
        let mid = rect.midY
        let w = rect.width
        var p = Path()
        p.move(to: CGPoint(x: 0, y: mid))
        p.addLine(to: CGPoint(x: w * 0.26, y: mid))
        p.addLine(to: CGPoint(x: w * 0.34, y: mid - rect.height * 0.28))
        p.addLine(to: CGPoint(x: w * 0.44, y: mid + rect.height * 0.42))
        p.addLine(to: CGPoint(x: w * 0.54, y: mid - rect.height * 0.48))
        p.addLine(to: CGPoint(x: w * 0.64, y: mid + rect.height * 0.12))
        p.addLine(to: CGPoint(x: w * 0.72, y: mid))
        p.addLine(to: CGPoint(x: w, y: mid))
        return p
    }
}

// MARK: - 7b · No Watch → waitlist

/// The email is an OFFER, never a toll. An earlier version had no way past
/// this screen except typing a valid address (or backing up and claiming to
/// own a Watch), which is the same 5.1.1 data-minimization violation the name
/// screen had: personal information required to proceed. The decline action
/// names what it declines, per the scaffold's own rule.
struct WaitlistScreen: View {
    @Binding var email: String
    let onJoin: () -> Void
    let onDecline: () -> Void

    var body: some View {
        OnboardingScreen(section: .body,
                         title: "We'll tell you the day\nit works for you.",
                         subtitle: "We're not going to take your money for an app that can't do its one job. Leave your email and we'll write when there's a version that doesn't need a Watch.",
                         ctaTitle: "Join the waitlist",
                         ctaEnabled: email.contains("@") && email.contains("."),
                         skipTitle: "Continue without joining",
                         onSkip: onDecline,
                         onContinue: onJoin) {
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
    @StateObject private var gate = AdvanceGate()
    @Binding var anchor: Anchor?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "When will you\nactually meditate?",
                         subtitle: "Pick something you already do every day. Attaching it to an existing habit is the single biggest predictor of sticking with it.",
                         ctaEnabled: anchor != nil,
                         autoAdvances: true,
                         onContinue: { gate.now(onContinue) }) {
            VStack(spacing: 10) {
                ForEach(Anchor.allCases) { a in
                    OnboardingOption(label: a.label, icon: a.icon,
                                     selected: anchor == a) { pick(a) }
                }
            }
            .sensoryFeedback(.selection, trigger: anchor)
        }
    }

    private func pick(_ a: Anchor) {
        anchor = a
        gate.advance(onContinue)
    }
}

// MARK: - 9 · You

/// Both answers here are OPTIONAL, and that is a review requirement, not a
/// courtesy. Guideline 5.1.1 forbids requiring personal information the core
/// function doesn't need, and 808 measures a meditation identically whether or
/// not it knows what to call you. An earlier version gated Continue on a typed
/// name; that was the textbook data-minimization rejection. The field asks
/// "What should we call you?" rather than demanding a legal first name for the
/// same reason: we want a form of address, not an identity. Every downstream
/// screen already handles the empty case ("Your practice profile").
struct NameScreen: View {
    @StateObject private var gate = AdvanceGate()
    @Binding var firstName: String
    @Binding var ageBracket: String?
    let progress: Double
    let onContinue: () -> Void

    // Melvin asked for Under 18 / 18-21 / 21-25; those overlap at 21, so the
    // boundaries are closed here. Under 18 is deliberate and has App Review
    // consequences worth confirming (age rating, kids-category rules).
    private let brackets = ["Under 18", "18–20", "21–24", "25–34",
                            "35–44", "45–54", "55+"]

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "Last thing.",
                         subtitle: "So the app can talk to you like a person. Answer either, both, or neither.",
                         onContinue: { gate.now(onContinue) }) {
            VStack(alignment: .leading, spacing: 20) {
                TextField("What should we call you?", text: $firstName)
                    .textContentType(.nickname)
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
                        OnboardingOption(label: b, selected: ageBracket == b) { pick(b) }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: ageBracket)
        }
    }

    private func pick(_ bracket: String) {
        // Selects, never advances: with every answer optional, the only thing
        // that moves the screen forward is the Continue the user chooses.
        ageBracket = ageBracket == bracket ? nil : bracket
    }
}

// MARK: - Attribution (last interview question)

/// Dead last on purpose: it's the least interesting thing we ask, so a
/// drop-off here costs the least — and by now they've answered ten questions
/// and won't bail on the eleventh. Watch the "a friend told me" row; when it
/// climbs, word of mouth is working.
///
/// No longer skippable. "Somewhere else" is the honest out for anyone who
/// can't remember, which is what a skip was really being used for.
struct ReferralScreen: View {
    @StateObject private var gate = AdvanceGate()
    @Binding var referral: ReferralSource?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, progress: progress,
                         title: "One last thing.\nHow did you find us?",
                         subtitle: "It's the only way we know where to show up.",
                         ctaEnabled: referral != nil,
                         autoAdvances: true,
                         onContinue: { gate.now(onContinue) }) {
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
        gate.advance(onContinue)
    }
}

// MARK: - The regular practitioner's question

/// Shown only to someone who already meditates most weeks. The consistency
/// questions (restarts, causes, how long you've meant to start) all presume a
/// practice that isn't happening; this presumes one that is, and asks the only
/// thing 808 can actually fix for them.
///
/// DRAFT COPY — written to unblock the branching, not signed off.
struct BlindSpotScreen: View {
    @StateObject private var gate = AdvanceGate()
    @Binding var blindSpot: BlindSpot?
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, progress: progress,
                         title: "What can't you tell\nabout your practice?",
                         subtitle: "You already sit. This is the part nobody can see.",
                         ctaEnabled: blindSpot != nil,
                         autoAdvances: true,
                         onContinue: { gate.now(onContinue) }) {
            VStack(spacing: 10) {
                ForEach(BlindSpot.allCases) { b in
                    OnboardingOption(label: b.label, icon: b.icon,
                                     selected: blindSpot == b) { pick(b) }
                }
            }
            .sensoryFeedback(.impact(flexibility: .rigid), trigger: blindSpot)
        }
    }

    private func pick(_ b: BlindSpot) {
        blindSpot = b
        gate.advance(onContinue)
    }
}
