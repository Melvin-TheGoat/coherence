import SwiftUI
import StoreKit

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

    /// Matches the clip: 4.9 s (the Higgsfield regeneration of 2026-09-27,
    /// cut where he is frightened in spring; the first cut ran 5.15).
    private static let clipSeconds = 4.9

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

// MARK: - The good news

/// "The good news is…" (Aziz, 2026-09-25, Brainrot's "11 years back").
/// Otto bright again in the valley (`OnboardingView` draws him at his Bright
/// look on this step). "The good news is…" types, then "808 can help you
/// train your attention. Win back even a quarter of it, and that's", then a
/// QUARTER of their number counts up in big green (`MindWander.quarterBack`).
/// Researched 2026-09-25: every study finds meditation reduces mind wandering
/// (Mrazek 2013, Price 2023, Brandmeyer 2018), and none reports it as a share
/// of the day, so there is no honest "N% more present" to multiply by. The
/// training claim is sourced; the number stays an "if" on their own answers.
struct GoodNewsScreen: View {
    let answers: OnboardingAnswers
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headLetters = 0
    @State private var bodyLetters = 0
    @State private var counted = 0
    @State private var numberShown = false
    @State private var landed = false

    private static let head = "The good news is…"
    private static let body = "808 can help you train your attention. Win back even a quarter of it, and that's"

    private var target: Int { MindWander.quarterBack(answers) }
    private var unit: String {
        MindWander.years(answers) == nil ? (target == 1 ? "day a year" : "days a year")
                                         : (target == 1 ? "year back" : "years back")
    }

    private static func typed(_ text: String, _ n: Int, _ ink: Color) -> AttributedString {
        var line = AttributedString(text)
        let cut = line.index(line.startIndex, offsetByCharacters: min(n, text.count))
        line[line.startIndex..<cut].foregroundColor = ink
        line[cut..<line.endIndex].foregroundColor = .clear
        return line
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(Self.typed(Self.head, headLetters, AppColor.textPrimary))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
            Text(Self.typed(Self.body, bodyLetters, AppColor.textPrimary.opacity(0.85)))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text("\(counted) \(unit)")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(OnboardingGreen.fill)
                .monospacedDigit()
                .contentTransition(.numericText())
                .scaleEffect(landed ? 1.06 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: landed)
                .shadow(color: .white.opacity(0.8), radius: 8)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .opacity(numberShown ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding + 6)
        .padding(.top, 46)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.head) \(Self.body) \(target) \(unit).")
        .safeAreaInset(edge: .bottom) {
            // "Let's do this!" moved to the screen after, where it lands on
            // the payoff (Aziz); said twice in a row it would lose its punch.
            OnboardingCTA(title: "Continue", action: onContinue)
                .opacity(landed ? 1 : 0)
                .allowsHitTesting(landed)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .task { await play() }
    }

    private func type(_ text: String, _ set: (Int) -> Void) async {
        for (i, ch) in text.enumerated() {
            guard !Task.isCancelled else { return }
            set(i + 1)
            if !ch.isWhitespace { WelcomeHaptics.tick() }
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private func play() async {
        guard !landed else { return }
        if reduceMotion {
            headLetters = Self.head.count; bodyLetters = Self.body.count
            counted = target; numberShown = true; landed = true
            return
        }
        WelcomeHaptics.prepare()
        try? await Task.sleep(for: .milliseconds(250))
        // "The good news is…" first, a beat, then the rest (Aziz).
        await type(Self.head) { headLetters = $0 }
        try? await Task.sleep(for: .milliseconds(350))
        await type(Self.body) { bodyLetters = $0 }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { numberShown = true }
        let steps = max(1, min(target, 20))
        for k in 1...steps {
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.1)) {
                counted = Int((Double(target) * Double(k) / Double(steps)).rounded())
            }
            WelcomeHaptics.tick()
            try? await Task.sleep(for: .milliseconds(60))
        }
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { landed = true }
        WelcomeHaptics.land()
    }
}

// MARK: - More years of…

/// "4 more years of family / having fun / the beauty of this world / so much
/// more." (Aziz, 2026-09-25, Brainrot's "11 more years of Playing"). One
/// generated clip fills the screen (`otto-life-moments.mov`, 10 s, 20 fps):
/// his family arrives and they hug, he blows a dandelion laughing, then the
/// valley turns golden and he takes it in, held on that last frame. The big
/// word swaps on the clip's own beats, a thump each, and the number is the
/// good news screen's quarter (`MindWander.quarterBack`).
struct LifeMomentsScreen: View {
    let answers: OnboardingAnswers
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0
    @State private var shown = false
    @State private var ctaShown = false

    /// When each word takes over, in seconds into the clip, measured on it.
    /// Re-measured on the Higgsfield clip of 2026-09-27 (the family at his
    /// size): the family hugs him until about 4.5 s, he lifts the dandelion
    /// at 5.3, the golden light breaks at 6.8, and he settles from 8.6.
    /// The words are all onboarding green (Aziz; a colour each was tried
    /// first), the green the good news screen counts its years in.
    private static let beats: [(at: Double, word: String)] = [
        (0.0, "family"),
        (5.3, "having fun"),
        (6.8, "the beauty of this world"),
        (8.6, "so much more."),
    ]

