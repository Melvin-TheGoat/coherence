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
    // No sign-in link on this screen, deliberately (Aziz, 2026-09-14).
    // It jumped straight to Sign in, skipping every screen including the
    // paywall, and PostHog showed new people using it that way. Sign-in now
    // exists only at the end of onboarding. A returning user loses nothing:
    // their sessions and onboarding flag come back through iCloud (which
    // skips onboarding by itself once the import lands), and a subscription
    // rides the Apple ID, restored on the paywall. Quittr and Cal AI make the
    // same choice: nothing reaches the app without passing the offer.
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // The first thing anyone ever sees of 808, and it is now a face
            // rather than a glyph: the same crop as the app icon they just
            // tapped, so the app introduces itself as the thing on their home
            // screen.
            VStack(spacing: 9) {
                OttoMark(size: 78, pose: .head)
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
                    .fill(RadialGradient(colors: [Color.onboardingSage.opacity(0.55),
                                                  Color.onboardingSage.opacity(0.05)],
                                         center: .center, startRadius: 6, endRadius: 130))
                    .frame(width: 230, height: 230)
                Circle()
                    .stroke(Color.onboardingSage.opacity(0.45), lineWidth: 1.5)
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
        .onboardingGround(.relief)
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
    /// One second on the line, then "Breathe in" arrives and holds for half a
    /// second before the orb moves (Melvin, 2026-08-25: the old two-second
    /// hold made the instruction feel late, and the half-second beat between
    /// the words and the expansion is what makes the inhale feel cued rather
    /// than already underway).
    ///
    /// Every sleep is followed by a cancellation check. A cancelled
    /// `Task.sleep` throws, `try?` swallows it, and the next line runs
    /// immediately: without the guards, backing out of this screen fires the
    /// whole sequence at once.
    private func intro() async {
        withAnimation(.easeOut(duration: 0.5)) { titleOpacity = 1 }
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        // Staggered on purpose: "Breathe in" speaks first, and the orb
        // arrives a beat later as the thing the words were announcing.
        withAnimation(.easeOut(duration: 0.35)) { labelOpacity = 1 }
        try? await Task.sleep(for: .seconds(0.65))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.4)) { orbOpacity = 1 }
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
/// "How often do you meditate right now?" (Aziz, 2026-09-25, Brainrot's
/// screen-time slider). Five stops from "Not yet" to "Every day", the big
/// readout, a week of seven flames that light as it slides toward every day
/// (the flame is the streak's icon), and a line under it per stop. Saves into
/// `currentFrequency`, the old list question's answer, so the persona it
/// feeds is unchanged. Starts in the middle like Brainrot's; a tick per stop.
/// Otto sits on his cushion below (the valley's, dropped as on "Did you
/// know?"); a looping clip of him thinking replaces him when it exists.
struct FrequencyScreen: View {
    @Binding var frequency: CurrentFrequency?
    let count: InterviewCount
    let onContinue: () -> Void

    @Environment(\.onboardingBack) private var back

    private var stops: [CurrentFrequency] { CurrentFrequency.allCases }
    private var current: CurrentFrequency { frequency ?? .fewTimesMonth }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let back { OnboardingBackButton(action: back) }
                OnboardingProgress(from: Double(count.index - 1) / Double(max(count.total, 1)),
                                   to: Double(count.index) / Double(max(count.total, 1)))
            }
            .frame(height: 40)

            Text("How often do you meditate right now?")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text("No judgment. It's just where we start.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textPrimary.opacity(0.7))
                .padding(.top, 6)

            Text(current.sliderLabel)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: current)
                .padding(.top, 16)

            WeekFlames(lit: current.flames.lit, faint: current.flames.faint)
                .padding(.top, 10)

            StopSlider(count: stops.count,
                       index: Binding(get: { stops.firstIndex(of: current) ?? 2 },
                                      set: { frequency = stops[$0] }))
                .padding(.top, 14)
            HStack {
                Text("Not yet")
                Spacer()
                Text("Every day")
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(AppColor.textPrimary.opacity(0.75))
            .padding(.top, 4)

            Text(current.sliderLine)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.skyDeep)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: current)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue") {
                if frequency == nil { frequency = current }
                onContinue()
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 10)
        }
        .sensoryFeedback(.selection, trigger: current)
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            let i = stops.firstIndex(of: current) ?? 2
            let j = direction == .increment ? min(stops.count - 1, i + 1) : max(0, i - 1)
            frequency = stops[j]
        }
    }
}

