import SwiftUI

/// Shared visual language on top of `AppColor` (the only color source). Spacing
/// and component modifiers keep every screen cohesive. Compiles into both apps.
///
/// **Rounded everywhere, no exceptions** (2026-09-19). The face used to be
/// rounded for display sizes and the plain system face for body, which is the
/// respectable choice and is exactly why the app read as technical: the type a
/// person actually spends their time reading was the same face as a settings
/// list. One line here does more for how friendly the app feels than any other
/// change in this pass, and it costs nothing.

enum AppMetrics {
    static let screenPadding: CGFloat = 20
    static let gap: CGFloat = 14
    /// Soft rather than merely rounded. At 22 a card reads as a panel; at 26 it
    /// reads as an object, which is the difference being asked for.
    static let cardRadius: CGFloat = 28
    static let cardPadding: CGFloat = 18
    static let buttonRadius: CGFloat = 20
    /// How far a primary button stands off its own shadow. Pressing it closes
    /// the gap, so the control behaves like something physical instead of
    /// fading out. The whole idea is one borrowed from Duolingo and it is the
    /// single most recognisable thing about a friendly interface.
    static let buttonLift: CGFloat = 4
}

enum AppFont {
    static let hero = Font.system(size: 40, weight: .bold, design: .rounded)
    static let title = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .rounded)
    static let callout = Font.system(.callout, design: .rounded)
    /// Reading size for user-written text (session notes, and later, comments) —
    /// a step down from callout so a long note stays comfortable at full width.
    static let note = Font.system(.subheadline, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
    static let statNumber = Font.system(size: 40, weight: .bold, design: .rounded)
}

// MARK: - Modifiers

private struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppColor.backgroundPrimary.ignoresSafeArea())
    }
}

private struct CardStyle: ViewModifier {
    var padding: CGFloat = AppMetrics.cardPadding
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                    .fill(AppColor.backgroundSecondary)
                    // Cards used to be separated from the ground by a hairline.
                    // On cream that reads as a drawn box; a 2pt bottom edge in
                    // the same warm tone reads as a card resting on paper.
                    .shadow(color: AppColor.hairline, radius: 0, y: 2)
            )
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
    func card(padding: CGFloat = AppMetrics.cardPadding) -> some View { modifier(CardStyle(padding: padding)) }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        let lift = down ? 1 : AppMetrics.buttonLift
        return configuration.label
            .font(AppFont.headline.weight(.bold))
            .foregroundStyle(AppColor.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous)
                    .fill(AppColor.accentGold)
                    // A hard-edged shadow, not a blur: this is the side of the
                    // button, so it must have an edge.
                    .shadow(color: AppColor.accentGoldShade, radius: 0, y: lift)
            )
            // Move with the edge, so the whole control sinks rather than the
            // label sliding off its own plate.
            .offset(y: AppMetrics.buttonLift - lift)
            .animation(.easeOut(duration: 0.12), value: down)
            .padding(.bottom, AppMetrics.buttonLift)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.callout.weight(.medium))
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Small components

/// A section label, in the voice a person uses.
///
/// It was UPPERCASE, TRACKED AND TINY (2026-09-19, Aziz: "I don't want it to
/// look super scientific"). Small caps with letter-spacing is the house style
/// of dashboards and lab reports, and a dozen of them down a screen is most of
/// why this app felt clinical: every label was shouting a field name. Sentence
/// case at a readable size reads as somebody talking, costs nothing, and is
/// legible to more people.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(AppFont.callout.weight(.bold))
            .foregroundStyle(AppColor.textPrimary)
    }
}

/// A labeled stat (big number + caption), for the summary card.
struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppFont.statNumber)
                .foregroundStyle(AppColor.accentGoldText)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
