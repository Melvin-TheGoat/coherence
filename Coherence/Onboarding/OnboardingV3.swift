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
    /// The welcome screen's look (Aziz, 2026-09-23: "fully white and more
    /// bubble with a more welcoming font"): solid white, rounder, no outline,
    /// a soft shadow, and the rounded face in semibold. Off everywhere else,
    /// where Melvin's see-through Duolingo bubble stays.
    var friendly: Bool = false
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
            .font(.system(size: size, weight: friendly ? .semibold : .regular, design: .rounded))
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            // Hugs its words, the way Duo's does: a short line gets a short
            // bubble. The clear-ink layout means the width is the finished
            // line's from the first frame, so it never grows while typing.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, friendly ? 22 : 18)
            .padding(.vertical, friendly ? 18 : 15)
            // Room for the point inside the frame, so layout counts it.
            .padding(tail == .bottom ? .bottom : .leading, Self.tailSize)
            .background {
                if friendly {
                    SpeechBubbleShape(edge: tail, cornerRadius: 28, tailWidth: 24,
                                      tailDepth: Self.tailSize)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                } else {
                    let bubble = SpeechBubbleShape(edge: tail, tailWidth: 22,
                                                   tailDepth: Self.tailSize)
                    bubble.fill(fill)
                    bubble.stroke(stroke, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
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

/// Otto standing on the grass of the valley behind onboarding, with a soft
/// shadow under his feet.
///
/// **He used to stand on a branch** that ran off both edges of the screen,
/// and before the valley came in behind every screen that was what gave him
/// somewhere to be. Melvin, 2026-09-23: "get rid of the tree branch, i dont
/// like it". The meadow is the ground now, the same one Home sits him on.
///
/// The rig keeps its own proportions (425 x 522) and carries about a sixth
/// of empty sky above his tuft, so a frame whose height is `share` of the
/// width puts him at a steady size on every phone, standing on its bottom
/// edge.
struct OttoInMeadow: View {
    var pose: OttoPose = .talking
    var talking: Bool = false
    @ObservedObject var rig: OttoRigHolder
    /// His frame's height as a share of the width he is given.
    var share: CGFloat = 0.78
    /// The dark ellipse under his feet. Off on the welcome screen (Aziz,
    /// 2026-09-23), where he stands on the valley's own grass.
    var shadow: Bool = true

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                // Grounds him: without it a figure on grass reads as pasted on.
                if shadow {
                    Ellipse()
                        .fill(RadialGradient(colors: [Color.black.opacity(0.20), Color.black.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: h * 0.24))
                        .frame(width: h * 0.52, height: h * 0.075)
                        .offset(y: h * 0.025)
                }
                OttoRiveView(size: h, pose: pose, talking: talking, branch: false, rig: rig)
                    // The waving art carries his raised arm on the left, so
                    // his body sits right of the frame's centre; nudged back
                    // so HE is centred (Aziz, 2026-09-23).
                    .offset(x: pose == .talking ? -h * 0.06 : 0)
            }
            .frame(width: geo.size.width, height: h, alignment: .bottom)
        }
        .aspectRatio(1 / share, contentMode: .fit)
    }
}

/// Screen 1, Brainrot's welcome in 808's words (Aziz, 2026-09-23, from a
/// screenshot), standing in the valley. A generated clip, not the rig: the
/// rig's arm could only turn ten degrees, which never read as a wave. He waves
/// for as long as the screen is up ("constantly waving"): two waves played
/// forward then backward, so it turns and wraps while he is holding still and
/// never needs a blend (a crossfade loop ghosted his arm, the "phasing").
/// Cropped centred on his feet so his BODY is on the screen's centre line.
struct WelcomeScreen: View {
    let onContinue: () -> Void

    var body: some View {
        IntroScreen(progress: 0,
                    title: "Welcome to 808!",
                    subtitle: "It's time to regain control of your mind.",
                    cta: "Let's go!",
                    onContinue: onContinue) { playing in
            OttoClip(name: "otto-welcome-wave", playing: playing, loops: true)
                .aspectRatio(710.0 / 700.0, contentMode: .fit)
        }
    }
}

/// After the breath, Brainrot's "Meet your brain" in 808's words (Aziz,
/// 2026-09-23): Otto introduced as the reader's partner, in his middle mood,
/// Steady, the fourth of his seven. He is the aura figure Home draws, so he
/// breathes here the way he will there.
///
/// Two pages, one screen: Continue on the introduction changes only the
/// words to "The more you meditate, the more enlightened he becomes." (Brainrot's
/// "The more you brainrot" page, not typed, Aziz). Otto does not move between
/// them: the same Otto, now explained.
struct MeetOttoScreen: View {
    /// The second page (`Step.ottoGrows`).
    let grows: Bool
    let onContinue: () -> Void

    var body: some View {
        IntroScreen(progress: grows ? 0.07 : 0.04,
                    progressFrom: grows ? 0.04 : nil,
                    title: grows ? "The more you meditate, the more enlightened he becomes."
                                 : "Meet your meditating partner: Otto",
                    titleSize: grows ? 34 : 31,
                    subtitle: grows ? nil : "He's doing alright.",
                    cta: "Continue",
                    standing: false,
                    onContinue: onContinue) { _ in
            // Drawn by the valley itself (`OnboardingValley`, stage Steady),
            // on his cushion, where the stress screen and Home put him.
            EmptyView()
        }
    }
}

/// The Brainrot-shaped screen both of those are, standing in the valley
/// (Aziz, 2026-09-23: "back to that mountain outdoors background ... make
/// sure the depth is good and it looks natural"): the words in the sky, Otto
/// on the meadow, one button. It is a sequence, and every beat is felt:
///
/// 1. Otto fades in (no pop: Aziz) and the title arrives with him, not typed.
/// 2. What he says types out in his bubble above his head, a light tick per
///    letter.
/// 3. The button rises into place with a thump.
///
/// **Depth.** A standing Otto is placed in the SCENE's coordinates, his feet
/// on the ground line where the valley seats him on his cushion, scaled with
/// the scene (`SitLayout`), so he is exactly as far away as the sitting Otto
/// the reader meets next, and he stands on the very cushion he then sits on,
/// drawn where the valley draws it.
///
/// Reduce Motion gets the finished screen at once, with no ticks, and
/// `figure` is told not to play.
struct IntroScreen<Figure: View>: View {
    /// Where the progress bar stands: the questions fill it from here.
    let progress: Double
    /// Where it grows from, when a page moves it on.
    var progressFrom: Double? = nil
    let title: String
    var titleSize: CGFloat = 34
    /// What Otto says, typed into his bubble. Nil for a page that is the
    /// title alone.
    let subtitle: String?
    let cta: String
    /// True when `figure` is a standing Otto this screen places on the
    /// meadow; false when the valley draws him itself.
    var standing: Bool = true
    let onContinue: () -> Void
    /// Otto, handed whether he should be moving yet.
    @ViewBuilder let figure: (_ playing: Bool) -> Figure

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flips once: fades Otto and the title in and starts him moving.
    @State private var shown = false
    @State private var subtitleShown = 0
    @State private var ctaShown = false

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                let size = geo.size
                let scale = SitLayout.scale(in: size)
                // His own cushion, the one he sits on in the very next
                // screens, at exactly the size and place the valley draws it
                // (Aziz, 2026-09-23: "the same mat hes sitting on ...
                // consistent"). He stands on its top.
                let cushionCentre = SitLayout.cushionBottom(in: size) - 22 * scale
                let feet = cushionCentre + 2 * scale
                // A standing sloth is a head taller than the seated one (186
                // in the scene's units).
                let height = 222 * scale
                // The top of his head: the clip carries a few points of
                // margin above his tuft; the seated Otto is the valley's.
                let headTop = standing ? feet - height + 5 * scale : SitLayout.ottoTop(in: size)

                if standing {
                    Cushion()
                        .frame(width: 168 * scale, height: 44 * scale)
                        .position(x: size.width / 2, y: cushionCentre)
                        .standsInMeadow(feetY: SitLayout.cushionFront(in: size, scale: scale),
                                        scale: scale, sceneSize: size)
                        .opacity(shown ? 1 : 0)
                    figure(shown && !reduceMotion)
                        .frame(height: height)
                        .position(x: size.width / 2, y: feet - height / 2)
                        .opacity(shown ? 1 : 0)
                }

                // What he says, in his bubble just above his head (Aziz,
                // 2026-09-23: every typed line is Otto talking). It still
                // types a letter at a time with a tick each.
                if let subtitle {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        OttoSaysBubble(text: subtitle, shown: subtitleShown)
                            .frame(maxWidth: size.width - 72)
                    }
                    .frame(width: size.width, height: max(0, headTop - 6))
                    .position(x: size.width / 2, y: max(0, headTop - 6) / 2)
                    .opacity(shown ? 1 : 0)
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.3), value: subtitle)

            VStack(spacing: 0) {
                OnboardingProgress(from: progressFrom ?? progress, to: progress)
                    // A second page of one screen moves the bar instead of
                    // rebuilding it.
                    .id(progress)
                    .padding(.top, 12)
                    .padding(.horizontal, 8)

                // The words sit in the sky, over the ridge and well clear of
                // his head.
                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(shown ? 1 : 0)
                        // A new page of the same screen cross-fades its words.
                        .id(title)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.3), value: title)
                .padding(.horizontal, AppMetrics.screenPadding + 4)
                .padding(.top, 44)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: " "))
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: cta, action: onContinue)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
                .opacity(ctaShown ? 1 : 0)
                .offset(y: ctaShown ? 0 : 40)
                .allowsHitTesting(ctaShown)
        }
        .task { await play() }
    }

    private func play() async {
        guard !shown else { return }
        if reduceMotion {
            shown = true
            subtitleShown = subtitle?.count ?? 0
            ctaShown = true
            return
        }
        WelcomeHaptics.prepare()
        // A beat for the screen to be there before anything happens on it.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.35)) { shown = true }
        try? await Task.sleep(for: .milliseconds(450))

        if let subtitle {
            await type(subtitle, every: .milliseconds(28)) { subtitleShown = $0 }
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { ctaShown = true }
        WelcomeHaptics.land()
    }

    /// Reveals `text` a character at a time, a tick on every letter and none
    /// on the spaces, so the rhythm follows the words.
    private func type(_ text: String, every step: Duration, reveal: (Int) -> Void) async {
        for (i, ch) in text.enumerated() {
            guard !Task.isCancelled else { return }
            reveal(i + 1)
            if !ch.isWhitespace { WelcomeHaptics.tick() }
            try? await Task.sleep(for: step)
        }
    }
}