    private var header: String {
        let n = MindWander.quarterBack(answers)
        if MindWander.years(answers) == nil { return "\(n) more days a year of" }
        return n == 1 ? "1 more year of" : "\(n) more years of"
    }

    var body: some View {
        ZStack(alignment: .top) {
            OttoClip(name: "otto-life-moments", playing: !reduceMotion, fallback: .pleased, fills: true)
                .ignoresSafeArea()

            VStack(spacing: 4) {
                Text(header)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.85))
                Text(Self.beats[beat].word)
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(OnboardingGreen.fill)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(beat)
                    .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                            removal: .opacity))
            }
            .shadow(color: .white.opacity(0.9), radius: 10)
            .shadow(color: .white.opacity(0.6), radius: 3)
            .padding(.horizontal, AppMetrics.screenPadding + 6)
            .padding(.top, 70)
            .opacity(shown ? 1 : 0)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Let's do this!", action: onContinue)
                .opacity(ctaShown ? 1 : 0)
                .allowsHitTesting(ctaShown)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(header) family, having fun, the beauty of this world, and so much more.")
        .task { await play() }
    }

    private func play() async {
        withAnimation(.easeOut(duration: 0.35)) { shown = true }
        if reduceMotion {
            beat = Self.beats.count - 1
            ctaShown = true
            return
        }
        WelcomeHaptics.prepare()
        WelcomeHaptics.land()
        let start = Date()
        for i in 1..<Self.beats.count {
            let wait = Self.beats[i].at - Date().timeIntervalSince(start)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { beat = i }
            WelcomeHaptics.land()
        }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { ctaShown = true }
    }
}

// MARK: - Your attention has been hacked

/// "Your attention has been hacked." (Aziz, 2026-09-25, Brainrot's
/// "Willpower doesn't work against dopamine loops"), after "more years of",
/// before "Why 808 works". A plain white page so the words carry it (Aziz: no
/// sloth, nothing to pull the eye). The headline, then three lines popping in
/// with a tick. Aziz's wording, tightened to what holds: apps are built to
/// hold attention (not "designed to shorten your attention span", a claim
/// about intent) and worry is future-focused thinking. The last line is
/// Aziz's, kept as he wants it: a felt claim, not a statistic.
struct AttentionHackedScreen: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headShown = false
    @State private var shownCards = 0
    @State private var ctaShown = false

    /// A slight red (Aziz), the "cost" terracotta at a wash.
    static let warning = Color(red: 0.95, green: 0.86, blue: 0.83)

    static let lines = [
        "Apps are designed to keep pulling at your attention.",
        "Your mind lives in the future, where anxiety grows.",
        "That anxiety subconsciously seeps into every facet of your life.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("Your attention has been hacked.")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(headShown ? 1 : 0)
                .scaleEffect(headShown ? 1 : 0.94)

            VStack(spacing: 12) {
                ForEach(Array(Self.lines.enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Self.warning))
                        .opacity(i < shownCards ? 1 : 0)
                        .offset(y: i < shownCards ? 0 : 12)
                }
            }
            .padding(.top, 40)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", action: onContinue)
                .opacity(ctaShown ? 1 : 0)
                .offset(y: ctaShown ? 0 : 30)
                .allowsHitTesting(ctaShown)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .task {
            if reduceMotion { headShown = true; shownCards = Self.lines.count; ctaShown = true; return }
            WelcomeHaptics.prepare()
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { headShown = true }
            WelcomeHaptics.land()
            try? await Task.sleep(for: .milliseconds(650))
            for i in 0..<Self.lines.count {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { shownCards = i + 1 }
                WelcomeHaptics.tick()
                try? await Task.sleep(for: .milliseconds(650))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { ctaShown = true }
            WelcomeHaptics.land()
        }
    }
}

// MARK: - How 808 makes it stick

