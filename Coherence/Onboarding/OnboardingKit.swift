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

/// The ground every onboarding screen sits on: near-black with a slow radial
/// wash in the section's colour, and a signal drifting across the lower third.
/// One modifier so no screen hand-rolls a background and drifts.
struct OnboardingBackground: ViewModifier {
    let section: OnboardingSection
    /// Off for the mechanism screen only. A second moving line next to a
    /// nervous-system claim starts to look like a live reading, and that
    /// screen's entire job is admitting we cannot take one.
    var ambient: Bool = true
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
                    if ambient {
                        AmbientSignal(tint: near)
                            .frame(height: 150)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 64)
                            .allowsHitTesting(false)
                    }
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
    func onboardingGround(_ section: OnboardingSection, ambient: Bool = true) -> some View {
        modifier(OnboardingBackground(section: section, ambient: ambient))
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
            Button(action: action) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        LinearGradient(colors: [AppColor.accentGold,
                                                AppColor.accentGold.opacity(0.82)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(PressReleaseHapticStyle())
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
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
    /// Two generators kept alive and PREPARED. A generator created on the
    /// tap and fired at once can miss: the Taptic Engine spins up in a few
    /// milliseconds and an unprepared request that arrives first is dropped.
    /// A tester on 2026-09-14 lost the pulse on some taps and not others,
    /// which is exactly that failure. Prepared generators fire every time.
    private static let press = UIImpactFeedbackGenerator(style: .heavy)
    private static let release = UIImpactFeedbackGenerator(style: .rigid)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onAppear {
                Self.press.prepare()
                Self.release.prepare()
            }
            .onChange(of: configuration.isPressed) { _, pressed in
                let gen = pressed ? Self.press : Self.release
                gen.impactOccurred(intensity: 1.0)
                gen.prepare()
            }
    }
}

struct OnboardingOption: View {
    let label: String
    var icon: String? = nil
    let selected: Bool
    /// Multi-select rows draw a square, single-select rows a circle: the
    /// convention every form uses, and the one cue that tells someone whether
    /// tapping a second answer will replace the first (2026-09-14 tester).
    var multi: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? AppColor.accentGold : AppColor.textSecondary)
                        .frame(width: 22)
                }
                Text(label)
                    .font(OnboardingType.option)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: selected ? (multi ? "checkmark.square.fill" : "checkmark.circle.fill")
                                           : (multi ? "square" : "circle"))
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? AppColor.accentGold
                                              : AppColor.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            // 18, not 15: the taller row is half of why a five-option screen
            // stopped looking like a list floating in a void.
            .padding(.vertical, 18)
            // Full-strength surface and a hairline. At 0.75 opacity the rows
            // bled into the ground (2026-09-14 tester: "too close in colour").
            .background(selected ? AppColor.accentGold.opacity(0.12)
                                 : AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(selected ? AppColor.accentGold : AppColor.textSecondary.opacity(0.22),
                        lineWidth: selected ? 1.5 : 1))
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
    /// See `OnboardingBackground.ambient`. Off for the mechanism screen only.
    var ambient: Bool = true
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
            // The chevron and the rail share one row, the way every flow with
            // both does it. The rail shifting right by the width of the arrow
            // is what stops the arrow looking like it was dropped on top.
            if back != nil || progress != nil || counter != nil {
                HStack(spacing: 10) {
                    if let back {
                        OnboardingBackButton(action: back)
                    }
                    if let counter {
                        OnboardingCounter(index: counter.index, total: counter.total)
                    } else if let progress {
                        OnboardingProgress(value: progress)
                    }
                }
                .frame(height: 40)
                .padding(.bottom, progress == nil && counter == nil ? 6 : 20)
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
                            .frame(maxHeight: 60)
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
        .onboardingGround(section, ambient: ambient)
        .onAppear { answeredOnAppear = autoAdvances && ctaEnabled }
    }
}

/// A thin rail, not a percentage — the count of screens is our business, not
/// something to make the user tally.
/// Where you are in the interview, as a count rather than a bar.
///
/// **It is honest per person.** The model skips every question whose premise
/// the reader has already contradicted, so `total` is THAT reader's total and
/// "3 of 7" means three of their seven. A bar cannot say that; it just creeps.
///
/// Otto breathes beside it at the same five second pace as everywhere else,
/// which is the only moving thing on a question screen (Melvin, 2026-09-20:
/// Otto breathing top-left through the questions).
struct OnboardingCounter: View {
    let index: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            OttoMark(size: 30, pose: .head)
                .ottoBreathing()
            Text("\(index) of \(total)")
                .font(OnboardingType.sub)
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Question \(index) of \(total)")
    }
}

struct OnboardingProgress: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.textSecondary.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: [AppColor.accentGold.opacity(0.7),
                                                  AppColor.accentGold],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * min(max(value, 0), 1)))
                    .animation(.easeOut(duration: 0.35), value: value)
            }
        }
        .frame(height: 4)
    }
}
