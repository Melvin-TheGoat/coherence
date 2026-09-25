import SwiftUI

// The wandering question (Aziz, 2026-09-25). Its answer feeds `MindWander`,
// the arithmetic behind the "N years" moment after the mind profile: THEIR
// numbers multiplied, never invented. That moment is to be a GENERATED
// animation (Aziz), not built screens; a first attempt at building it as four
// SwiftUI screens was dropped the same day.

// MARK: - The question

/// "How much of your day is your mind somewhere else?" Five stops in words
/// (`WanderLevel`), each a share behind the scenes, opening on the middle one,
/// the research average, which the note under it names. Age
/// is not mentioned here (Aziz): it first appears in the "N years" moment.
struct WanderingScreen: View {
    @Binding var share: Double?
    let count: InterviewCount
    let onContinue: () -> Void

    @Environment(\.onboardingBack) private var back
    private var level: WanderLevel { WanderLevel(share: share ?? MindWander.average) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let back { OnboardingBackButton(action: back) }
                OnboardingProgress(from: Double(count.index - 1) / Double(max(count.total, 1)),
                                   to: Double(count.index) / Double(max(count.total, 1)))
                Color.clear.frame(width: SeatedClipLayer.cornerWidth)
            }
            .frame(height: 40)

            // Clear of the corner Otto: it touched him at 24 (Aziz).
            Text("How much of your day is your mind somewhere else?")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 44)
            Text("Your best guess. There's no wrong answer.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textPrimary.opacity(0.7))
                .padding(.top, 8)

            Text(level.label)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: level)
                .frame(height: 50)
                .padding(.top, 22)

            WordSlider(index: Binding(get: { level.rawValue },
                                      set: { share = WanderLevel(rawValue: $0)?.share }))
                .padding(.top, 12)
            HStack {
                Text("Rarely")
                Spacer()
                Text("Almost always")
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(AppColor.textPrimary.opacity(0.75))
            .padding(.top, 4)

            Text("Most people say about half the time.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.skyDeep)
                .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue") {
                if share == nil { share = MindWander.average }
                onContinue()
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 10)
        }
        .sensoryFeedback(.selection, trigger: level)
    }
}

/// Five stops, green, Otto's face as the handle.
private struct WordSlider: View {
    @Binding var index: Int
    private static let knob: CGFloat = 46
    private static let stops = WanderLevel.allCases.count

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width - Self.knob
            let x = travel * CGFloat(index) / CGFloat(Self.stops - 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white)
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                    .frame(height: 14)
                Capsule().fill(OnboardingGreen.fill)
                    .frame(width: x + Self.knob / 2, height: 14)
                Image("OttoHead")
                    .resizable().scaledToFit().padding(5)
                    .frame(width: Self.knob, height: Self.knob)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                    .offset(x: x)
            }
            .frame(height: Self.knob)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: index)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let t = min(max((g.location.x - Self.knob / 2) / max(1, travel), 0), 1)
                index = Int((t * CGFloat(Self.stops - 1)).rounded())
            })
        }
        .frame(height: Self.knob)
        .accessibilityElement()
        .accessibilityLabel("How much of your day your mind is somewhere else")
        .accessibilityValue(WanderLevel(rawValue: index)?.label ?? "")
        .accessibilityAdjustableAction { d in
            index = min(Self.stops - 1, max(0, index + (d == .increment ? 1 : -1)))
        }
    }
}

// MARK: - The years

/// "You're on track to spend N years with your mind somewhere else" (Aziz,
/// 2026-09-25, Brainrot's "25 years" screen). A generated clip fills the
/// screen: Otto sits still while the seasons race past him under a clock, and
/// it ends in spring with him looking afraid (`otto-seasons.mov`, cut at that
/// frame and held there). The number counts up while the seasons pass, a tick
/// a step, and lands with a thump as the clip ends. The words sit at the top
/// over the sky, Brainrot's layout (Aziz), the disclaimer at the bottom.
struct LifeNumberScreen: View {
    let answers: OnboardingAnswers
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var counted = 0
    @State private var landed = false

    private var years: Int? { MindWander.years(answers) }
    private var target: Int { years ?? MindWander.daysPerYear(answers) }
    private var unit: String {
        years == nil ? (target == 1 ? "day" : "days") : (target == 1 ? "year" : "years")
    }

    /// Matches the clip: 5.15 s.
    private static let clipSeconds = 5.15

    var body: some View {
        ZStack {
            OttoClip(name: "otto-seasons", playing: !reduceMotion, fallback: .meditating, fills: true)
                .ignoresSafeArea()

            // Brainrot's layout, fitted into the open sky between the clock
            // and Otto's head: the clip puts the clock at the top of the sky,
            // and the words over it could not be read (Aziz). Placed from the
            // screen's height, because the clip is drawn to fill it.
            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Dark with a white outline, like the number: white text
                    // over the pale sky and the clock could not be read (Aziz).
                    OutlinedNumber(text: "You're on track to spend", size: 20, outline: 2.2)
                    OutlinedNumber(text: "\(counted) \(unit)")
                        .contentTransition(.numericText())
                        .scaleEffect(landed ? 1.05 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: landed)
                    OutlinedNumber(text: years == nil ? "a year with your mind elsewhere."
                                                      : "with your mind somewhere else.",
                                   size: 20, outline: 2.2)
                }
                .frame(width: geo.size.width)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.40)
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                OutlinedNumber(text: years == nil ? "Based on your answer and 16 waking hours a day."
                                                  : "Based on your answers, 16 waking hours a day and a life to 80.",
                               size: 12, outline: 1.6)
                OnboardingCTA(title: "Next", action: onContinue)
                    .opacity(landed ? 1 : 0)
                    .allowsHitTesting(landed)
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 10)
        }
        .task {
            if reduceMotion { counted = target; landed = true; return }
            WelcomeHaptics.prepare()
            // Count up across the seasons, landing as the clip ends.
            let steps = max(1, min(target, 40))
            let per = Self.clipSeconds * 0.9 / Double(steps)
            try? await Task.sleep(for: .milliseconds(300))
            for k in 1...steps {
                guard !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.1)) {
                    counted = Int((Double(target) * Double(k) / Double(steps)).rounded())
                }
                WelcomeHaptics.tick()
                try? await Task.sleep(for: .seconds(per))
            }
            guard !Task.isCancelled else { return }
            landed = true
            WelcomeHaptics.land()
        }
    }
}

/// Dark text with a white outline, Brainrot's number style, used for all
/// three lines of the years screen: eight white copies
/// nudged around it, then the dark text on top.
private struct OutlinedNumber: View {
    let text: String
    var size: CGFloat = 54
    var outline: CGFloat = 3.5

    var body: some View {
        let font = Font.system(size: size, weight: .black, design: .rounded)
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) / 8 * 2 * .pi
                Text(text).font(font).foregroundStyle(.white)
                    .offset(x: cos(a) * outline, y: sin(a) * outline)
            }
            Text(text).font(font).foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.16))
        }
        .monospacedDigit()
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
    }
}