/// "How 808 makes it stick" (Aziz, 2026-09-25), after "Your attention has
/// been hacked": the MECHANISM, what the app does that makes meditating a
/// daily habit, as three cards popping in with a tick. A Brainrot-style
/// "X → bad, 808 → good" comparison was built first and dropped ("terrible").
/// Every card is something the app really does: Otto's glow rises with each
/// day meditated and fades with missed ones (`OttoAura`), the daily reminder
/// fires at the quiet-minutes time, and Block, only on builds that have it,
/// holds the chosen apps until a session is done.
struct WhyItWorksScreen: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headShown = false
    @State private var shownRows = 0
    @State private var ctaShown = false

    /// With Block, a chain (Aziz, 2026-09-25): friction, then a reminder
    /// every time, then the habit sinking in. Without it, the features the
    /// build does have, so the screen never sells what is not there.
    private static var chain: Bool { FeatureFlags.block }

    /// The icons are "In 1 week"'s (Melvin, 2026-09-27): a filled symbol in
    /// its own colour on a white disc with a soft shadow, the same four
    /// colours that screen uses.
    private static let blue = Color(red: 0.25, green: 0.55, blue: 0.85)
    private static let orange = Color(red: 0.93, green: 0.62, blue: 0.24)

    private static var rows: [(icon: String, tint: Color, title: String, line: String)] {
        if chain {
            return [
                ("lock.fill", blue, "808 puts a little friction between you and your apps", ""),
                ("bell.fill", orange, "Every time you open one, Otto reminds you to meditate", ""),
                ("sparkles", OnboardingGreen.shade, "Over time it sinks into your subconscious, and meditating becomes a habit you enjoy instead of dread", ""),
            ]
        }
        return [
            ("sparkles", orange, "Otto's glow", "Meditate and he glows brighter. Skip days and he fades."),
            ("bell.fill", blue, "A nudge at your time", "One reminder a day, at the time you picked."),
            ("clock.fill", OnboardingGreen.shade, "Just five minutes", "Short enough to fit into any day."),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("How 808 makes meditation stick")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .opacity(headShown ? 1 : 0)
                .scaleEffect(headShown ? 1 : 0.94)

            VStack(spacing: Self.chain ? 6 : 12) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { i, row in
                    if Self.chain && i > 0 {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(OnboardingGreen.shade.opacity(0.7))
                            .opacity(i < shownRows ? 1 : 0)
                    }
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: row.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(row.tint)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(.white))
                            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.system(size: Self.chain ? 17 : 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !row.line.isEmpty {
                                Text(row.line)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppColor.textPrimary.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(white: 0.965)))
                    .opacity(i < shownRows ? 1 : 0)
                    .offset(y: i < shownRows ? 0 : 14)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 32)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding + 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", action: onContinue)
                .opacity(ctaShown ? 1 : 0)
                .offset(y: ctaShown ? 0 : 30)
                .allowsHitTesting(ctaShown)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .task {
            if reduceMotion { headShown = true; shownRows = Self.rows.count; ctaShown = true; return }
            WelcomeHaptics.prepare()
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { headShown = true }
            WelcomeHaptics.land()
            try? await Task.sleep(for: .milliseconds(500))
            for i in 0..<Self.rows.count {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { shownRows = i + 1 }
                WelcomeHaptics.tick()
                try? await Task.sleep(for: .milliseconds(Self.chain ? 800 : 550))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { ctaShown = true }
            WelcomeHaptics.land()
        }
    }
}

// MARK: - 808 is built on research

