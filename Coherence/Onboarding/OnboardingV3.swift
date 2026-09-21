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

/// One line from Otto, typed out, with the tail pointing down at him.
///
/// `speaking` is reported back so the screen can drive the rig: it turns true
/// with the first character and false with the last. Under Reduce Motion the
/// whole line is there at once and he says it with one short beat of mouth
/// movement, because a typewriter is motion and someone asked us not to.
struct OttoSpeech: View {
    let text: String
    /// A beat before he starts, so the wave reads as a greeting and the line
    /// as the thing he says after it.
    var delay: TimeInterval = 0
    @Binding var speaking: Bool

    @State private var shown = 0
    @State private var elapsed: TimeInterval = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// About thirty characters a second: fast enough not to be a wait, slow
    /// enough that the mouth has something to do.
    private static let tick: TimeInterval = 0.033

    private var visible: String { String(text.prefix(shown)) }

    var body: some View {
        // The full line, invisible, holds the bubble at its final size, so
        // nothing below it moves while the words arrive.
        Text(text)
            .font(AppFont.callout)
            .opacity(0)
            .overlay(alignment: .topLeading) {
                Text(visible)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColor.backgroundSecondary)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppColor.backgroundSecondary)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(45))
                    .offset(y: 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Otto says: \(text)")
            .onAppear {
                guard reduceMotion else { return }
                shown = text.count
                speaking = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { speaking = false }
            }
            .onReceive(Timer.publish(every: Self.tick, on: .main, in: .common).autoconnect()) { _ in
                guard !reduceMotion, shown < text.count else { return }
                elapsed += Self.tick
                guard elapsed >= delay else { return }
                if shown == 0 { speaking = true }
                shown += 1
                if shown == text.count { speaking = false }
            }
    }
}

/// Otto standing on his branch, drawn the full width of the screen so the
/// limb runs off both edges instead of ending in mid air.
///
/// The artboard is 425 x 522 and the rig view keeps those proportions, so a
/// full-bleed branch means a frame 483 pt tall on a 393 pt phone. Most of
/// that is empty sky above his head, so the view shows only the bottom
/// `height` of it. **That is why the branch state also shrinks him to 72%**:
/// the composition has to fit a window shorter than the artboard.
struct OttoOnBranch: View {
    var pose: OttoPose = .talking
    var talking: Bool = false
    /// How much of the drawing to show, measured up from the bottom.
    var height: CGFloat = 400
    @ObservedObject var rig: OttoRigHolder

    var body: some View {
        GeometryReader { geo in
            OttoRiveView(size: geo.size.width / OttoRig.aspect,
                         pose: pose,
                         talking: talking,
                         branch: true,
                         width: geo.size.width,
                         rig: rig)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                .clipped()
        }
        .frame(height: height)
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

            OttoSpeech(text: "I'm Otto. Your Watch reads what your practice does, and I read it back to you.",
                       delay: 1.4, speaking: $speaking)
                .padding(.top, 18)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 8)

            OttoOnBranch(pose: .talking, talking: speaking, height: 400, rig: rig)
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

    @StateObject private var rig = OttoRigHolder()
    @State private var appeared = false
    @State private var speaking = false

    var body: some View {
        VStack(spacing: 0) {
            OttoSpeech(text: "Before anything else, let's take three breaths together.",
                       delay: 0.5, speaking: $speaking)
                .padding(.top, 16)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 8)

            OttoOnBranch(pose: .meditating, talking: speaking, height: 400, rig: rig)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 0)
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
/// **He breathes from the chest, through the rig.** An earlier version had his
/// head climb the screen on the inhale, the way Headspace's orange half does,
/// and Melvin cut it on sight; the next one scaled his whole body 3.5 percent
/// from the feet, which reads as the picture zooming rather than a body
/// breathing, and Melvin's verdict was that he was not breathing at all. The
/// rig now carries a feathered cut of his chest as its own layer and swells
/// that (see `tools/otto_chest.py`), with the body barely moving under it.
///
/// A Continue appears after the first breath. Nobody is held in a breathing
/// exercise they did not want by a screen with no exit.
struct BreathingScreen: View {
    let onContinue: () -> Void