/// Otto's line in the welcome screens' bubble: white, round, the tail down
/// at his head, typed a letter at a time by the screen (so each letter can
/// tick). Unarrived letters are laid out in clear ink, so the bubble is its
/// finished size from the first frame and never grows while he talks.
private struct OttoSaysBubble: View {
    let text: String
    let shown: Int
    private static let tail: CGFloat = 11

    var body: some View {
        var line = AttributedString(text)
        let cut = line.index(line.startIndex, offsetByCharacters: min(max(shown, 0), text.count))
        line[line.startIndex..<cut].foregroundColor = AppColor.textPrimary
        line[cut..<line.endIndex].foregroundColor = .clear
        return Text(line)
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .padding(.bottom, Self.tail)
            .background {
                SpeechBubbleShape(edge: .bottom, cornerRadius: 26, tailWidth: 24, tailDepth: Self.tail)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            .accessibilityHidden(true)
    }
}

/// The welcome screen's haptics. Prepared generators, for the reason
/// `PressHaptic` gives: an unprepared one can drop the first pulses while the
/// Taptic Engine spins up, and a typed line would lose its opening letters.
@MainActor
enum WelcomeHaptics {
    private static let thump = UIImpactFeedbackGenerator(style: .medium)
    private static let soft = UIImpactFeedbackGenerator(style: .light)

