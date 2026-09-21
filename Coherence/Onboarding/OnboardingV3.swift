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
        line[line.startIndex..<cut].foregroundColor = AppColor.textPrimary
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
                SpeechBubbleShape(edge: tail, tailWidth: 22, tailDepth: Self.tailSize)
                    .stroke(AppColor.textSecondary.opacity(0.4),
                            style: StrokeStyle(lineWidth: 2, lineJoin: .round))
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

/// Screen 2. The invitation, in his own voice, held for a moment before
/// anything is asked.
struct ThreeBreathsScreen: View {
    let onContinue: () -> Void
    /// Shared with `BreathingScreen`, which must put Otto in the same place.
    static let ottoGap: CGFloat = 20

    @StateObject private var rig = OttoRigHolder()
    @State private var appeared = false
    @State private var speaking = false

    var body: some View {
        VStack(spacing: 0) {
            OttoSpeech(text: "Before anything else, let's take three breaths together.",
                       speaking: $speaking)
                .padding(.top, 16)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 8)

            // Pinned just above the button, exactly where the breathing
            // screen pins him, so the fade between the two leaves him where
            // he is and only the words change.
            OttoOnBranch(pose: .meditating, talking: speaking, rig: rig)
                .padding(.bottom, Self.ottoGap)
                .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "I'm ready", action: onContinue)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
    }
}

/// Screen 3. Three breaths, paced, with Otto breathing beside the reader.
///
/// **Ten seconds a breath, five in and five out.** That is six a minute, the
/// pace the Watch orb breathes at and the pace the score's doorway is built
/// around, so the app breathes one way everywhere.
///
/// **He breathes with his torso, through the rig, and nothing else moves.**
/// Three tries got here. Scaling the whole body from the feet read as the
/// picture zooming; a feathered chest patch was too faint to see ("still not
/// breathing"); the body stretching plus the branch bobbing read as him
/// floating. The sitting pose now carries a 9 by 9 MESH in the rig, and the
/// Breathe timeline moves its vertices: the lap and hands stay planted, the
/// chest widens about ten percent, and the shoulders and head ride up a few
/// points on top of it. That is a deep breath, and the lap staying put is
/// what keeps it from reading as floating.
///
/// A Continue appears after the first breath. Nobody is held in a breathing
/// exercise they did not want by a screen with no exit.
struct BreathingScreen: View {
    let onContinue: () -> Void

    /// Five in, five out.
    private static let half: Duration = .seconds(5)
    private static let breaths = 3

    @StateObject private var rig = OttoRigHolder()
    /// The breath on the Taptic Engine: a swell in, a softer fall out, on the
    /// same ten seconds the rig and the words are on (Melvin, 2026-09-20:
    /// "turn on the breath haptic for the breathing screen"). Onboarding is
    /// one of the two places 808 buzzes at all, and this is the one where a
    /// pulse is the instruction rather than an interruption. **The simulator
    /// plays no haptics**, so this can only be judged on a phone.
    @State private var haptics = BreathHaptics()
    @State private var breath = 1
    @State private var inhaling = true
    @State private var canContinue = false

    var body: some View {
        VStack(spacing: 0) {
            Text(inhaling ? "Breathe in" : "Breathe out")
                .font(OnboardingType.question)
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: inhaling)
                .padding(.top, 8)

            Text("\(breath) of \(Self.breaths)")
                .font(OnboardingType.sub)
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
                .padding(.top, 6)

            Spacer(minLength: 8)

            // The rig loops on its own ten-second clock and the words ride
            // the same ten seconds. Over three breaths any drift between them
            // is smaller than the eye can hold.
            OttoOnBranch(pose: .meditating, rig: rig)
                .padding(.bottom, ThreeBreathsScreen.ottoGap)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            // The button is always laid out and only fades in. Swapping a
            // 54 pt line for the taller lifted button changed the inset's
            // height after the first breath, and every view above it shifted:
            // Otto, the branch, all of it, in one jump that read as him
            // floating.
            ZStack {
                OnboardingCTA(title: "Continue", action: onContinue)
                    .opacity(canContinue ? 1 : 0)
                    .allowsHitTesting(canContinue)
                if !canContinue {
                    Text("Follow along")
                        .font(OnboardingType.sub)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 10)
            .animation(.easeOut(duration: 0.3), value: canContinue)
        }
        // THE BREATHS RUN FROM ONE TASK. They used to advance on a
        // `Timer.publish` made inside `body`, which is rebuilt, and its
        // countdown restarted, every time the view redraws. The screen
        // redraws whenever onboarding's parent does, so the five-second tick
        // could be pushed back forever and the screen sat on its first
        // "Breathe in" (Melvin, 2026-09-21: "it doesnt progress past the
        // first breathe in"). A task belongs to the view's lifetime, is
        // cancelled when the screen goes, and cannot be reset by a redraw.
        .task {
            haptics.start()
            defer { haptics.stop() }
            for n in 1...Self.breaths {
                breath = n
                inhaling = true
                try? await Task.sleep(for: Self.half)
                guard !Task.isCancelled else { return }
                inhaling = false
                // One full breath is in and out; the way on appears once the
                // first one is under way.
                canContinue = true
                try? await Task.sleep(for: Self.half)
                guard !Task.isCancelled else { return }
            }
            onContinue()
        }
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
        Row(pose: .awake, title: "See how it went.",
            detail: "A score after every session, with the working shown."),
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