/// "808 is built on research" (Aziz, 2026-09-26, Brainrot's "built based on
/// research" screen), after "How 808 makes meditation stick". One study for
/// each link of that chain, named by where it was done:
///
/// - Harvard: Killingsworth & Gilbert 2010, *Science* 330:932,
///   doi:10.1126/science.1192439. "Thinking about what is not happening
///   almost as often as ... what is", and it makes people unhappier.
/// - Heidelberg University and the Max Planck Institute: Grüning, Riedel &
///   Lorenz-Spreen 2023, *PNAS* 120(8):e2213114120,
///   doi:10.1073/pnas.2213114120. A pop-up with a short wait before a chosen
///   app opens cut actual openings by 57% after six weeks (280 people).
///   That is the friction Block adds; the study is of another app, so the
///   line says what a pause did, never what 808 does.
/// - University College London: Lally, van Jaarsveld, Potts & Wardle 2010,
///   *European Journal of Social Psychology* 40(6):998, doi:10.1002/ejsp.674.
///   Repeating a behaviour in a consistent context made it automatic, and
///   "missing one opportunity ... did not materially affect" it.
///
/// **The logos are Aziz's call (2026-09-26), over a flagged risk:** a crest
/// is a trademark and can read as the university vouching for the app,
/// which App Review 5.2.1 can reject. The footnote saying 808 is not
/// affiliated must stay. Logos from Wikimedia (`Research*` image sets).
/// Every figure here is from the study's own abstract.
struct ResearchScreen: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headShown = false
    @State private var shownRows = 0
    @State private var ctaShown = false

    /// Just the logos, one to a row, like Brainrot's (Aziz, 2026-09-26: "get
    /// rid of the text underneath"). The findings behind them are in the doc
    /// comment above. Heights are by eye, so each mark carries about the
    /// same weight: the Heidelberg seal is mostly circle, Max Planck mostly
    /// a long wordmark.
    private static let logos: [(name: String, place: String, height: CGFloat)] = [
        ("ResearchHarvard", "Harvard University", 72),
        ("ResearchHeidelberg", "Heidelberg University", 84),
        ("ResearchMaxPlanck", "Max Planck Institute", 40),
        ("ResearchUCL", "University College London", 46),
    ]

    private static let pillars = [
        "Behavioral psychology",
        "Makes meditation a daily habit",
        "5–10 minutes a day is enough to start",
    ]

    /// The pale green the onboarding cards use.
    private static let wash = Color(red: 0.84, green: 0.94, blue: 0.82)

    var body: some View {
        GeometryReader { geo in
            // An SE has about 120pt less to give than a 17.
            let compact = geo.size.height < 640
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text("808 is built on research")
                    .font(.system(size: compact ? 28 : 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(headShown ? 1 : 0)
                    .scaleEffect(headShown ? 1 : 0.94)

                VStack(spacing: compact ? 22 : 34) {
                    ForEach(Array(Self.logos.enumerated()), id: \.offset) { i, logo in
                        Image(logo.name)
                            .resizable()
                            .scaledToFit()
                            .frame(height: logo.height * (compact ? 0.78 : 1))
                            .frame(maxWidth: .infinity)
                            .opacity(i < shownRows ? 1 : 0)
                            .offset(y: i < shownRows ? 0 : 12)
                            .accessibilityLabel(logo.place)
                    }
                }
                .padding(.top, compact ? 20 : 32)

                VStack(spacing: compact ? 6 : 10) {
                    ForEach(Self.pillars, id: \.self) { line in
                        Text(line)
                            .font(.system(size: compact ? 16 : 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 16 : 22)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.wash))
                .padding(.top, compact ? 20 : 32)
                .opacity(shownRows > Self.logos.count ? 1 : 0)
                .offset(y: shownRows > Self.logos.count ? 0 : 12)
                .accessibilityElement(children: .combine)

                Text("Findings from published studies. 808 is not affiliated with these institutions.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .opacity(ctaShown ? 1 : 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppMetrics.screenPadding + 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", action: onContinue)
                .opacity(ctaShown ? 1 : 0)
                .offset(y: ctaShown ? 0 : 30)
                .allowsHitTesting(ctaShown)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .task {
            let steps = Self.logos.count + 1
            if reduceMotion { headShown = true; shownRows = steps; ctaShown = true; return }
            WelcomeHaptics.prepare()
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { headShown = true }
            WelcomeHaptics.land()
            try? await Task.sleep(for: .milliseconds(550))
            for i in 0..<steps {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { shownRows = i + 1 }
                WelcomeHaptics.tick()
                try? await Task.sleep(for: .milliseconds(700))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { ctaShown = true }
            WelcomeHaptics.land()
        }
    }
}

// MARK: - Made for people like you

/// "808 was made for people like you." (Aziz, 2026-09-26, Brainrot's rating
/// screen), after the research screen. Two jobs:
///
/// 1. **It asks for an App Store rating.** Apple's own sheet, asked once as
///    the screen settles, for EVERYONE: no "do you like it?" question first,
///    because routing only happy people to the sheet is ratings manipulation
///    and a live rejection (see `ReviewPrompt`). This reverses the old
///    "never inside onboarding" rule, at Aziz's call. It does not stamp
///    `ReviewPrompt.lastAskedKey`, so the post-session ask still comes after
///    the third real session; Apple caps its sheet at three a year whatever
///    we call.
/// 2. **Social proof from famous meditators, not user reviews.** 808 has too
///    few ratings to quote, and invented reviews are out. The three quotes
///    are the verbatim, on-the-record lines the old wall screen carried.
///
/// **Faces are Aziz's call, over a flagged risk:** a famous face beside an
/// app can read as an endorsement (right of publicity, App Review 5.2.1),
/// so the footnote saying they don't endorse 808 must stay. Photos from
/// Wikimedia Commons, cropped to the face, credited in the footnote as their
/// licences ask: Oprah Winfrey 1997 by John Mathew Smith (CC BY-SA 2.0),
/// Kobe Bryant shooting a free throw by Steve Lipofsky (CC BY-SA 3.0), Ray Dalio by Locksteel888
/// (CC BY-SA 4.0). Smiling portraits picked from every free photo of each
/// (Aziz: the first set, mid-sentence and mid-game, "were ass").
struct SocialProofScreen: View {
    let onContinue: () -> Void

    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var quoteIndex = 0
    @State private var asked = false

    private struct Voice {
        let image: String
        let name: String
        let role: String
        let quote: String
    }

    private static let voices: [Voice] = [
        Voice(image: "ProofKobe", name: "Kobe Bryant", role: "5× NBA champion",
              quote: "It's like having an anchor. If I don't do it, it feels like I'm constantly chasing the day."),
        Voice(image: "ProofOprah", name: "Oprah Winfrey", role: "Media leader",
              quote: "Meditation reorders the natural flow of life… Decisions come easily, things fall into place, and there's no conflict."),
        Voice(image: "ProofDalio", name: "Ray Dalio", role: "Founder, Bridgewater Associates",
              quote: "Transcendental Meditation has probably been the single most important reason for whatever success I've had."),
    ]

    private static let gold = Color(red: 0.93, green: 0.62, blue: 0.24)
    private static let cardFill = Color(red: 0.87, green: 0.92, blue: 0.99)

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 640
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Otto at his radiant look, light already painted round him.
                Image("OttoAura6")
                    .resizable()
                    .scaledToFit()
                    .frame(height: compact ? 150 : 200)
                    .opacity(shown > 0 ? 1 : 0)
                    .scaleEffect(shown > 0 ? 1 : 0.9, anchor: .bottom)
                    .accessibilityHidden(true)

                Text("808 was made for\npeople like you.")
                    .font(.system(size: compact ? 28 : 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .opacity(shown > 0 ? 1 : 0)

                faces
                    .padding(.top, compact ? 12 : 18)
                    .opacity(shown > 1 ? 1 : 0)
                    .offset(y: shown > 1 ? 0 : 10)

                ratingRow
                    .padding(.top, compact ? 10 : 16)
                    .opacity(shown > 2 ? 1 : 0)
                    .offset(y: shown > 2 ? 0 : 10)

                quoteCard
                    .padding(.top, compact ? 14 : 22)
                    .opacity(shown > 3 ? 1 : 0)
                    .offset(y: shown > 3 ? 0 : 12)

                Text("Quotes from public interviews. None of them endorse 808. Photos: Steve Lipofsky, John Mathew Smith, Locksteel888 (CC BY-SA).")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .opacity(shown > 3 ? 1 : 0)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppMetrics.screenPadding + 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", action: onContinue)
                .opacity(shown > 3 ? 1 : 0)
                .offset(y: shown > 3 ? 0 : 30)
                .allowsHitTesting(shown > 3)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .task { await play() }
        .task { await rotate() }
    }

    /// The three faces, overlapping, each ringed in white.
    private var faces: some View {
        HStack(spacing: -16) {
            ForEach(Array(Self.voices.enumerated()), id: \.offset) { i, v in
                Image(v.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 66, height: 66)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 4))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    // The one being quoted comes forward.
                    .scaleEffect(i == quoteIndex ? 1.08 : 1)
                    .zIndex(i == quoteIndex ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: quoteIndex)
            }
        }
        .accessibilityHidden(true)
    }

    /// Brainrot's laurel row, asking for the rating rather than quoting one.
    private var ratingRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Self.gold)
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Self.gold)
                    }
                }
                Text("Your rating helps others find 808")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.6))
            }
            Image(systemName: "laurel.trailing")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Self.gold)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating helps others find 808")
    }

    /// One quote at a time, turning every few seconds.
    private var quoteCard: some View {
        let v = Self.voices[quoteIndex]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(v.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(v.name)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(v.role)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: "quote.opening")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColor.skyDeep.opacity(0.55))
            }
            Text("“\(v.quote)”")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                // Room for the longest quote, so the card never jumps.
                .frame(minHeight: 66, alignment: .top)
            HStack(spacing: 6) {
                ForEach(0..<Self.voices.count, id: \.self) { i in
                    Capsule()
                        .fill(i == quoteIndex ? AppColor.skyDeep : AppColor.skyDeep.opacity(0.22))
                        .frame(width: i == quoteIndex ? 18 : 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.cardFill))
        .id(quoteIndex)
        .transition(.opacity)
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .accessibilityElement(children: .combine)
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.35)) {
            quoteIndex = (quoteIndex + 1) % Self.voices.count
        }
    }

    private func play() async {
        if reduceMotion { shown = 4 } else {
            WelcomeHaptics.prepare()
            try? await Task.sleep(for: .milliseconds(200))
            for i in 1...4 {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { shown = i }
                i == 1 || i == 4 ? WelcomeHaptics.land() : WelcomeHaptics.tick()
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
        // Apple's rating sheet, once the screen has settled.
        try? await Task.sleep(for: .milliseconds(600))
        // Once per onboarding, not once per visit: `asked` is reset every
        // time the screen is rebuilt (Back and forward, a resume), so the
        // flag lives in UserDefaults and is cleared with the resume record
        // when onboarding ends or someone signs out.
        guard !Task.isCancelled, !asked,
              !UserDefaults.standard.bool(forKey: OnboardingResume.reviewAskedKey) else { return }
        asked = true
        UserDefaults.standard.set(true, forKey: OnboardingResume.reviewAskedKey)
        Analytics.track(.ratingPrompted(placement: "onboarding"))
        requestReview()
    }

    private func rotate() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            advance()
        }
    }
}

