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
    // The three display sizes are Baloo 2; everything under them is SF
    // Rounded. See `DisplayFont` at the foot of this file for why the line is
    // drawn where it is.
    static let hero = DisplayFont.display(40, .heavy)
    static let title = DisplayFont.display(24)
    static let headline = DisplayFont.display(17)
    static let body = Font.system(.body, design: .rounded)
    static let callout = Font.system(.callout, design: .rounded)
    /// Reading size for user-written text (session notes, and later, comments) —
    /// a step down from callout so a long note stays comfortable at full width.
    static let note = Font.system(.subheadline, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
    static let statNumber = DisplayFont.display(40, .heavy)
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
            .font(DisplayFont.display(17))
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

/// A capsule that fits its own words.
///
/// The third button shape, and the one for actions that sit beside each other
/// under something rather than at the bottom of a screen: Edit profile, Share
/// profile. `SecondaryButtonStyle` stretches to full width, which is right at
/// the foot of a sheet and wrong under a portrait, where two full-width slabs
/// turn a profile into a settings screen.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.callout.weight(.bold))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(AppColor.backgroundSecondary)
                    .shadow(color: AppColor.hairline, radius: 0, y: 2)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - The display face

/// **Baloo 2 for the big text, SF Rounded for everything small** (Aziz,
/// 2026-09-19, choosing it out of `mockups/fonts.html`).
///
/// The problem it solves is that SF Rounded is the correct first move for a
/// friendly iOS app and is also what every friendly iOS app reaches for, so
/// 808 sounded like all of them. Baloo 2 is chunky, warm and unmistakable, and
/// it matches the shapes the rest of this redesign is made of.
///
/// **It is deliberately not used below about fifteen points**, and that is the
/// whole design of this type:
///
/// - SF is hinted for these screens at small sizes and a bundled web face is
///   not. Baloo's lowercase in particular gets loose and a little wild small,
///   which is charming in a headline and costs legibility in a stat label.
/// - SF carries every weight and every language the app ships in. Three
///   bundled TTFs carry three weights of Latin.
/// - SF scales with Dynamic Type for free. A fixed-size custom face does not,
///   so every string set in Baloo has to be one whose layout can survive
///   growing, which headlines can and dense rows cannot.
///
/// So the rule is: **a display face has a personality where there is room for
/// one.** Headlines, the score, the big numbers. Nothing a person reads a
/// paragraph of.
///
/// Registered in `Coherence/Info.plist` under `UIAppFonts`; the files and the
/// SIL Open Font License live in `Coherence/Fonts/`. iOS only: the Watch
/// target has its own palette and its own sizes and stays on the system face.
enum DisplayFont {
    /// PostScript names, which are what `Font.custom` wants and are NOT the
    /// family names: the 800 weight's family is "Baloo 2 ExtraBold" while its
    /// PostScript name is "Baloo2-ExtraBold". Getting this wrong fails silently
    /// to the system font, which looks like a layout bug rather than a missing
    /// file.
    private static let semibold = "Baloo2-SemiBold"
    private static let bold = "Baloo2-Bold"
    private static let extrabold = "Baloo2-ExtraBold"

    /// Baloo sits small in its own box, so a size here reads roughly a point
    /// under the same size in SF. The 1.06 makes the two interchangeable at a
    /// call site without every caller having to know that.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        let name: String
        switch weight {
        case .semibold, .medium, .regular: name = semibold
        case .black, .heavy: name = extrabold
        default: name = bold
        }
        return .custom(name, fixedSize: size * 1.06)
    }
}
