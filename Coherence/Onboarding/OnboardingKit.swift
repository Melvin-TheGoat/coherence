import SwiftUI

/// Shared chrome for the onboarding flow: the section colour arc, the
/// bottom-anchored CTA, option rows, and the progress rail.
///
/// The arc is the design's one structural idea (ONBOARDING.md): the ground
/// shifts warm amber → teal → deep red → gold as the flow moves from relief,
/// to the body entering, to what it's costing, to the win. Screens don't pick
/// colours; they declare which *section* they're in and the ground follows.

// MARK: - The colour arc

/// The interview's accent. Melvin picked sage over the app's teal for the
/// onboarding ground (2026-08-25, option B of mockups/onboarding-ground.html):
/// warmer and more inviting for a first meeting, while the app itself keeps
/// teal for the body's signals. Onboarding-only on purpose.
extension Color {
    static let onboardingSage = Color(red: 0.486, green: 0.659, blue: 0.431)
}

enum OnboardingSection {
    /// Screens 1–2. Blame comes off before any ask.
    case relief
    /// Screens 3–9. The interview; the body enters the story.
    case body
    /// Screens 10–12. The admission and what it's costing.
    case cost
    /// Screens 13–25. Proof, profile, projection, the offer.
    case win

    /// Two stops for the ground gradient, over the app's near-black.
    ///
    /// **The per-section colour arc is retired (Aziz, 2026-08-29).** The
    /// original decision (Melvin, 2026-08-05) ran amber → sage → red → gold as
    /// an emotional arc, and walking the finished flow the shifts read as the
    /// app changing its mind about its own identity rather than as staging.
    /// Every section now grounds in the same warm gold the app itself lives
    /// in. The section enum STAYS: screens still declare what they are, so an
    /// arc could return as a one-line change, and no screen hand-rolls a
    /// background.
    var glow: (Color, Color) {
        (AppColor.accentGold, Color(red: 0.42, green: 0.31, blue: 0.08))
    }
}

/// The ground every onboarding screen sits on: the app's paper with a slow
/// warm wash behind the top third. One modifier so no screen hand-rolls a
/// background and drifts.
///
/// **The drifting wave across the bottom is gone** (Melvin, 2026-09-21: "its
/// not on theme anymore"). It belonged to the dark, instrument-panel
/// onboarding, where a travelling signal said "measurement"; on a friendly
/// cream ground with a character on a branch it was a stray line.
/// `AmbientSignal` stays in this file for anything that wants it back.
struct OnboardingBackground: ViewModifier {
    let section: OnboardingSection
    @State private var breathe = false

    func body(content: Content) -> some View {
        let (near, far) = section.glow
        return content
            .background {
                ZStack {
                    AppColor.backgroundPrimary
                    RadialGradient(colors: [near.opacity(0.30), far.opacity(0.12), .clear],
                                   center: .init(x: 0.5, y: 0.28),
                                   startRadius: 8,
                                   endRadius: breathe ? 520 : 430)
                    .blur(radius: 42)
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.1), value: section)
            }
            .onAppear {
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
    }
}

extension View {
    func onboardingGround(_ section: OnboardingSection) -> some View {
        modifier(OnboardingBackground(section: section))
    }
}

/// Two slow waves travelling across the bottom of the screen, in the section's
/// colour at very low opacity.
///
/// This is decoration, and it is the only decoration in onboarding. It earns
/// its place by filling the dead band under short questions — five options
/// leave roughly 280 pt of black, and centring the block only halves that.
///
/// **It must never read as data.** No axis, no labels, no leading edge, no
/// cursor: it travels by exactly one period on a loop, which the eye reads as
/// pattern rather than a trace. It holds completely still under Reduce Motion.
struct AmbientSignal: View {
    let tint: Color
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One period in points. Translating by exactly this much loops seamlessly.
    private let period: CGFloat = 150