    static func prepare() {
        thump.prepare(); soft.prepare()
    }
    static func land() {
        thump.impactOccurred(intensity: 0.9)
        thump.prepare()
    }
    /// A light tick for each typed letter.
    static func tick() {
        soft.impactOccurred(intensity: 0.55)
        soft.prepare()
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

    /// ONE breath, in 4, hold 2, out 4 (Aziz, 2026-09-23, from a reference
    /// screen: "only for one breath", `mockups/breath-one.html`). It was three
    /// 5 s breaths paced off Otto's rig. Otto is a clip timed to the same 4, 2, 4.
    static let inhale: Double = 4
    static let hold: Double = 2
    static let exhale: Double = 4
    private static var total: Double { inhale + hold + exhale }
    /// How high the water stands, as a share of the screen, at rest and full.
    /// Full is past the top (Aziz: "the water to go up all the way to the
    /// top"), so on the hold the whole screen is under it, waves and all.
    private static let low: CGFloat = 0.08
    private static let high: CGFloat = 1.08

    @State private var haptics = BreathHaptics()
    @State private var appeared = false
    @State private var finished = false
    /// When the breath began. Everything on screen reads its place off this
    /// one clock, so the water, Otto and the words can never disagree.
    @State private var breathStart: Date?

    init(breathing: Bool, onReady: @escaping () -> Void, onContinue: @escaping () -> Void) {
        self.breathing = breathing
        self.onReady = onReady
        self.onContinue = onContinue
    }

    var body: some View {
        TimelineView(.animation) { context in
            // Clamped: the first frame can be drawn a hair before the start,
            // and a negative time flashed "5 seconds" for one frame.
            let t = breathStart.map { max(0, context.date.timeIntervalSince($0)) }
            let fill = Self.fullness(at: t)
            ZStack {
                // White, like the reference (Aziz: "make it a white background").
                Color.white.ignoresSafeArea()
                BreathWater(level: Self.low + (Self.high - Self.low) * fill,
                            time: context.date.timeIntervalSinceReferenceDate)
                    .ignoresSafeArea()
                // Otto in the middle of the screen (Aziz), the words under him.
                // The clear block above matches the words below, so it is his
                // centre, not the pair's, that sits on the screen's.
                VStack(spacing: 14) {
                    Color.clear.frame(height: Self.wordsHeight)
                    // He guides the breath with his arms (Aziz, 2026-09-23): a
                    // Runway clip, cut to exactly 80 frames rising palms up,
                    // 40 held, 80 lowering palms down at 20 fps, which is this
                    // screen's 4, 2, 4. It starts on the same clock as the
                    // water and the words, and holds its last frame (his paws
                    // back on his knees) once the breath is done.
                    OttoClip(name: "otto-breath", playing: breathStart != nil, fallback: .meditating)
                        .aspectRatio(832.0 / 624.0, contentMode: .fit)
                        .frame(width: 380)
                        .opacity(appeared ? 1 : 0)
                    // Always laid out, empty or not: an empty slot took no
                    // height, and Otto jumped up the moment the words
                    // arrived (the "glitch when otto pops up").
                    ZStack(alignment: .top) {
                        Color.clear
                        words(at: t)
                    }
                    .frame(height: Self.wordsHeight)
                }
                .padding(.horizontal, AppMetrics.screenPadding)
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Only once the breath is done, and the slot is always laid out,
            // so nothing above it moves when it appears.
            OnboardingCTA(title: "Continue", action: onContinue)
                .opacity(finished ? 1 : 0)
                .allowsHitTesting(finished)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
        // Straight into the breath (Aziz: "no im ready button should j go
        // straight into it"). Once per visit, not per `breathing` flip.
        .task { await runBreath() }
        .onDisappear { haptics.stop() }
    }

    private static let wordsHeight: CGFloat = 70

    /// "Breathe in." over "3 seconds", counting down whole seconds.
    @ViewBuilder private func words(at t: Double?) -> some View {
        if finished {
            VStack(spacing: 6) {
                Text("Nicely done")
                    .font(OnboardingType.question)
                    .foregroundStyle(AppColor.textPrimary)
                Text("One slow breath")
                    .font(OnboardingType.sub.weight(.semibold))
                    .foregroundStyle(AppColor.skyDeep)
            }
        } else if let t {
            let (word, left) = Self.phase(at: t)
            VStack(spacing: 6) {
                Text(word)
                    .font(OnboardingType.question)
                    .foregroundStyle(AppColor.textPrimary)
                Text(left == 1 ? "1 second" : "\(left) seconds")
                    .font(OnboardingType.sub.weight(.semibold))
                    .foregroundStyle(AppColor.skyDeep)
                    .monospacedDigit()
            }
        }
    }

    private static func phase(at t: Double) -> (String, Int) {
        if t < inhale { return ("Breathe in.", max(1, Int((inhale - t).rounded(.up)))) }
        if t < inhale + hold { return ("Hold.", max(1, Int((inhale + hold - t).rounded(.up)))) }
        return ("Breathe out.", max(1, Int((total - t).rounded(.up))))
    }

    /// 0 at rest, 1 full: eased up over the inhale, still through the hold,
    /// eased down over the exhale.
    private static func fullness(at t: Double?) -> CGFloat {
        guard let t, t > 0 else { return 0 }
        func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
        if t < inhale { return CGFloat(ease(t / inhale)) }
        if t < inhale + hold { return 1 }
        if t < total { return CGFloat(1 - ease((t - inhale - hold) / exhale)) }
        return 0
    }

    private func runBreath() async {
        guard breathStart == nil, !finished else { return }
        // A beat for the screen to land before the water moves.
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        // Moves the flow on to `.breathing`, which is what resume and the
        // analytics count, without a button to press for it.
        if !breathing { onReady() }
        breathStart = Date()
        haptics.playOnce(inhale: Self.inhale, hold: Self.hold, exhale: Self.exhale)
        try? await Task.sleep(for: .milliseconds(Int(Self.total * 1000)))
        // A cancelled sleep throws and `try?` swallows it: without this the
        // screen would claim "Nicely done" the moment it was left.
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) { finished = true }
    }
}

/// Blue water rising from the bottom of the breath screen: three layers, each
/// with its own slow wave, so it moves like water rather than a bar filling.
/// `level` is how high it stands, as a share of the height.
struct BreathWater: View {
    let level: CGFloat
    let time: TimeInterval

    var body: some View {
        Canvas { ctx, size in
            let layers: [(opacity: Double, reach: CGFloat, phase: Double)] = [
                // Pale, like the reference, so the blue countdown still
                // reads on it: at 0.55 the front layer swallowed "1 second".
                (0.12, 1.0, 0), (0.18, 0.93, 1.7), (0.30, 0.86, 3.1)
            ]
            for (i, layer) in layers.enumerated() {
                let top = size.height * (1 - level * layer.reach) - CGFloat(i) * 9
                let amplitude = 11 + CGFloat(i) * 3
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                var x: CGFloat = 0
                while x <= size.width + 5 {
                    let across: Double = Double(x / size.width) * Double.pi * 1.8
                    let speed: Double = 0.7 + Double(i) * 0.2
                    let wave: Double = sin(across + time * speed + layer.phase)
                    path.addLine(to: CGPoint(x: x, y: top + CGFloat(wave) * amplitude))
                    x += 6
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                ctx.fill(path, with: .color(AppColor.skyDeep.opacity(layer.opacity)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

            OttoInMeadow(pose: .talking, talking: speaking, rig: rig)
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

/// **Otto's glow, in your hands** (Melvin, 2026-09-22: "instead of just
/// telling you that otto gets worse as you dont meditate, it SHOWS you, with
/// a scrolling bar, you can scroll horizontally and it makes him grow weaker
/// or stronger for the user to see for themselves").
///
/// It replaced two screens that described the app in words. The rule it sets
/// for every screen that sells something: **hand them the thing, do not
/// describe it.** Here the whole mechanic (sit and he brightens, skip and he
/// fades) is learned by dragging a bar for three seconds, and the caption
/// says what each position costs in days, which is the actual rule in
/// `OttoAura`.
struct AuraDemoScreen: View {
    let onContinue: () -> Void

    @State private var level: Double = 40
    @State private var demoed = false
    @StateObject private var rig = OttoRigHolder()

    private var stage: OttoAura.Stage { OttoAura.Stage(level: Int(level.rounded())) }

    /// What this much glow means in days, from the rule itself: everyone
    /// starts at 40, a day meditated adds 10, a day missed takes 20.
    private var caption: String {
        switch Int(level.rounded()) {
        case 90...:  return "Five days in a row"
        case 70..<90: return "Three or four days in a row"
        case 50..<70: return "A session or two"
        case 40..<50: return "Where everyone starts"
        case 20..<40: return "A day missed"
        default:      return "A few days missed"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            Text("I get brighter every day you meditate")
                .font(OnboardingType.question)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text("See for yourself. Drag the bar.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 6)

            OttoAuraFigure(stage: stage, size: 200, rig: rig)
                .frame(height: 210)
                .padding(.top, 18)
                .animation(.easeOut(duration: 0.18), value: stage)

            Text(caption)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 10)
                .contentTransition(.opacity)

            scrubber
                .padding(.top, 14)
                .padding(.horizontal, 6)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Continue", action: onContinue)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        // It moves itself once, so the bar is discovered rather than
        // explained. A caption saying "this is draggable" would be the very
        // thing this screen exists to stop doing.
        .task {
            guard !demoed else { return }
            demoed = true
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeInOut(duration: 1.1)) { level = 96 }
            try? await Task.sleep(for: .milliseconds(1250))
            withAnimation(.easeInOut(duration: 1.3)) { level = 6 }
            try? await Task.sleep(for: .milliseconds(1450))
            withAnimation(.easeInOut(duration: 0.8)) { level = 40 }
        }
    }

    /// The glow bar from Home, made draggable: the same object in the same
    /// colours, so what is learned here is recognised there.
    private var scrubber: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = max(0, min(width, width * level / 100))
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.trace)
                Capsule()
                    .fill(LinearGradient(colors: [AppColor.auraGlow, AppColor.auraRing],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(18, x))
                Circle()
                    .fill(AppColor.backgroundPrimary)
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .overlay(Circle().strokeBorder(AppColor.auraRing, lineWidth: 2))
                    .offset(x: max(0, min(width - 30, x - 15)))
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                level = max(0, min(100, value.location.x / width * 100))
            })
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel("Otto's glow")
        .accessibilityValue(caption)
        .accessibilityAdjustableAction { direction in
            level = max(0, min(100, level + (direction == .increment ? 10 : -10)))
        }
    }
}

