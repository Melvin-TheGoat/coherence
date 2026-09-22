import SwiftUI

// The front of onboarding, rebuilt to the shape Melvin approved in
// `mockups/onboarding-v3.html` (2026-09-20): Headspace's opening in 808's
// words, with Otto carrying it instead of a progress bar.
//
// Four screens land before the first question. They exist because the
// analytics say the interview is not where people leave: sixteen strangers
// reached the first screen in thirty days and twelve left on the second. The
// opening has to earn the questions, and a character doing something is a
// better argument than a sentence about measurement.
//
// **Otto SAYS these lines; they are not printed beside him** (Melvin,
// 2026-09-20: "he also isnt even talking, make it seem like he is saying the
// stuff"). Every line he owns arrives in a bubble, typed a character at a
// time, with the rig's `talking` state on for exactly as long as the typing
// lasts, so his mouth and head move while the words appear and stop when they
// stop. A line that simply faded in would be text near a mascot.

// MARK: - Otto speaking

/// One line from Otto, typed out, in an outlined bubble whose tail points
/// down at him.
///
/// **The bubble is see-through, an outline and nothing else** (Melvin,
/// 2026-09-21, pointing at Duolingo's "Hi there! I'm Duo!"). A filled card
/// reads as a panel sitting on the screen; an outline on the screen's own
/// ground reads as words coming out of the character, which is the point.
/// The outline and the tail are ONE path (`SpeechBubbleShape`), so the line
/// runs unbroken down into the point instead of a rotated square being
/// tucked under a box.
///
/// **It types at about three hundred characters a second** (Melvin, same
/// message: "make the text appear like 10x quicker"). A two-line line lands
/// in about a quarter of a second, so it reads as arriving rather than as a
/// wait, and nobody taps Continue before the sentence is there.
///
/// **The words that have not arrived yet are laid out in clear ink.** That
/// keeps every line break exactly where the finished line will put it, so
/// centred text stays centred while it types and nothing below the bubble
/// moves. Revealing a growing prefix instead reflows the lines as they fill.
///
/// `speaking` is reported back so a screen can drive the rig while the line
/// types; the rig no longer draws anything for it (there is no mouth, by
/// Melvin's call), but the wiring stays so a future idea has somewhere to land.
/// Under Reduce Motion the whole line is there at once.
struct OttoSpeech: View {
    let text: String
    /// Which side the point is on: under the bubble when Otto stands below
    /// it, on its left when he stands beside it (the question screens).
    var tail: SpeechBubbleShape.Edge = .bottom
    var size: CGFloat = 19
    /// The ink and the outline. Defaulted to the page colours, so onboarding
    /// is unchanged; the session screens pass the valley's own ink, because
    /// Otto's warm brown on a blue sky reads as a different palette.
    var ink: Color = AppColor.textPrimary
    var stroke: Color = AppColor.textSecondary.opacity(0.4)
    /// What sits behind the words. Clear by default, which is Duolingo's
    /// bubble and is right over onboarding's flat ground. **A painted scene
    /// needs a fill**: on the session screen the morning sun rose straight
    /// through the glass and sat behind a word.
    var fill: Color = .clear
    /// A beat before he starts. Zero everywhere now: the welcome screen had
    /// 1.4 s so the line would follow the wave, and Melvin read it as a lag
    /// between the screen arriving and the words arriving (2026-09-21).
    var delay: TimeInterval = 0
    @Binding var speaking: Bool

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Five characters a frame at 60 frames a second: about 300 a second.
    private static let perTick = 5
    private static let tailSize: CGFloat = 11

    /// The line with its `**bold**` runs, parsed once.
    private var parsed: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private var total: Int { parsed.characters.count }

    private var typed: AttributedString {
        var line = parsed
        let cut = line.index(line.startIndex, offsetByCharacters: min(shown, total))
        line[line.startIndex..<cut].foregroundColor = ink
        line[cut..<line.endIndex].foregroundColor = .clear
        return line
    }