    var body: some View {
        ZStack {
            DriftWave(period: period, amplitude: 0.30, phase: 0)
                .stroke(tint.opacity(0.26), lineWidth: 2)
            DriftWave(period: period * 1.5, amplitude: 0.20, phase: .pi / 3)
                .stroke(tint.opacity(0.14), lineWidth: 1.5)
                .offset(y: 22)
        }
        .offset(x: drift ? -period * 3 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                drift = true
            }
        }
    }
}

/// A sine drawn far wider than the screen, so drifting never exposes an end.
private struct DriftWave: Shape {
    let period: CGFloat
    /// Fraction of the rect's height, peak to centre.
    let amplitude: CGFloat
    let phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        let amp = rect.height * amplitude
        let end = rect.width + period * 3
        p.move(to: CGPoint(x: 0, y: mid - sin(phase) * amp))
        var x: CGFloat = 2
        while x <= end {
            let y = mid - sin(x / period * 2 * .pi + phase) * amp
            p.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        return p
    }
}

// MARK: - Type

enum OnboardingType {
    static let headline = Font.system(size: 32, weight: .bold, design: .rounded)
    static let question = Font.system(size: 27, weight: .bold, design: .rounded)
    static let sub = Font.system(size: 16, weight: .regular)
    static let option = Font.system(size: 16, weight: .medium)
}

// MARK: - CTA

/// The primary action, always bottom-anchored in the thumb zone, always a
/// gradient (the flat-gold mock read as dull — the fix was motion through the
/// palette). `footnote` carries trial terms on their own line where needed.
struct OnboardingCTA: View {
    let title: String
    var footnote: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // The same lifted gold button as Create your profile (Melvin,
            // 2026-09-21: the buttons should look the way they do there), and
            // Duolingo's CONTINUE: a plate standing on its own edge that
            // sinks when pressed. The flat gradient it replaces was the one
            // button in the app that looked different.
            Button(action: action) { Text(title) }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!enabled)
                .saturation(enabled ? 1 : 0.2)
                .brightness(enabled ? 0 : -0.25)

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// `PrimaryButtonStyle`, plus the onboarding's press-and-release pulse.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle().makeBody(configuration: configuration)
            .onAppear { PressHaptic.prepare() }
            .onChange(of: configuration.isPressed) { _, pressed in
                PressHaptic.fire(pressed: pressed)
            }
    }
}

// MARK: - Options

/// One tappable answer. Tap advances where the screen allows it — no confirm
/// button, which is most of why the reference flow feels like a game.
/// The double pulse Melvin approved, split across the physical gesture
/// (2026-08-25): touch-down fires the first hit, letting go fires the second.
/// UIKit generators rather than .sensoryFeedback because SwiftUI's trigger
/// fires on state change, and press state never changes for a cancelled tap.
struct PressReleaseHapticStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onAppear { PressHaptic.prepare() }
            .onChange(of: configuration.isPressed) { _, pressed in
                PressHaptic.fire(pressed: pressed)
            }
    }
}

/// Two generators kept alive and PREPARED. A generator created on the tap
/// and fired at once can miss: the Taptic Engine spins up in a few
/// milliseconds and an unprepared request that arrives first is dropped. A
/// tester on 2026-09-14 lost the pulse on some taps and not others, which is
/// exactly that failure. Prepared generators fire every time.
enum PressHaptic {
    private static let press = UIImpactFeedbackGenerator(style: .heavy)
    private static let release = UIImpactFeedbackGenerator(style: .rigid)

    static func prepare() {
        press.prepare()
        release.prepare()
    }

    static func fire(pressed: Bool) {
        let gen = pressed ? press : release
        gen.impactOccurred(intensity: 1.0)
        gen.prepare()
    }
}

struct OnboardingOption: View {
    let label: String
    var icon: String? = nil
    let selected: Bool
    /// Multi-select rows draw a square, because that is the one cue that says
    /// tapping a second answer adds rather than replaces (2026-09-14 tester).
    /// Single-select rows draw nothing: the whole row lights up when chosen.
    var multi: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(selected ? AppColor.accentGold : AppColor.textSecondary)
                        .frame(width: 24)
                }
                Text(label)
                    .font(AppFont.body.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if multi {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? AppColor.accentGold
                                                  : AppColor.textSecondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            // The same field as Create your profile (Melvin, 2026-09-21):
            // a white rounded plate on the paper with no outline, radius 12.
            // Chosen is the plate outlined in gold with a faint gold wash.
            .background(selected ? AppColor.accentGold.opacity(0.10)
                                 : AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppColor.accentGold, lineWidth: 2)
                }
            }
        }
        .buttonStyle(PressReleaseHapticStyle())
    }
}