/// A week of seven flames: lit ones in the streak's blush, the rest hollow.
/// Each one that lights pops.
private struct WeekFlames: View {
    let lit: Int
    let faint: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<7, id: \.self) { i in
                let on = i < lit
                Image(systemName: on ? "flame.fill" : "flame")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(on ? AppColor.streakBlushText.opacity(faint ? 0.45 : 1)
                                        : AppColor.textPrimary.opacity(0.25))
                    .scaleEffect(on ? 1 : 0.85)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5).delay(Double(i) * 0.03), value: on)
            }
        }
        // On white: over the sky, blush and hollow flames both vanished.
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.white)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2))
        .accessibilityHidden(true)
    }
}

/// A slider that snaps to `count` stops, green like onboarding's buttons,
/// with Otto's face as the handle (as on See for yourself).
private struct StopSlider: View {
    let count: Int
    @Binding var index: Int
    private static let knob: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width - Self.knob
            let x = travel * CGFloat(index) / CGFloat(max(count - 1, 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                    .frame(height: 14)
                Capsule()
                    .fill(OnboardingGreen.fill)
                    .frame(width: x + Self.knob / 2, height: 14)
                Image("OttoHead")
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .frame(width: Self.knob, height: Self.knob)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                    .offset(x: x)
            }
            .frame(height: Self.knob)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: index)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let t = (value.location.x - Self.knob / 2) / max(1, travel)
                index = Int((min(max(t, 0), 1) * CGFloat(count - 1)).rounded())
            })
        }
        .frame(height: Self.knob)
    }
}

// MARK: - 3 · Q1 The goal, Q2 what gets in the way

/// Brainrot's question screen in the valley (Aziz, 2026-09-23): the title in
/// the sky, the answers on white plates, **as many as are true** and a
/// Continue button, greyed until one is picked (Aziz: not tap to advance).
/// The writing Otto sits top right, the same Otto who was writing on his
/// cushion on "Let's personalize": `OnboardingView` draws him in the fixed
/// layer and glides him into the corner (`SeatedClipLayer(inCorner:)`), so
/// this screen leaves room for him and draws nothing there itself.
struct CornerQuestionScreen<Option: Identifiable & Hashable>: View {
    let title: String
    let options: [Option]
    /// One answer only: tapping another swaps it (still moved on with
    /// Continue). Square boxes when several may be picked, none when one.
    var single: Bool = false
    let label: (Option) -> String
    /// Nil draws no icon (the age question: seven identical ones was noise).
    let icon: (Option) -> String?
    @Binding var selected: Set<Option>
    let count: InterviewCount
    let onContinue: () -> Void

    @Environment(\.onboardingBack) private var back

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let back { OnboardingBackButton(action: back) }
                OnboardingProgress(from: Double(count.index - 1) / Double(max(count.total, 1)),
                                   to: Double(count.index) / Double(max(count.total, 1)))
                // Otto's corner (`SeatedClipLayer.cornerWidth`).
                Color.clear.frame(width: SeatedClipLayer.cornerWidth)
            }
            .frame(height: 40)

            Text(title)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)

            VStack(spacing: 10) {
                ForEach(options) { o in
                    OnboardingOption(label: label(o), icon: icon(o),
                                     selected: selected.contains(o), multi: !single) {
                        if single {
                            selected = [o]
                        } else if selected.contains(o) {
                            selected.remove(o)
                        } else {
                            selected.insert(o)
                        }
                    }
                }
            }
            .padding(.top, 24)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", enabled: !selected.isEmpty, action: onContinue)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
    }
}

/// "What's your goal with meditation?", the first question. Six answers;
/// making it a daily habit is left out because that is the whole app.
struct MotivationScreen: View {
    @Binding var selected: Set<Motivation>
    @Binding var otherText: String
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        CornerQuestionScreen(title: "What's your goal with meditation?",
                             options: Motivation.offered, label: \.label, icon: \.icon,
                             selected: $selected, count: count, onContinue: onContinue)
    }
}

