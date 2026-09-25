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
            // On a frosted card in the open sky between the clock and his
            // head (Aziz: the outlined text looked rough). The number in the
            // app's sky blue, the same blue the pause types it in.
            GeometryReader { geo in
                VStack(spacing: 2) {
                    Text("You're on track to spend")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("\(counted) \(unit)")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.skyDeep)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .scaleEffect(landed ? 1.05 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: landed)
                    Text(years == nil ? "a year with your mind elsewhere."
                                      : "with your mind somewhere else.")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.35)))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                )
                .position(x: geo.size.width / 2, y: geo.size.height * 0.40)
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Text(years == nil ? "Based on your answer and 16 waking hours a day."
                                  : "Based on your answers, 16 waking hours a day and a life to 80.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Color.white.opacity(0.35))))
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

/// The pause after the years (Aziz, 2026-09-25, Brainrot's "Do you
/// understand what it means…"): a white page that types one question with a
/// tick a letter, their number in blue, then moves on by itself (Skip moves
/// on at once). A question pointing forward rather than Brainrot's challenge,
/// so it names what they could have rather than what they are losing.
struct LifePauseScreen: View {
    let answers: OnboardingAnswers
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var letters = 0
    @State private var done = false

    private var amount: String {
        if let y = MindWander.years(answers) { return y == 1 ? "1 year" : "\(y) years" }
        return "\(MindWander.daysPerYear(answers)) days a year"
    }
    private var sentence: String { "What would you do with \(amount) of being fully here?" }

    private var typed: AttributedString {
        let text = sentence
        var line = AttributedString(text)
        let cut = line.index(line.startIndex, offsetByCharacters: min(letters, text.count))
        line[line.startIndex..<cut].foregroundColor = AppColor.textPrimary
        line[cut..<line.endIndex].foregroundColor = .clear
        // Their number is blue as it types, letter by letter (Aziz), not
        // repainted once it is finished.
        if let r = line.range(of: amount), r.lowerBound < cut {
            line[r.lowerBound..<min(r.upperBound, cut)].foregroundColor = AppColor.skyDeep
        }
        return line
    }

    var body: some View {
        VStack {
            Spacer()
            Text(typed)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppMetrics.screenPadding + 12)
                .accessibilityLabel(sentence)
            Spacer()
            Button("Skip", action: finish)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary.opacity(0.4))
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let text = sentence
            if reduceMotion {
                letters = text.count
            } else {
                WelcomeHaptics.prepare()
                try? await Task.sleep(for: .milliseconds(150))
                for (i, ch) in text.enumerated() {
                    guard !Task.isCancelled, !done else { return }
                    letters = i + 1
                    if !ch.isWhitespace { WelcomeHaptics.tick() }
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
            // Long enough to read, short enough not to drag (Aziz: the
            // pauses felt too long).
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !done else { return }
        done = true
        onContinue()
    }
}

/// "This is your life." (Aziz, 2026-09-25, Brainrot's dots.) Eighty dots, a
/// year each; the years lived fill in blue, "You are here, assuming you're
/// 30". Then "And this is how much of it your mind spends somewhere else."
/// and that many years fill in terracotta from the end, one by one with a
/// tick, the SAME number as the years screen (`MindWander.years`). One screen,
/// two beats, so the grid never moves. Without an age it is one year of 365
/// days, and only the second beat.
struct LifeDotsScreen: View {
    let answers: OnboardingAnswers
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lived = 0
    @State private var wandering = 0
    @State private var secondBeat = false
    @State private var ctaShown = false
    @State private var skipped = false

    /// Muted terracotta, the website's "cost" colour: a warning's hue with
    /// half the chroma, so a field of it does not read as an error.
    private static let terracotta = Color(red: 0.80, green: 0.47, blue: 0.40)
    private static let lifeBlue = Color(red: 0.55, green: 0.80, blue: 0.96)
    private static let empty = Color(white: 0.87)

    private var age: Double? { MindWander.age(answers) }
    private var total: Int { age == nil ? 365 : 80 }
    private var columns: Int { age == nil ? 19 : 8 }
    private var livedTarget: Int { min(Int(age ?? 0), total) }
    private var wanderTarget: Int {
        min(MindWander.years(answers) ?? MindWander.daysPerYear(answers), total - livedTarget)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(secondBeat ? "And this is how much of it your mind spends somewhere else."
                            : (age == nil ? "This is your year." : "This is your life."))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 110, alignment: .bottom)
                .id(secondBeat)
                .transition(.opacity)
                .padding(.top, 40)

            dots.padding(.top, 28)

            Text(footnote)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(secondBeat ? Self.terracotta : AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .frame(height: 50)
                .padding(.top, 20)
                .id("f\(secondBeat)")
                .transition(.opacity)

            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.35), value: secondBeat)
        .padding(.horizontal, AppMetrics.screenPadding + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            ZStack {
                if ctaShown {
                    OnboardingCTA(title: "Next", action: onContinue)
                        .transition(.opacity)
                } else {
                    Button("Skip", action: skip)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary.opacity(0.4))
                        .frame(height: 56)
                }
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 10)
        }
        .task { await play() }
    }

    private var footnote: String {
        if secondBeat {
            return age == nil ? "\(wanderTarget) days a year" : "\(wanderTarget) years"
        }
        if let age { return "You are here, assuming you're \(Int(age))" }
        return "365 days"
    }

    private var dots: some View {
        let size: CGFloat = age == nil ? 10 : 22
        let gap: CGFloat = age == nil ? 5 : 16
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: gap), count: columns),
                         spacing: gap) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(color(i))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(age == nil
            ? "A year of 365 days, \(wanderTarget) of them with your mind somewhere else"
            : "Eighty years, \(livedTarget) lived, \(wanderTarget) of the rest with your mind somewhere else")
    }

    private func color(_ i: Int) -> Color {
        if i >= total - wandering { return Self.terracotta }
        if i < lived { return Self.lifeBlue }
        return Self.empty
    }

    private func play() async {
        guard !ctaShown else { return }
        if reduceMotion {
            lived = livedTarget; secondBeat = true; wandering = wanderTarget; ctaShown = true
            return
        }
        WelcomeHaptics.prepare()
        try? await Task.sleep(for: .milliseconds(150))
        if age != nil {
            for k in 0..<livedTarget {
                guard !Task.isCancelled, !skipped else { break }
                withAnimation(.easeOut(duration: 0.12)) { lived = k + 1 }
                if k % 2 == 0 { WelcomeHaptics.tick() }
                try? await Task.sleep(for: .milliseconds(35))
            }
            guard !skipped else { return }
            try? await Task.sleep(for: .seconds(0.55))
        }
        guard !Task.isCancelled, !skipped else { return }
        await wander()
    }

    private func wander() async {
        lived = livedTarget
        secondBeat = true
        try? await Task.sleep(for: .milliseconds(200))
        // One dot at a time on the year grid; in bursts on the 365-day grid.
        let per = age == nil ? 5 : 1
        var k = 0
        while k < wanderTarget {
            guard !Task.isCancelled else { return }
            k = min(wanderTarget, k + per)
            withAnimation(.easeOut(duration: 0.15)) { wandering = k }
            WelcomeHaptics.tick()
            try? await Task.sleep(for: .milliseconds(age == nil ? 35 : 90))
        }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { ctaShown = true }
        WelcomeHaptics.land()
    }

    private func skip() {
        guard !skipped else { return }
        skipped = true
        if secondBeat {
            wandering = wanderTarget
            withAnimation { ctaShown = true }
        } else {
            Task { await wander() }
        }
    }
}
