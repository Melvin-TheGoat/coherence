import SwiftUI

/// Shared chrome for the onboarding flow: the section colour arc, the
/// bottom-anchored CTA, option rows, and the progress rail.
///
/// The arc is the design's one structural idea (ONBOARDING.md): the ground
/// shifts warm amber → teal → deep red → gold as the flow moves from relief,
/// to the body entering, to what it's costing, to the win. Screens don't pick
/// colours; they declare which *section* they're in and the ground follows.

// MARK: - The colour arc

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
    var glow: (Color, Color) {
        switch self {
        case .relief: return (Color(red: 0.85, green: 0.60, blue: 0.24), Color(red: 0.55, green: 0.33, blue: 0.12))
        case .body:   return (AppColor.calmAccent, Color(red: 0.16, green: 0.36, blue: 0.35))
        case .cost:   return (Color(red: 0.62, green: 0.18, blue: 0.16), Color(red: 0.32, green: 0.08, blue: 0.08))
        case .win:    return (AppColor.accentGold, Color(red: 0.42, green: 0.31, blue: 0.08))
        }
    }
}

/// The ground every onboarding screen sits on: near-black with a slow radial
/// wash in the section's colour. One modifier so no screen hand-rolls a
/// background and drifts.
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
            .buttonStyle(CardButtonStyle())
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
struct OnboardingOption: View {
    let label: String
    var icon: String? = nil
    let selected: Bool
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
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? AppColor.accentGold
                                              : AppColor.textSecondary.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(selected ? AppColor.accentGold.opacity(0.10)
                                 : AppColor.backgroundSecondary.opacity(0.75),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(selected ? AppColor.accentGold : .clear, lineWidth: 1.5))
        }
        .buttonStyle(CardButtonStyle())
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
    var onSkip: (() -> Void)? = nil
    let onContinue: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let progress {
                OnboardingProgress(value: progress)
                    .padding(.bottom, 26)
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

            ScrollView {
                content.padding(.top, 22).padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            if autoAdvances {
                // No button: the answer IS the action. A quiet line keeps the
                // bottom from reading as unfinished and teaches the model once.
                Text("Tap an answer")
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
                Button("Skip", action: onSkip)
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
    }
}

/// A thin rail, not a percentage — the count of screens is our business, not
/// something to make the user tally.
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