// MARK: - This week, 808 will help you

/// "In 1 week, 808 will help you:" (Aziz, 2026-09-26, Brainrot's week-ahead
/// screen), after "808 was made for people like you". Four rows popping in
/// with a tick, Otto with his hand up underneath.
///
/// No row carries a number: Brainrot's "Save over 3 hours every day" is
/// exactly the invented figure 808 refuses. The last two answer the problems people come with
/// (Aziz: stress, and not being present).
struct ThisWeekScreen: View {
    let answers: OnboardingAnswers
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headShown = false
    @State private var shownRows = 0
    @State private var ottoShown = false
    @State private var ctaShown = false

    private struct Row { let icon: String; let tint: Color; let text: String }

    private static let cardFill = Color(red: 0.87, green: 0.92, blue: 0.99)

    /// Aziz, 2026-09-26: the routine on top, clarity second, then two
    /// things the reader will actually SEE the app do for them.
    private var rows: [Row] {
        [
            Row(icon: "sun.max.fill", tint: Color(red: 0.93, green: 0.62, blue: 0.24),
                text: "Make meditation part of your daily routine"),
            Row(icon: "wind", tint: Color(red: 0.25, green: 0.55, blue: 0.85),
                text: "Improve your mental clarity"),
            Row(icon: "heart.fill", tint: Color(red: 0.87, green: 0.36, blue: 0.33),
                text: "Regulate your emotions and stress"),
            Row(icon: "leaf.fill", tint: OnboardingGreen.shade,
                text: "Be more present in your everyday life"),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 640
            VStack(spacing: 0) {
                Text("In 1 week, 808\nwill help you:")
                    .font(.system(size: compact ? 28 : 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, compact ? 16 : 36)
                    .opacity(headShown ? 1 : 0)
                    .scaleEffect(headShown ? 1 : 0.94)

                VStack(spacing: compact ? 10 : 14) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        HStack(spacing: 16) {
                            Image(systemName: row.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(row.tint)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(.white))
                                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                            Text(row.text)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, compact ? 12 : 16)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.cardFill))
                        .opacity(i < shownRows ? 1 : 0)
                        .offset(x: i < shownRows ? 0 : -24)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, compact ? 18 : 28)

                Spacer(minLength: 8)

                Image("OttoGreet")
                    .resizable()
                    .scaledToFit()
                    .frame(height: compact ? 120 : 170)
                    .opacity(ottoShown ? 1 : 0)
                    .scaleEffect(ottoShown ? 1 : 0.85, anchor: .bottom)
                    .accessibilityHidden(true)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, AppMetrics.screenPadding + 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", action: onContinue)
                .opacity(ctaShown ? 1 : 0)
                .offset(y: ctaShown ? 0 : 30)
                .allowsHitTesting(ctaShown)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .task {
            let count = rows.count
            if reduceMotion { headShown = true; shownRows = count; ottoShown = true; ctaShown = true; return }
            WelcomeHaptics.prepare()
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { headShown = true }
            WelcomeHaptics.land()
            try? await Task.sleep(for: .milliseconds(450))
            for i in 0..<count {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { shownRows = i + 1 }
                WelcomeHaptics.tick()
                try? await Task.sleep(for: .milliseconds(420))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { ottoShown = true }
            WelcomeHaptics.land()
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { ctaShown = true }
        }
    }
}

// MARK: - Ready to take control? (hold to ascend)

/// "Ready to take control?" (Aziz, 2026-09-26, Brainrot's hold-to-ascend
/// screen), after "In 1 week, 808 will help you". The reader presses and
/// holds; Otto rises from his middle look (Steady, level 50, content but not
/// glowing) through every look to Nirvana. From the bright looks up the aura
/// rig (`OttoAura.riv`, Rive) floats and bobs him and brings in his light,
/// halo and leaves; `lift` raises him further off his stone so he clearly
/// levitates. Looks change instantly (`snap`): the rig's cross-fade leaves
/// him half see-through for each fade, and against the bright moon he
/// looked like a ghost the whole way up.
///
/// **Its own place, not the meadow** (Aziz: "something like the brainrot one
/// but dont copy it"): a lake at dusk under a big moon, from Melvin's
/// moodboard (a figure on a stone before an enormous moon, doubled in still
/// water; circles settle things; light is an event). Otto sits on a flat
/// stone in the water; ripples spread from it while he rises, and the moon
/// and its reflection brighten with him.
///
/// Let go early and he settles back down, so the hold is the commitment.
/// Ticks firm up as he climbs; the finish is a success buzz, the words turn
/// to "Let's go!", and Continue replaces the button.
struct AscendScreen: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var rig = OttoRigHolder()
    @State private var level: Double = 50
    /// How far he floats off the stone, 0 to 1. Its own state, animated on
    /// its own: animating `level` also eased the rig's frame from wide to
    /// tall at the bright looks, and midway it was big both ways, so he
    /// ballooned for a moment (Aziz: "he just gets really big").
    @State private var floatUp: Double = 0
    @State private var holding = false
    @State private var progress: Double = 0
    @State private var done = false
    @State private var shown = false