    var body: some View {
        Text(typed)
            .font(.system(size: size, weight: .regular, design: .rounded))
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            // Hugs its words, the way Duo's does: a short line gets a short
            // bubble. The clear-ink layout means the width is the finished
            // line's from the first frame, so it never grows while typing.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            // Room for the point inside the frame, so layout counts it.
            .padding(tail == .bottom ? .bottom : .leading, Self.tailSize)
            .background {
                let bubble = SpeechBubbleShape(edge: tail, tailWidth: 22,
                                               tailDepth: Self.tailSize)
                bubble.fill(fill)
                bubble.stroke(stroke, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Otto says: \(String(parsed.characters))")
            // A task, not a Timer built in `body`: a publisher made there is
            // made again on every redraw, and the resubscription restarts its
            // countdown, so a busy parent can starve it. That is exactly what
            // froze the breathing screen on its first "Breathe in".
            .task(id: text) {
                shown = 0
                if reduceMotion { shown = total; return }
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                }
                speaking = true
                while shown < total {
                    try? await Task.sleep(for: .milliseconds(16))
                    guard !Task.isCancelled else { speaking = false; return }
                    shown = min(total, shown + Self.perTick)
                }
                speaking = false
            }
    }
}

/// A rounded rectangle with a point, as one continuous outline, the way
/// Duolingo draws Duo's bubble. The point sits inside the shape's frame: the
/// body is the frame minus `tailDepth` on the point's side.
///
/// `.bottom` points down at a character standing under the bubble.
/// `.leading` points left at a character standing beside it, at the height of
/// his head rather than the bubble's middle, which is where a two-line
/// question would otherwise aim it.
struct SpeechBubbleShape: Shape {
    enum Edge { case bottom, leading }

    var edge: Edge = .bottom
    var cornerRadius: CGFloat = 16
    var tailWidth: CGFloat
    var tailDepth: CGFloat

    func path(in rect: CGRect) -> Path {
        let body: CGRect = edge == .bottom
            ? CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailDepth)
            : CGRect(x: rect.minX + tailDepth, y: rect.minY, width: rect.width - tailDepth, height: rect.height)
        let r = min(cornerRadius, body.height / 2, body.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.minY + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        if edge == .bottom {
            p.addLine(to: CGPoint(x: body.midX + tailWidth / 2, y: body.maxY))
            p.addLine(to: CGPoint(x: body.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: body.midX - tailWidth / 2, y: body.maxY))
        }
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        if edge == .leading {
            // Aim at the top third, where Otto's face is.
            let mid = min(body.minY + 34, body.midY)
            p.addLine(to: CGPoint(x: body.minX, y: mid + tailWidth / 2))
            p.addLine(to: CGPoint(x: rect.minX, y: mid))
            p.addLine(to: CGPoint(x: body.minX, y: mid - tailWidth / 2))
        }
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Otto standing on his branch, drawn the full width of the screen so the
/// limb runs off both edges instead of ending in mid air.
///
/// The artboard is 425 x 522 and the rig view keeps those proportions, so a
/// full-bleed frame is taller than the phone has room for, and most of that
/// height is empty sky above his head. So the view shows a window onto the
/// bottom of the drawing, and **the window's height is derived from the
/// width, never picked per screen.** It used to be a number per screen, and
/// 360 cut the top of his head off on the questions screen (Melvin,
/// 2026-09-21) while 400 shaved his tuft on the welcome screen.
///
/// The arithmetic: on the branch he is scaled to 72 percent with his feet at
/// artboard y 452, so the top of his head is at 452 - 0.72 x 507 = 87 of 522,
/// 16.7 percent down the drawing. The window keeps everything below 14
/// percent, which leaves a little air over his head on any phone width.
struct OttoOnBranch: View {
    var pose: OttoPose = .talking
    var talking: Bool = false
    @ObservedObject var rig: OttoRigHolder

    /// The share of the drawing's height kept, measured up from the bottom.
    private static let kept: CGFloat = 0.86

    var body: some View {
        GeometryReader { geo in
            let drawn = geo.size.width / OttoRig.aspect
            OttoRiveView(size: drawn,
                         pose: pose,
                         talking: talking,
                         branch: true,
                         width: geo.size.width,
                         rig: rig)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                .clipped()
        }
        // width / (width / aspect x kept) = aspect / kept
        .aspectRatio(OttoRig.aspect / Self.kept, contentMode: .fit)
        // Out past the screen padding, so the limb reaches both edges.
        .padding(.horizontal, -AppMetrics.screenPadding)
    }
}

/// Screen 1. Otto waves once, says hello, then settles into his breath.
struct WelcomeScreen: View {
    let onContinue: () -> Void

    @StateObject private var rig = OttoRigHolder()
    @State private var appeared = false
    @State private var speaking = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Welcome to 808")
                .font(OnboardingType.question)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)

            // Nothing Watch-specific (Melvin, 2026-09-21): 808 is becoming a
            // meditation app with friends and a camera session, not a
            // sensor readout, and the first thing Otto says should be true
            // of all of it.
            OttoSpeech(text: "Hi there! I'm Otto. Let's meditate together.",
                       speaking: $speaking)
                .padding(.top, 18)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 8)

