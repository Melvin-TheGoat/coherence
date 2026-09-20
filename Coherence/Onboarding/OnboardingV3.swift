import SwiftUI

// The front of onboarding, rebuilt to the shape Melvin approved in
// `mockups/onboarding-v3.html` (2026-09-20): Headspace's opening in 808's
// words, with Otto carrying it instead of a progress bar.
//
// Three screens land before the first question. They exist because the
// analytics say the interview is not where people leave: sixteen strangers
// reached the first screen in thirty days and twelve left on the second. The
// opening has to earn the questions, and a character doing something is a
// better argument than a sentence about measurement.

/// Screen 1. Otto waves once, then settles into his breath.
///
/// The wave is the Rive rig, fired on appear. When the rig is missing the
/// still pose stands in and the screen is merely quiet, never broken.
struct WelcomeScreen: View {
    let onContinue: () -> Void

    @StateObject private var rig = OttoRigHolder()
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            OttoRiveView(size: 200, pose: .talking, rig: rig)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            Text("Welcome to 808")
                .font(OnboardingType.question)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 26)
                .opacity(appeared ? 1 : 0)

            Text("Your Watch sees what your practice does. I'll read it back to you.")
                .font(OnboardingType.sub)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, 12)
                .opacity(appeared ? 1 : 0)

            Spacer()
            Spacer()
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

/// Screen 2. The invitation, held for a moment before anything is asked.
struct ThreeBreathsScreen: View {
    let onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            OttoMark(size: 150, pose: .meditating)
                .ottoBreathing()
                .opacity(appeared ? 1 : 0)

            Text("Let's take three\nbreaths together.")
                .font(OnboardingType.question)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)
                .opacity(appeared ? 1 : 0)

            Spacer()
            Spacer()
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
/// **Otto sits and breathes, through the Rive rig. Nothing rises.** An earlier
/// version had his head climb the screen on the inhale, the way Headspace's
/// orange half does, and Melvin cut it on sight; a second one pulsed a still
/// PNG, which is a picture being scaled rather than a character breathing.
/// This is the rig's own `Breathe` state, and the rig's timeline was stretched
/// to ten seconds so it breathes at six a minute here, on Home, and on the
/// Watch orb. One pace everywhere, which is what the copy has always claimed.
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
    @State private var swollen = false
    @State private var canContinue = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(inhaling ? "Breathe in" : "Breathe out")
                .font(OnboardingType.question)
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: inhaling)

            Text("\(breath) of \(Self.breaths)")
                .font(OnboardingType.sub)
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
                .padding(.top, 6)

            // The rig loops on its own clock; the words below ride the same
            // ten seconds. Over three breaths any drift between them is
            // smaller than the eye can hold.
            OttoRiveView(size: 230, pose: .meditating, rig: rig)
                .padding(.top, 34)

            Spacer()
            Spacer()
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
        .onAppear { startInhale() }
        .onReceive(Timer.publish(every: Self.half, on: .main, in: .common).autoconnect()) { _ in
            advance()
        }
    }

    private func startInhale() {
        inhaling = true
        withAnimation(.easeInOut(duration: Self.half)) { swollen = true }
    }

    private func advance() {
        if inhaling {
            inhaling = false
            withAnimation(.easeInOut(duration: Self.half)) { swollen = false }
            // One full breath is in and out, so the count and the exit both
            // move on the exhale.
            if breath >= 1 { canContinue = true }
        } else {
            if breath >= Self.breaths {
                onContinue()
                return
            }
            breath += 1
            startInhale()
        }
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