/// "Which one sounds most like you?" (Brainrot's "Which best describes
/// you?", reworded). One pick, then Continue.
struct RoleScreen: View {
    @Binding var role: Role?
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        CornerQuestionScreen(title: "Which one sounds most like you?",
                             options: Role.allCases, single: true, label: \.label, icon: \.icon,
                             selected: Binding(get: { role.map { [$0] } ?? [] },
                                               set: { role = $0.first }),
                             count: count, onContinue: onContinue)
    }
}

/// "When could you fit in a few quiet minutes?". One pick; the answer sets
/// the daily reminder's time (see `QuietTime`).
struct QuietTimeScreen: View {
    @Binding var quietTime: QuietTime?
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        CornerQuestionScreen(title: "When could you fit in a few quiet minutes?",
                             options: QuietTime.allCases, single: true, label: \.label, icon: \.icon,
                             selected: Binding(get: { quietTime.map { [$0] } ?? [] },
                                               set: { quietTime = $0.first }),
                             count: count, onContinue: onContinue)
    }
}

/// "Have you tried to make meditation a habit before?" (Brainrot's "Have you
/// tried to reduce screen time before?"). One pick.
struct HabitHistoryScreen: View {
    @Binding var history: HabitHistory?
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        CornerQuestionScreen(title: "Have you tried to make meditation a habit before?",
                             options: HabitHistory.allCases, single: true, label: \.label, icon: \.icon,
                             selected: Binding(get: { history.map { [$0] } ?? [] },
                                               set: { history = $0.first }),
                             count: count, onContinue: onContinue)
    }
}

/// "What usually gets in the way of meditating?", straight after the goal:
/// the question Otto promised on "Let's personalize" ("Your answers show me
/// what gets in the way").
struct ObstaclesScreen: View {
    @Binding var selected: Set<Obstacle>
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        CornerQuestionScreen(title: "What usually gets in the way of meditating?",
                             options: Obstacle.allCases, label: \.label, icon: \.icon,
                             selected: $selected, count: count, onContinue: onContinue)
    }
}

// MARK: - 4 · Q2 Stress (slider)

/// **The stress question, answered on Otto** (Melvin, 2026-09-22: "'how
/// stressed are you' should show the sloth slider, combine it with that
/// screen instead of them being separate"). It absorbed the aura demo, which
/// was a screen of its own for a day.
///
/// Otto sits on his cushion in the valley, exactly where he sits on Home,
/// and asks the question in the same bubble. As the answer is dragged he
/// changes with it: **Burnt out on the left** is Otto withered and gray with
/// a moth on him, **Fine in the middle**, and **Blissful on the right** is
/// Otto at his brightest, floating in light (Melvin, 2026-09-23: worst to
/// best reads left to right, the way the glow bar fills). So the question also
/// shows what 808 is, without a word about it: his state is a picture of
/// yours, and meditating is what brings him back.
///
/// **He is drawn by `OnboardingView`, not here**, in the valley behind every
/// screen, so he does not slide in with the screen as a second copy of the
/// sky would. This screen places the bubble on his head and the controls on
/// the grass, using the same `SitLayout` the valley uses.
///
/// **Teal to red, never gold**, still: gold is the score's colour, and
/// someone's stress is not an achievement.
struct StressScreen: View {
    @Binding var stress: Double
    let count: InterviewCount
    /// Poke Otto: he jiggles, as he does on Home.
    var onPoke: () -> Void = {}
    let onContinue: () -> Void

    @Environment(\.onboardingBack) private var back
    // It does NOT sweep itself on arrival any more (Melvin, 2026-09-23:
    // "dont show the user the options automatically before they scroll ...
    // let them just see it for themselves").

    /// Calm draws him at his brightest, burnt out at his lowest.
    static func stage(for stress: Double) -> OttoAura.Stage {
        OttoAura.Stage(level: level(for: stress))
    }

    /// The same answer as one of the rig's thirteen drawings, so dragging
    /// the bar moves him through every one of them.
    static func look(for stress: Double) -> Int {
        OttoAura.look(level: level(for: stress))
    }