            OttoOnBranch(pose: .talking, talking: speaking, rig: rig)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Get started", action: onContinue)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            // A beat, so the wave reads as a greeting rather than a twitch
            // that happened before the screen finished arriving.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { rig.wave() }
        }
    }
}

/// Screens 2 and 3 are ONE screen: the invitation, then the three breaths,
/// with nothing between them (Melvin, 2026-09-21, twice: "IT SHOULD JUST
/// START BREATHING, NO TRANSITION"). They were two screens joined by a slide,
/// then by a fade, and either way the screen changed under Otto when the
/// reader had just said they were ready. Now "I'm ready" changes the words
/// and starts his breath, and nothing else moves.
///
/// **His first inhale starts ON "I'm ready".** The rig's breath runs on its
/// own ten-second clock, so a reader who taps mid-cycle used to see "Breathe
/// in" over a chest that was already falling. Here the rig settles into the
/// sitting pose on the branch and is held still (`OttoRigHolder(
/// holdUntilReleased:)`); the tap releases it, and the words are paced from
/// where his breath actually is, never from a separate stopwatch.
///
/// **Three full breaths, then Continue.** A Continue after the first breath
/// read as the exercise ending after one ("it only happens ONCE and then the
/// continue button appears"), so the only button during the breaths is none.
///
/// Five in, five out: six a minute, the pace the rig, the haptic and the
/// Watch orb all share.
///
/// The router shows this for both `.breath` and `.breathing`, from ONE switch
/// case under ONE identity, so moving between the two steps (which keeps the
/// analytics funnel and resume records exactly as they were) redraws this view
/// rather than replacing it.
struct BreathExerciseScreen: View {
    /// True once the reader has said they are ready (`Step.breathing`).
    let breathing: Bool
    let onReady: () -> Void
    let onContinue: () -> Void

    private static let half: Double = 5
    private static let breaths = 3

    @StateObject private var rig: OttoRigHolder
    @State private var haptics = BreathHaptics()
    @State private var appeared = false
    @State private var speaking = false
    @State private var breath = 1
    @State private var inhaling = true
    @State private var finished = false
    /// When his current breath began, set the moment he is released. The
    /// circle reads its size off this clock, the same one the words run on.
    @State private var breathStart: Date?