    /// How long a full hold takes, and how fast he sinks if let go.
    private static let holdSeconds: Double = 3.2
    private static let sinkSeconds: Double = 1.4
    /// He climbs in the aura's own steps of five, one look at a time.
    private static let steps = 10

    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let success = UINotificationFeedbackGenerator()

    /// How far up he has come, 0 at Steady and 1 at Nirvana.
    private var rise: Double { max(0, min(1, (level - 50) / 50)) }

    private func setLevel(_ new: Double) {
        level = new
        withAnimation(.easeInOut(duration: 0.6)) { floatUp = max(0, min(1, (new - 50) / 50)) }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let ottoSize = min(size.width * 0.46, size.height * 0.24)
            let stoneY = size.height * 0.705
            ZStack {
                MoonLake(glow: done ? 1 : rise, ripples: holding || done,
                         stoneY: stoneY, stoneWidth: ottoSize * 0.95,
                         reduceMotion: reduceMotion)

                OttoAuraFigure(stage: OttoAura.Stage(level: Int(level)),
                               look: OttoAura.look(level: Int(level)),
                               size: ottoSize, rig: rig, snap: true)
                    .frame(width: ottoSize, height: ottoSize)
                    .position(x: size.width / 2,
                              y: stoneY - ottoSize * 0.06 - ottoSize / 2)
                    .offset(y: -CGFloat(floatUp) * size.height * 0.08)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            VStack(spacing: 12) {
                Text(done ? "Let's go!" : "Ready to take\ncontrol?")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .id(done)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                Text(done ? "You're committed and ready.\nThe first step is often the hardest."
                          : "Hold the button to help\nOtto ascend!")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .id("sub\(done)")
                    .transition(.opacity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .padding(.horizontal, AppMetrics.screenPadding + 4)
            .padding(.top, 44)
            .frame(maxWidth: .infinity)
            .opacity(shown ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: done)
        }
        .safeAreaInset(edge: .bottom) {
            ZStack {
                if done {
                    OnboardingCTA(title: "Continue", action: onContinue)
                        .padding(.horizontal, AppMetrics.screenPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    holdButton
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(height: 130, alignment: .bottom)
            .padding(.bottom, 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: done)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { shown = true }
            impact.prepare()
        }
        .task { await run() }
        // The dark status bar is unreadable on a night sky, and onboarding
        // pins light, so this one immersive screen hides it.
        .statusBarHidden(true)
    }

    /// Otto's head in a white button, the ring filling as he climbs.
    private var holdButton: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.3), lineWidth: 7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color(red: 1, green: 0.9, blue: 0.62),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(red: 1, green: 0.85, blue: 0.5).opacity(0.7), radius: 6)
            Circle()
                .fill(.white)
                .padding(13)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            Image("OttoHead")
                .resizable()
                .scaledToFit()
                .padding(30)
        }
        .frame(width: 124, height: 124)
        .scaleEffect(holding ? 0.93 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: holding)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !holding { holding = true; impact.impactOccurred(intensity: 0.6) } }
            .onEnded { _ in holding = false })
        .accessibilityElement()
        .accessibilityLabel("Hold to help Otto ascend")
        .accessibilityAddTraits(.isButton)
        // VoiceOver cannot press and hold: a double tap finishes it.
        .accessibilityAction { progress = 1 }
    }

    private func run() async {
        var lastStep = 0
        var last = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date(); let dt = now.timeIntervalSince(last); last = now
            guard !done else { continue }
            if holding {
                progress = min(1, progress + dt / Self.holdSeconds)
            } else if progress > 0 {
                progress = max(0, progress - dt / Self.sinkSeconds)
            }
            let step = Int((progress * Double(Self.steps)).rounded(.down))
            if step != lastStep {
                setLevel(50 + Double(step) * 50 / Double(Self.steps))
                if step > lastStep {
                    impact.impactOccurred(intensity: 0.35 + 0.6 * progress)
                    impact.prepare()
                }
                lastStep = step
            }
            if progress >= 1 {
                setLevel(100)
                holding = false
                success.notificationOccurred(.success)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { done = true }
            }
        }
    }
}