// MARK: - Back

/// Going back, published through the environment rather than threaded as a
/// parameter. Twenty screens sit inside `OnboardingScreen`, and passing a
/// closure down twenty initialisers to draw one chevron would guarantee that
/// the twenty-first forgets it. `OnboardingView` sets this once; nil means
/// there is nowhere to go back to, and the chevron does not render.
private struct OnboardingBackKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var onboardingBack: (() -> Void)? {
        get { self[OnboardingBackKey.self] }
        set { self[OnboardingBackKey.self] = newValue }
    }
}

/// The top-left chevron. Sized to a 40 pt target rather than the glyph, since a
/// 17 pt arrow is well under the minimum anyone can reliably hit.
struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 40, height: 40, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel("Back")
    }
}

// MARK: - Auto-advance timing

enum OnboardingFlowTiming {
    /// How long the chosen answer stays on screen before the flow moves on.
    /// Long enough to see the tick land and feel the haptic, short enough that
    /// it never feels like waiting. Tuned by hand — below ~0.2 s the selection
    /// reads as a flicker, above ~0.5 s it reads as lag.
    static let selectionDwell: Duration = .milliseconds(320)
}

// MARK: - Screen scaffold

/// Every interview screen has the same bones: progress, a question, content,
/// and a bottom-anchored CTA. Centralised so 26 screens can't drift apart.
struct OnboardingScreen<Content: View>: View {
    let section: OnboardingSection
    var progress: Double? = nil
    /// The interview position, shown instead of the rail when present.
    var counter: InterviewCount? = nil
    var title: String
    var subtitle: String? = nil
    var ctaTitle: String = "Continue"
    var ctaFootnote: String? = nil
    var ctaEnabled: Bool = true
    /// Single-select questions advance on the answer tap and therefore show NO
    /// Continue button at all. Keeping a button next to tap-to-advance was
    /// worse than either choice alone: Aziz met it as a user and read the
    /// auto-advance as a bug, because a visible Continue implies the tap
    /// shouldn't have been enough. One interaction, one affordance.
    ///
    /// Multi-select and free-text screens keep a real Continue, because there
    /// the user decides when they're done.
    var autoAdvances: Bool = false
    /// The line shown in place of the CTA on auto-advancing screens. Overridable
    /// because one screen needs to say what is still missing.
    var autoAdvanceHint: String = "Tap an answer"
    /// Declining an ask, which is not the same as skipping a question and must
    /// never be labelled as though it were. No onboarding screen says "Skip"
    /// any more: a question you can skip shouldn't be asked, and the three
    /// screens that keep a second action are declining a system permission or
    /// money, not walking out of the flow. Each says what it actually declines.
    var skipTitle: String = "Not now"
    var onSkip: (() -> Void)? = nil
    let onContinue: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.onboardingBack) private var back
    /// Whether an answer was already ticked when this screen appeared. That
    /// only happens on the way BACK, and there the tap-to-advance model
    /// breaks down: the tick is already lit, so tapping it again is not an
    /// obvious move and "Tap an answer" reads as a contradiction (2026-09-14
    /// tester). A returning screen shows Continue; a fresh one keeps the
    /// single affordance Aziz asked for.
    @State private var answeredOnAppear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let counter {
                // THE QUESTION SCREENS ARE DUOLINGO'S (Melvin, 2026-09-21,
                // with its "What would you like to learn?" screenshot): the
                // back arrow and a progress bar share the top row, Otto
                // stands under the arrow with his clipboard, and the question
                // is HIS line, in his bubble, pointing at him. No "3 of 8"
                // and no subtitle: the bar says where you are and the
                // question says the rest.
                HStack(spacing: 14) {
                    if let back {
                        OnboardingBackButton(action: back)
                    }
                    OnboardingProgress(from: Double(counter.index - 1) / Double(max(counter.total, 1)),
                                       to: Double(counter.index) / Double(max(counter.total, 1)))
                }
                .frame(height: 40)

                HStack(alignment: .top, spacing: 8) {
                    // Still. He is asking, not performing; a pulsing figure
                    // beside a question read as fidgeting.
                    Image(OttoPose.asking.asset)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 124)
                        .accessibilityHidden(true)
                    OttoSpeech(text: title, tail: .leading, size: 19, speaking: .constant(false))
                        .padding(.top, 14)
                }
                .padding(.top, 14)
            } else {
                // The chevron and the rail share one row, the way every flow
                // with both does it.
                if back != nil || progress != nil {
                    HStack(spacing: 10) {
                        if let back {
                            OnboardingBackButton(action: back)
                        }
                        if let progress {
                            OnboardingProgress(from: progress, to: progress)
                        }
                    }
                    .frame(height: 40, alignment: .bottom)
                    .padding(.bottom, progress == nil ? 6 : 14)
                }

                Text(title)
                    .font(OnboardingType.question)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(OnboardingType.sub)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }

            // Content shorter than the band centres itself; longer content
            // still scrolls from the top exactly as before.
            //
            // This is the single fix for the flow's biggest visual problem.
            // The scaffold used to pin the question to the ceiling and the CTA
            // to the floor, so every screen's unused height fell out as one
            // black band directly above the button: 280 pt on a five-option
            // question, over 400 on the Watch gate. Splitting it above and
            // below turns absence into margin, and costs nothing.
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        // Deliberately NOT centred. True centring on a tall
                        // band just moves the void from under the content to
                        // above it, and divorces the answers from the question
                        // they belong to.
                        //
                        // A fixed cap, not a proportion. A proportional share
                        // reads well on a five-option list and badly on a thin
                        // screen, where a third of a very large slack strands
                        // the content in the middle with a gulf under the
                        // question. 60 pt is enough for the block to look
                        // placed; everything else falls to the bottom, where
                        // the ambient signal lives.
                        Spacer(minLength: 0)
                            // Under Otto's bubble the answers belong close,
                            // as they are under Duo's.
                            .frame(maxHeight: counter == nil ? 60 : 12)
                        content
                            .padding(.top, 22)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                // The bar sat on top of the option rows (2026-09-14 tester).
                .scrollIndicators(.hidden)
            }

            if autoAdvances && !answeredOnAppear {
                // No button: the answer IS the action. A quiet line keeps the
                // bottom from reading as unfinished and teaches the model once.
                Text(autoAdvanceHint)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
            } else {
                OnboardingCTA(title: ctaTitle, footnote: ctaFootnote,
                              enabled: ctaEnabled, action: onContinue)
                    .padding(.top, 10)
            }

            if let onSkip {
                Button(skipTitle, action: onSkip)
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onboardingGround(section)
        .onAppear { answeredOnAppear = autoAdvances && ctaEnabled }
    }
}

/// Duolingo's progress bar: a thick rounded track with the filled part
/// growing into it as you answer (Melvin, 2026-09-21). It replaced "3 of 8"
/// beside a corner Otto, which read as a form counting at you.
///
/// It opens at `from` (the questions already answered) and grows to `to`
/// (this one) as the screen arrives, so every question visibly moves it. The
/// fraction is of THIS reader's questions: the model skips any whose premise
/// they have contradicted, so the bar fills exactly at their last one.
struct OnboardingProgress: View {
    let from: Double
    let to: Double

    @State private var value: Double = 0

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.textSecondary.opacity(0.16))
                Capsule()
                    .fill(AppColor.accentGold)
                    // The lit strip along the top of the fill, which is what
                    // makes a flat bar read as a filled tube.
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(height: height * 0.22)
                            .padding(.horizontal, height * 0.45)
                            .padding(.top, height * 0.2)
                    }
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 14)
        .onAppear {
            value = from
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) { value = to }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((to * 100).rounded())) percent")
    }
}