    private static func level(for stress: Double) -> Int {
        Int(((1 - min(max(stress, 0), 1)) * 100).rounded())
    }

    /// Where the thumb sits, 0 at the left (burnt out) to 1 at the right
    /// (blissful). The stored answer keeps its meaning, 1 the most stressed,
    /// so everything downstream (`isHighStress`) reads it as before.
    private var position: Double { 1 - min(max(stress, 0), 1) }

    private var notch: Int { Int((position * 4).rounded()) }

    private var readout: String {
        switch notch {
        case 0: return "Burnt out"
        case 1: return "Carrying a lot"
        case 2: return "Fine"
        case 3: return "Calm"
        default: return "Blissful"
        }
    }

    /// Red at burnt out, a warm sand at fine, sage at blissful. Three stops
    /// rather than two: straight from red to green in RGB passes through a
    /// washed-out brown at exactly the midpoint most people leave it on.
    private var tint: Color {
        let t = min(max(stress, 0), 1)
        let calm  = (r: 0.486, g: 0.659, b: 0.431)   // Color.onboardingSage
        let amber = (r: 0.86, g: 0.64, b: 0.36)
        let hot   = (r: 0.78, g: 0.26, b: 0.22)
        let (from, to, k) = t < 0.5 ? (calm, amber, t * 2) : (amber, hot, (t - 0.5) * 2)
        return Color(red:   from.r + (to.r - from.r) * k,
                     green: from.g + (to.g - from.g) * k,
                     blue:  from.b + (to.b - from.b) * k)
    }

    var body: some View {
        GeometryReader { outer in
            let inset = outer.safeAreaInsets
            GeometryReader { geo in
                let size = geo.size
                let ottoTop = SitLayout.ottoTop(in: size)
                let ottoSize = 186 * SitLayout.scale(in: size)
                let ink = DayLight.at(0).ink
                let top = inset.top + 12
                ZStack(alignment: .top) {
                    HStack(spacing: 14) {
                        if let back {
                            OnboardingBackButton(action: back)
                        }
                        OnboardingProgress(from: Double(count.index - 1) / Double(max(count.total, 1)),
                                           to: Double(count.index) / Double(max(count.total, 1)))
                    }
                    .frame(height: 40)
                    .padding(.horizontal, 24)
                    .padding(.top, top)

                    // His question, pinned by its bottom to just above his
                    // head, the way Home pins his line.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        OttoSpeech(text: "How stressed have you been lately?",
                                   tail: .bottom, size: 19,
                                   ink: ink, stroke: ink.opacity(0.38),
                                   fill: AppColor.backgroundPrimary.opacity(0.85),
                                   speaking: .constant(false))
                    }
                    .frame(width: min(size.width - 56, 330),
                           height: max(0, ottoTop - 8 - (top + 56)))
                    .padding(.top, top + 56)

                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: ottoSize, height: ottoSize)
                        .position(x: size.width / 2, y: ottoTop + ottoSize / 2)
                        .onTapGesture(perform: onPoke)
                        .accessibilityHidden(true)

                    // Everything below his cushion, which leaves about 140pt
                    // on the smallest phone: the words, the bar, the button.
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text(readout)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .onMeadow()
                            .contentTransition(.opacity)
                            .animation(.easeOut(duration: 0.2), value: readout)
                        scrubber
                        OnboardingCTA(title: "Continue", action: onContinue)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, inset.bottom + 4)
                }
                .frame(width: size.width, height: size.height)
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.selection, trigger: Self.stage(for: stress))
    }

    /// Home's glow bar made draggable, filling left to right toward blissful,
    /// the way the glow bar fills. The ends are not labelled: the words above
    /// it name where it is, and Otto shows it.
    private var scrubber: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let width = geo.size.width
                let x = max(0, min(width, width * position))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.85))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(18, x))
                    Circle()
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                        .overlay(Circle().strokeBorder(tint, lineWidth: 3))
                        .offset(x: max(0, min(width - 30, x - 15)))
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    stress = 1 - max(0, min(1, value.location.x / width))
                })
            }
            .frame(height: 30)
        }
        .accessibilityElement()
        .accessibilityLabel("How stressed have you been lately?")
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { direction in
            stress = max(0, min(1, stress + (direction == .increment ? -0.25 : 0.25)))
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
/// cannot measure. Same line the mechanism screen respects.
///
/// The ground turns red here — this is now the first pain question.
struct AloneWithThoughtsScreen: View {
    @StateObject private var gate = AdvanceGate()
    @Binding var answer: AloneWithThoughts?
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, counter: count,
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
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, counter: count,
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
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, counter: count,
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
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, counter: count,
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
        }
    }

    private func pick(_ i: IntendedFor) {
        intended = i
        gate.advance(onContinue)
    }
}