/// A lake at dusk under a big moon: the ascend screen's own place. Deep
/// indigo sky warming to a band of light at the horizon, two misty ridges,
/// still water with the moon's reflection, a flat stone for Otto, and rings
/// spreading from the stone. `glow` (0 to 1) brightens the moon and its
/// reflection as he rises.
private struct MoonLake: View {
    let glow: Double
    let ripples: Bool
    let stoneY: CGFloat
    let stoneWidth: CGFloat
    let reduceMotion: Bool

    private static let skyTop = Color(red: 0.12, green: 0.18, blue: 0.32)
    private static let skyMid = Color(red: 0.26, green: 0.36, blue: 0.55)
    private static let skyLow = Color(red: 0.62, green: 0.60, blue: 0.72)
    private static let horizon = Color(red: 0.93, green: 0.79, blue: 0.66)
    private static let farRidge = Color(red: 0.36, green: 0.42, blue: 0.58)
    private static let nearRidge = Color(red: 0.22, green: 0.28, blue: 0.43)
    private static let waterTop = Color(red: 0.25, green: 0.33, blue: 0.50)
    private static let waterLow = Color(red: 0.10, green: 0.15, blue: 0.27)
    private static let moon = Color(red: 0.99, green: 0.95, blue: 0.84)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let horizonY = h * 0.60
            let moonD = w * 0.58
            let moonY = h * 0.455
            ZStack {
                LinearGradient(stops: [.init(color: Self.skyTop, location: 0),
                                       .init(color: Self.skyMid, location: 0.34),
                                       .init(color: Self.skyLow, location: 0.52),
                                       .init(color: Self.horizon, location: 0.60)],
                               startPoint: .top, endPoint: .bottom)

                // The moon, and the light around it, growing with him.
                Circle()
                    .fill(RadialGradient(colors: [Self.moon.opacity(0.55 + 0.4 * glow), Self.moon.opacity(0)],
                                         center: .center, startRadius: moonD * 0.4,
                                         endRadius: moonD * (0.75 + 0.45 * glow)))
                    .frame(width: moonD * 2.4, height: moonD * 2.4)
                    .position(x: w / 2, y: moonY)
                Circle()
                    .fill(Self.moon.opacity(0.78 + 0.22 * glow))
                    .frame(width: moonD, height: moonD)
                    .position(x: w / 2, y: moonY)

                // Two ridges in the mist.
                Ridge(peaks: [0.0: 0.55, 0.18: 0.38, 0.4: 0.62, 0.62: 0.3, 0.85: 0.5, 1.0: 0.4])
                    .fill(Self.farRidge.opacity(0.75))
                    .frame(width: w, height: h * 0.1)
                    .position(x: w / 2, y: horizonY - h * 0.05)
                Ridge(peaks: [0.0: 0.3, 0.25: 0.7, 0.5: 0.5, 0.72: 0.8, 1.0: 0.35])
                    .fill(Self.nearRidge)
                    .frame(width: w, height: h * 0.06)
                    .position(x: w / 2, y: horizonY - h * 0.03)
                LinearGradient(colors: [Self.horizon.opacity(0), Self.horizon.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.06)
                    .position(x: w / 2, y: horizonY - h * 0.03)

                // Still water.
                LinearGradient(colors: [Self.waterTop, Self.waterLow], startPoint: .top, endPoint: .bottom)
                    .frame(height: h - horizonY)
                    .position(x: w / 2, y: horizonY + (h - horizonY) / 2)
                // Where the hills meet the water: a soft line of moonlight.
                LinearGradient(colors: [Self.moon.opacity(0), Self.moon.opacity(0.45 + 0.3 * glow), Self.moon.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: w, height: 2)
                    .blur(radius: 1)
                    .position(x: w / 2, y: horizonY)
                // The moon on the water: broken bands of light.
                Canvas { ctx, size in
                    // A soft column, brightest at the horizon.
                    let col = CGRect(x: size.width / 2 - moonD * 0.28, y: 0,
                                     width: moonD * 0.56, height: size.height)
                    ctx.fill(Path(ellipseIn: col),
                             with: .linearGradient(Gradient(colors: [Self.moon.opacity(0.32 + 0.3 * glow),
                                                                     Self.moon.opacity(0)]),
                                                   startPoint: CGPoint(x: col.midX, y: 0),
                                                   endPoint: CGPoint(x: col.midX, y: size.height * 0.8)))
                    // Glints on the surface, fading with distance from the
                    // horizon.
                    for i in 0..<9 {
                        let t = Double(i) / 8
                        let y = size.height * (0.04 + 0.34 * t * t + 0.02 * t)
                        let bw = moonD * (0.5 - 0.22 * t) * (i.isMultiple(of: 2) ? 1 : 0.62)
                        let rect = CGRect(x: size.width / 2 - bw / 2, y: y, width: bw, height: 2)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                                 with: .color(Self.moon.opacity((0.35 + 0.35 * glow) * (1 - t))))
                    }
                }
                .blur(radius: 1.2)
                .frame(width: w, height: h - horizonY)
                .position(x: w / 2, y: horizonY + (h - horizonY) / 2)

                // Rings on the water around his stone.
                TimelineView(.animation(paused: !ripples || reduceMotion)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        guard ripples else { return }
                        for k in 0..<3 {
                            let phase = (t / 2.6 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                            let rw = stoneWidth * (1.0 + 1.6 * phase)
                            let rect = CGRect(x: size.width / 2 - rw / 2, y: stoneY - rw * 0.08,
                                              width: rw, height: rw * 0.16)
                            ctx.stroke(Path(ellipseIn: rect),
                                       with: .color(Self.moon.opacity(0.5 * (1 - phase))), lineWidth: 1.5)
                        }
                    }
                }

                // His stone: flat, dark, lit along its top.
                ZStack {
                    Ellipse().fill(Color(red: 0.14, green: 0.17, blue: 0.24))
                    Ellipse()
                        .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.47, blue: 0.54), .clear],
                                             startPoint: .top, endPoint: .center))
                        .padding(.horizontal, stoneWidth * 0.06)
                }
                .frame(width: stoneWidth, height: stoneWidth * 0.2)
                .position(x: w / 2, y: stoneY)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A soft mountain line across its frame: `peaks` maps x (0 to 1) to the
/// height of the ridge there (0 bottom, 1 top), joined with smooth curves.
private struct Ridge: Shape {
    let peaks: [Double: Double]

    func path(in rect: CGRect) -> Path {
        let pts = peaks.sorted { $0.key < $1.key }
            .map { CGPoint(x: rect.minX + rect.width * $0.key, y: rect.maxY - rect.height * $0.value) }
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: pts[0])
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            p.addQuadCurve(to: mid, control: a)
            p.addQuadCurve(to: b, control: b)
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