    /// Five in, five out.
    private static let half: TimeInterval = 5
    private static let breaths = 3

    @StateObject private var rig = OttoRigHolder()
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

            // The rig loops on its own clock; the words above ride the same
            // ten seconds. Over three breaths any drift between them is
            // smaller than the eye can hold.
            OttoOnBranch(pose: .meditating, height: 420, rig: rig)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            Group {
                if canContinue {
                    OnboardingCTA(title: "Continue", action: onContinue)
                } else {
                    Text("Follow along")
                        .font(OnboardingType.sub)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(height: 54)
                }
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 10)
            .animation(.easeOut(duration: 0.3), value: canContinue)
        }
        .onReceive(Timer.publish(every: Self.half, on: .main, in: .common).autoconnect()) { _ in
            advance()
        }
    }

    private func advance() {
        if inhaling {
            inhaling = false
            // One full breath is in and out, so the count and the exit both
            // move on the exhale.
            canContinue = true
        } else {
            if breath >= Self.breaths {
                onContinue()
                return
            }
            breath += 1
            inhaling = true
        }
    }
}

/// Screen 4. How many questions are coming, before a single one is asked.
///
/// Duolingo's move, and Melvin's ask (2026-09-20): a person who knows the
/// shape of what they are agreeing to finishes it. Ours is an interview that
/// branches, so the number is a CEILING, not a promise of exactly eight: the
/// model skips any question whose premise this reader has already
/// contradicted, which is why a newcomer is asked seven and everyone else
/// eight. "Eight at most" is the one number that is true for every path, and
/// the counter beside Otto on each question then reads N of THEIR total.
struct QuestionCountScreen: View {
    /// The largest number of questions any path is asked, from the model
    /// itself, so cutting or adding a question moves this line with it.
    static let most = OnboardingAnswers.longestInterview

    let onContinue: () -> Void

    @StateObject private var rig = OttoRigHolder()
    @State private var appeared = false
    @State private var speaking = false
    @State private var litPips = 0

    var body: some View {
        VStack(spacing: 0) {
            Text("First, a few questions")
                .font(OnboardingType.question)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)

            OttoSpeech(text: "\(Self.mostSpelled) at most, about a minute. Your answers decide what 808 shows you.",
                       delay: 0.5, speaking: $speaking)
                .padding(.top, 16)
                .opacity(appeared ? 1 : 0)

            HStack(spacing: 9) {
                ForEach(0..<Self.most, id: \.self) { i in
                    Circle()
                        .fill(i < litPips ? AppColor.accentGold : AppColor.textSecondary.opacity(0.22))
                        .frame(width: 11, height: 11)
                        .scaleEffect(i < litPips ? 1 : 0.8)
                }
            }
            .padding(.top, 22)
            .accessibilityHidden(true)

            Spacer(minLength: 8)

            OttoOnBranch(pose: .talking, talking: speaking, height: 360, rig: rig)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Let's go", action: onContinue)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            for i in 0..<Self.most {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(i) * 0.07) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { litPips = i + 1 }
                }
            }
        }
    }

    /// Numbers under ten are words in a spoken line.
    private static let mostSpelled: String = {
        let words = ["zero", "one", "two", "three", "four", "five",
                     "six", "seven", "eight", "nine", "ten"]
        let word = most < words.count ? words[most] : "\(most)"
        return word.prefix(1).uppercased() + word.dropFirst()
    }()
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
        Row(pose: .meditating, title: "Every session is measured.",
            detail: "Heart, stillness and breath, read from your wrist while you sit."),
        Row(pose: .awake, title: "You get a score you can trust.",
            detail: "Built from what your body did, with the working shown."),
        Row(pose: .talking, title: "It adds up.",
            detail: "A streak, a history, and friends who sit too."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Here's what's waiting")
                .font(OnboardingType.question)
                .foregroundStyle(AppColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

            VStack(spacing: 14) {
                ForEach(rows) { row in
                    HStack(alignment: .center, spacing: 14) {
                        OttoMark(size: 54, pose: row.pose)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColor.textPrimary)
                            Text(row.detail)
                                .font(OnboardingType.sub)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(AppColor.backgroundSecondary,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(.top, 26)

            Spacer(minLength: 0)
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