// MARK: - 6 · Q4 The cause

struct BodyCuriosityScreen: View {
    @StateObject private var gate = AdvanceGate()
    @Binding var answer: BodyCuriosity?
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, counter: count,
                         title: "When you meditate, do you\never wonder what your body\nis actually doing?",
                         subtitle: "Underneath the stillness, something is happening.",
                         ctaEnabled: answer != nil,
                         autoAdvances: true,
                         onContinue: { gate.now(onContinue) }) {
            VStack(spacing: 10) {
                ForEach(BodyCuriosity.allCases) { c in
                    OnboardingOption(label: c.label, icon: c.icon,
                                     selected: answer == c) { pick(c) }
                }
            }
        }
    }

    private func pick(_ c: BodyCuriosity) {
        answer = c
        gate.advance(onContinue)
    }
}

struct BodyProofScreen: View {
    @StateObject private var gate = AdvanceGate()
    @Binding var answer: BodyProof?
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, counter: count,
                         title: "After a session, how do\nyou know it worked?",
                         subtitle: "There's no wrong answer. Most people have never had a way to check.",
                         ctaEnabled: answer != nil,
                         autoAdvances: true,
                         onContinue: { gate.now(onContinue) }) {
            VStack(spacing: 10) {
                ForEach(BodyProof.allCases) { b in
                    OnboardingOption(label: b.label, icon: b.icon,
                                     selected: answer == b) { pick(b) }
                }
            }
        }
    }

    private func pick(_ b: BodyProof) {
        answer = b
        gate.advance(onContinue)
    }
}

struct BodyTrackingScreen: View {
    @Binding var tracking: Set<BodyTracking>
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, counter: count,
                         title: "What do you already track\nabout your body?",
                         subtitle: "Pick everything that applies.",
                         ctaEnabled: !tracking.isEmpty,
                         onContinue: onContinue) {
            VStack(spacing: 10) {
                ForEach(BodyTracking.allCases) { t in
                    OnboardingOption(label: t.label, icon: t.icon,
                                     selected: tracking.contains(t), multi: true) {
                        if tracking.contains(t) { tracking.remove(t) } else { tracking.insert(t) }
                    }
                }
            }
        }
    }
}

// MARK: - The accessibility reveal (after the body questions)