    init(breathing: Bool, onReady: @escaping () -> Void, onContinue: @escaping () -> Void) {
        self.breathing = breathing
        self.onReady = onReady
        self.onContinue = onContinue
        // Resuming straight into the breaths has no invitation to wait on.
        _rig = StateObject(wrappedValue: OttoRigHolder(holdUntilReleased: !breathing))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(minHeight: 96, alignment: .top)
                .padding(.top, 8)

            Spacer(minLength: 0)

            // The pacer (Melvin: his chest alone "barely looks like hes
            // breathing"). Already there on the invitation, so I'm ready
            // adds nothing to the screen: the circle just starts to swell.
            BreathCircle(start: finished ? nil : breathStart)
                .frame(maxWidth: .infinity, maxHeight: BreathCircle.diameter)
                .padding(.bottom, 24)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 0)

            // Pinned above the button and never moved: the words change,
            // Otto does not. The top of his frame is empty sky, so it may
            // run up under the circle.
            OttoOnBranch(pose: .meditating, talking: speaking, rig: rig)
                .padding(.top, -60)
                .padding(.bottom, -8)
                .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            // One slot, one height, whatever sits in it. A slot that changes
            // height shifts every view above it, which is the jump that read
            // as Otto floating.
            ZStack {
                OnboardingCTA(title: "I'm ready", action: onReady)
                    .opacity(breathing ? 0 : 1)
                    .allowsHitTesting(!breathing)
                OnboardingCTA(title: "Continue", action: onContinue)
                    .opacity(finished ? 1 : 0)
                    .allowsHitTesting(finished)
                if breathing && !finished {
                    Text("Follow along")
                        .font(OnboardingType.sub)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 10)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
        .task(id: breathing) { await runBreaths() }
        .onDisappear { haptics.stop() }
    }

    @ViewBuilder private var header: some View {
        if !breathing {
            OttoSpeech(text: "Before anything else, let's take three breaths together.",
                       speaking: $speaking)
        } else if finished {
            VStack(spacing: 6) {
                Text("Nicely done")
                    .font(OnboardingType.question)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Three slow breaths")
                    .font(OnboardingType.sub)
                    .foregroundStyle(AppColor.textSecondary)
            }
        } else {
            VStack(spacing: 6) {
                Text(inhaling ? "Breathe in" : "Breathe out")
                    .font(OnboardingType.question)
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(breath) of \(Self.breaths)")
                    .font(OnboardingType.sub)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    /// The three breaths, paced from Otto's own breath.
    private func runBreaths() async {
        guard breathing else {
            breath = 1; inhaling = true; finished = false; breathStart = nil
            haptics.stop()
            return
        }
        // Where his breath is the moment he is released: about half a second
        // into an inhale when he was held on the invitation.
        var phase = rig.release()
        breathStart = Date().addingTimeInterval(-phase)
        haptics.start()
        defer { haptics.stop() }
        // If he happens to be breathing out, wait for his next inhale so the
        // words never contradict his chest.
        if phase >= Self.half {
            inhaling = false
            await pause(10 - phase)
            guard !Task.isCancelled else { return }
            phase = 0
        }
        for n in 1...Self.breaths {
            breath = n
            inhaling = true
            await pause(n == 1 ? Self.half - phase : Self.half)
            guard !Task.isCancelled else { return }
            inhaling = false
            await pause(Self.half)
            guard !Task.isCancelled else { return }
        }
        finished = true
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(max(0, seconds) * 1000)))
    }
}

/// The breathing circle from the old breath screen and the walkthrough: a
/// sage glow inside a sage ring, swelling on the inhale and settling on the
/// exhale. Its size is read off `start` every frame rather than animated, so
/// it can never drift from the words or from Otto's ten-second breath. With
/// no `start` it rests at its smallest.
struct BreathCircle: View {
    let start: Date?