/// "Seeing your body meditate used to cost $400." The three questions above
/// name a wish; this screen reveals it is sold as dedicated hardware, then
/// resolves to the watch already on the wrist. Approved mockup 2026-08-29.
///
/// Copy rules: prices are public list prices, marked ≈, checked before ship.
/// Deliberately VAGUE about what any device measures (Aziz): naming sensors
/// starts a spec-sheet argument this screen doesn't need to win. The claim is
/// the wish, the price, and "something similar for everyone". No product
/// photos: silhouettes keep the screen ours.
struct HardwareScreen: View {
    /// Where 808 Premium's price lands once the anchor has been set. Only the
    /// paywall ladder passes one; the interview path never did and no longer
    /// shows this screen at all (Melvin, 2026-09-14).
    var priceLine: String? = nil
    var ctaTitle: String = "Continue"
    /// A second, quieter way out. The ladder needs one at every rung, in
    /// plain words, so a decline never has to be hunted for.
    var declineTitle: String? = nil
    let onContinue: () -> Void
    var onDecline: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("THE HARDWARE YOU'D OTHERWISE NEED")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppColor.textSecondary)
                Text("Seeing your body meditate used to cost $400.")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Dedicated devices sell exactly this wish as extra hardware.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.top, 12)

            VStack(spacing: 8) {
                deviceRow(name: "Muse S", sub: "Meditation headband", price: "≈ $400", headband: true)
                deviceRow(name: "Muse 2", sub: "Meditation headband", price: "≈ $250", headband: true)
                deviceRow(name: "HeartMath", sub: "Clip-on biofeedback sensor", price: "≈ $200", headband: false)
            }

            watchRow

            Text("**808 answers the same wish, for everyone.** No extra hardware, no gadget shelf: your body, read from the watch already on your wrist.")
                .font(.system(size: 13.5))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let priceLine {
                Text(priceLine)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            OnboardingCTA(title: ctaTitle, action: onContinue)

            if let declineTitle, let onDecline {
                Button(declineTitle, action: onDecline)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(hardwareGround.ignoresSafeArea())
    }

    /// The onboarding arc in miniature: ember above (what it costs elsewhere)
    /// resolving to gold below (what you already own). Hand-rolled against the
    /// one-ground-per-section rule because this screen IS the transition, per
    /// the approved mockup.
    private var hardwareGround: some View {
        // One hue with the rest of onboarding (Aziz, 2026-08-29): the ember
        // top went with the colour arc. Cost still reads in the terracotta
        // PRICE text; the ground stays the app's gold.
        ZStack {
            AppColor.backgroundPrimary
            RadialGradient(colors: [AppColor.accentGold.opacity(0.10), .clear],
                           center: .init(x: 0.5, y: -0.08), startRadius: 10, endRadius: 430)
            RadialGradient(colors: [AppColor.accentGold.opacity(0.16), .clear],
                           center: .init(x: 0.5, y: 1.08), startRadius: 10, endRadius: 460)
        }
    }

    private let ember = Color(red: 0.79, green: 0.54, blue: 0.51)

    private func deviceRow(name: String, sub: String, price: String, headband: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if headband { HeadbandSilhouette().stroke(ember, style: StrokeStyle(lineWidth: 2.4, lineCap: .round)) }
                else { SensorSilhouette().stroke(ember, style: StrokeStyle(lineWidth: 2.2, lineCap: .round)) }
            }
            .frame(width: 38, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(sub).font(.system(size: 11)).foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            Text(price)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(ember)
        }
        .padding(12)
        .background(AppColor.backgroundSecondary.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var watchRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.system(size: 22))
                .foregroundStyle(AppColor.accentGold)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Your Apple Watch")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Heart, stillness and breath, every session")
                    .font(.system(size: 11)).foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            Text("$0 extra")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColor.accentGoldText)
        }
        .padding(13)
        .background(
            LinearGradient(colors: [AppColor.accentGold.opacity(0.16),
                                    AppColor.accentGold.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(AppColor.accentGold.opacity(0.55), lineWidth: 1))
    }
}

/// A minimal over-the-head band arc with ear pods.
private struct HeadbandSilhouette: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 2, y: r.maxY - 3))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 2, y: r.maxY - 3),
                       control: CGPoint(x: r.midX, y: r.minY - 4))
        p.addEllipse(in: CGRect(x: r.minX, y: r.maxY - 7, width: 5, height: 5))
        p.addEllipse(in: CGRect(x: r.maxX - 5, y: r.maxY - 7, width: 5, height: 5))
        return p
    }
}

/// A clip-on sensor: a rounded module with a short lead.
private struct SensorSilhouette: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: r.midX - 8, y: r.minY, width: 16, height: 12),
                         cornerSize: CGSize(width: 3.5, height: 3.5))
        p.move(to: CGPoint(x: r.midX, y: r.minY + 12))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

// MARK: - 7 · Q5 The gate

/// Plain language, no spin. A "no" here goes to the waitlist, never to a
/// paywall — we will not take money for an app that can't do its one job.
struct WatchGateScreen: View {
    @StateObject private var gate = AdvanceGate()
    @Binding var hasWatch: Bool?
    let count: InterviewCount
    let onYes: () -> Void
    /// `notYet` is true for "Not yet": no Watch today, one in mind. Both
    /// answers land on the waitlist; the analytics outcome tells them apart,
    /// because a person who plans to buy a Watch is a different lead from one
    /// who never will (Melvin, 2026-09-14: three answers, not two).
    let onNo: (_ notYet: Bool) -> Void
    /// Which of the two "no" rows is lit. `hasWatch` alone cannot say.
    @State private var notYet = false

    var body: some View {
        OnboardingScreen(section: .body, counter: count,
                         title: "Do you have an\nApple Watch?",
                         subtitle: "808 measures from the Watch. Without one there's nothing to measure, so we'd rather tell you now.",
                         ctaEnabled: hasWatch != nil,
                         // Single select, so it advances on the tap like the
                         // rest. A "no" lands on the waitlist without a warning
                         // label, which is fine: that screen explains itself in
                         // its first line and the chevron comes straight back.
                         autoAdvances: true,
                         onContinue: { gate.now { hasWatch == false ? onNo(notYet) : onYes() } }) {
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
                    OnboardingOption(label: "No", icon: "applewatch.slash",
                                     selected: hasWatch == false && !notYet) { pick(false) }
                    OnboardingOption(label: "Not yet", icon: "cart",
                                     selected: hasWatch == false && notYet) { pick(false, notYet: true) }
                }
            }
        }
    }

    private func pick(_ yes: Bool, notYet planned: Bool = false) {
        hasWatch = yes
        notYet = planned
        gate.advance { yes ? onYes() : onNo(planned) }
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
                                .stroke(Color.onboardingSage.opacity(0.3),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            PulseTrace()
                                .trim(from: 0, to: sweep ? 1 : 0)
                                .stroke(Color.onboardingSage,
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
            // A plain grey field that says "email" (2026-09-14 tester: the
            // example address read as a link). Gold caret so the one accent
            // on the screen is ours, not the system blue.
            TextField("", text: $email, prompt: Text("email").foregroundStyle(AppColor.textSecondary.opacity(0.6)))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(OnboardingType.option)
                .foregroundStyle(AppColor.textPrimary)
                .tint(AppColor.accentGold)
                .padding(16)
                .background(AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColor.textSecondary.opacity(0.22), lineWidth: 1))
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
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, counter: count,
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
    @Binding var username: String
    @Binding var ageBracket: String?
    let count: InterviewCount
    let onContinue: () -> Void

    // Melvin asked for Under 18 / 18-21 / 21-25; those overlap at 21, so the
    // boundaries are closed here. Under 18 is deliberate and has App Review
    // consequences worth confirming (age rating, kids-category rules).
    private let brackets = ["Under 18", "18–20", "21–24", "25–34",
                            "35–44", "45–54", "55+"]

    var body: some View {
        OnboardingScreen(section: .body, counter: count,
                         title: "Last thing.",
                         subtitle: "So the app can talk to you like a person, and so friends can find you later. Answer any of these, or none.",
                         onContinue: { gate.now(onContinue) }) {
            VStack(alignment: .leading, spacing: 20) {
                TextField("What should we call you?", text: $firstName)
                    .textContentType(.nickname)
                    .font(OnboardingType.option)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(16)
                    .background(AppColor.backgroundSecondary.opacity(0.8),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Optional like everything else here (5.1.1). Lowercase,
                // letters, digits, underscore and dot, normalised as they type
                // so the handle they see is the handle that gets saved.
                // Friends builds ask for the username on its own screen at the
                // end (Create your profile), reserved for real, so the
                // cosmetic field here goes away.
                if !FeatureFlags.friends {
                HStack(spacing: 6) {
                    Text("@")
                        .font(OnboardingType.option)
                        .foregroundStyle(AppColor.textSecondary)
                    TextField("Pick a username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(OnboardingType.option)
                        .foregroundStyle(AppColor.textPrimary)
                        .onChange(of: username) { _, raw in
                            let clean = Username.normalize(raw) ?? ""
                            if clean != raw { username = clean }
                        }
                }
                .padding(16)
                .background(AppColor.backgroundSecondary.opacity(0.8),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Age")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                    ForEach(brackets, id: \.self) { b in
                        OnboardingOption(label: b, selected: ageBracket == b) { pick(b) }
                    }
                }
            }
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
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .body, counter: count,
                         title: "First, how did\nyou find us?",
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
    let count: InterviewCount
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(section: .cost, counter: count,
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
        }
    }

    private func pick(_ b: BlindSpot) {
        blindSpot = b
        gate.advance(onContinue)
    }
}