    static let diameter: CGFloat = 180
    private static let period: Double = 10
    private static let rest: CGFloat = 0.5

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { context in
            GeometryReader { geo in
                let d = min(geo.size.width, geo.size.height, Self.diameter)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color.onboardingSage.opacity(0.55),
                                                      Color.onboardingSage.opacity(0.05)],
                                             center: .center, startRadius: 6, endRadius: d * 0.56))
                    Circle()
                        .stroke(Color.onboardingSage.opacity(0.45), lineWidth: 1.5)
                }
                .frame(width: d, height: d)
                .scaleEffect(scale(at: context.date))
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityHidden(true)
    }

    /// Smallest at the start of an inhale, largest five seconds in.
    private func scale(at now: Date) -> CGFloat {
        guard let start else { return Self.rest }
        let t = max(0, now.timeIntervalSince(start))
        let p = t.truncatingRemainder(dividingBy: Self.period) / Self.period
        let fill = 0.5 - 0.5 * cos(2 * .pi * p)
        return Self.rest + (1 - Self.rest) * CGFloat(fill)
    }
}

/// Screen 4. How many questions are coming, before a single one is asked.
///
/// **Duolingo's screen, nearly exactly** (Melvin, 2026-09-21, with its
/// screenshot): the back arrow, Otto's bubble, Otto under it, Continue. No
/// headline and no row of dots; the bubble is the whole screen.
///
/// The number is a CEILING that holds on every path: the interview skips any
/// question whose premise the reader has contradicted, so a newcomer answers
/// seven and everyone else eight, and "Just 8" is kept for both.
/// `OnboardingAnswers.longestInterview` derives it and a test pins that no
/// path exceeds it.
struct QuestionCountScreen: View {
    static let most = OnboardingAnswers.longestInterview

    let onContinue: () -> Void

    @Environment(\.onboardingBack) private var back
    @StateObject private var rig = OttoRigHolder()
    @State private var appeared = false
    @State private var speaking = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let back { OnboardingBackButton(action: back) }
                Spacer()
            }
            .frame(height: 40)

            Spacer(minLength: 12)

            OttoSpeech(text: "Just **\(Self.most) quick questions** before your first session!",
                       speaking: $speaking)
                .opacity(appeared ? 1 : 0)

            OttoOnBranch(pose: .talking, talking: speaking, rig: rig)
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", action: onContinue)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
    }
}

/// Screen 7. What the app is, once, before it asks for a notification.
///
/// Three lines, each a thing the app does rather than a thing it promises.
/// The rule from the copy notes holds: state the positive, and never set up
/// a loser for the line to beat.
struct WhatsWaitingScreen: View {
    let onContinue: () -> Void

    private struct Row: Identifiable {
        let id = UUID()
        let pose: OttoPose
        let title: String
        let detail: String
    }

    private let rows = [
        Row(pose: .meditating, title: "Meditate your way.",
            detail: "Guided sessions, calming sounds, or silence."),
        // Was "A score after every session", which stopped being true for
        // anyone without a Watch on 2026-09-21. Otto's glow is true for all.
        Row(pose: .awake, title: "Keep Otto glowing.",
            detail: "He glows brighter every day you meditate."),
        Row(pose: .talking, title: "Do it with friends.",
            detail: "A streak, your history, and friends who meditate too."),
    ]

    var body: some View {
        // The block sits in the middle of the screen with the headline on it,
        // not pinned to the top with the rest of the screen left empty
        // (Melvin, 2026-09-21: "three tiles at the top with a bunch of
        // whitespace below"). Bigger rows, bigger Otto in each, and the space
        // shared above and below.
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            Text("Here's what's waiting")
                .font(OnboardingType.question)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            VStack(spacing: 14) {
                ForEach(rows) { row in
                    HStack(alignment: .center, spacing: 16) {
                        OttoMark(size: 78, pose: row.pose)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColor.textPrimary)
                            Text(row.detail)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .background(AppColor.backgroundSecondary,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(.top, 28)

            Spacer(minLength: 16)
            Spacer(minLength: 16)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", action: onContinue)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
    }
}
