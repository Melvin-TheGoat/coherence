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
    // ONE rounded family for everything, display and body alike. See
    // `DisplayFont` at the foot of this file for which family and why.
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

/// How far the tiles on a screen are dimmed for the scene behind them, 0 to
/// 1. Zero everywhere but Home, which follows the clock: its tiles are the
/// brightest thing on a night valley, so they dim a little as the sky goes
/// dark (Melvin, 2026-09-26: "the white stands out a lot very boldly").
private struct TileDimKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

extension EnvironmentValues {
    var tileDim: Double {
        get { self[TileDimKey.self] }
        set { self[TileDimKey.self] = newValue }
    }
}

/// A tile's surface: the sand of `backgroundSecondary`, darkened by the
/// screen's `tileDim`. Every tile draws through this, so a tile can never be
/// the one left glaring at night.
struct TileFill<S: Shape>: View {
    let shape: S
    var opacity: Double = 1
    @Environment(\.tileDim) private var dim

    var body: some View {
        shape.fill(AppColor.backgroundSecondary.opacity(opacity))
            .overlay(shape.fill(Color.black.opacity(dim * opacity)))
    }
}

private struct CardStyle: ViewModifier {
    var padding: CGFloat = AppMetrics.cardPadding
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                TileFill(shape: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
                    // Cards used to be separated from the ground by a hairline.
                    // On cream that reads as a drawn box; a 2pt bottom edge in
                    // a shade deeper than the card reads as a card resting on paper.
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
    /// Gold everywhere in the app; onboarding passes its green.
    var fill: Color = AppColor.accentGold
    var shade: Color = AppColor.accentGoldShade
    var ink: Color = AppColor.textOnAccent

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        let lift = down ? 1 : AppMetrics.buttonLift
        return configuration.label
            .font(AppFont.headline.weight(.bold))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous)
                    .fill(fill)
                    // A hard-edged shadow, not a blur: this is the side of the
                    // button, so it must have an edge.
                    .shadow(color: shade, radius: 0, y: lift)
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

/// **One rounded family everywhere, Duolingo's way** (Melvin, 2026-09-21:
/// "use their font everywhere, i think its DIN Next Rounded").
///
/// **What ships today is SF Pro Rounded, standing in for DIN Next Rounded.**
/// DIN Next Rounded is Monotype's, and putting a font inside an app needs an
/// app-embedding licence bought for that app; a desktop licence or an Adobe
/// Fonts activation does not cover it, and an unlicensed copy is not going in
/// a shipped binary. SF Pro Rounded is Apple's, ships on every iPhone, carries
/// every weight and language, scales with Dynamic Type, and is the closest
/// shape to DIN Next Rounded available without a licence: the same rounded
/// terminals on a plain grotesque skeleton.
///
/// **How it reaches everything:** display text comes through here, the body
/// sizes come through `AppFont`, and `CoherenceApp` sets `.fontDesign(.rounded)`
/// on the root so every other `.system(size:)` and every text style (`.body`,
/// `.caption`...) in the app resolves to the rounded design too.
///
/// **SUPERSEDED: Baloo 2** for display (Aziz, 2026-09-19, out of
/// `mockups/fonts.html`). Its TTFs and OFL are still in `Coherence/Fonts/` and
/// registered under `UIAppFonts`, unread, so going back is one line here.
///
/// **When the DIN Next Rounded app licence is bought:** add the files to
/// `Coherence/Fonts/`, list them under `UIAppFonts`, and return
/// `Font.custom(<PostScript name>, size:)` below and from `AppFont`. The root
/// `fontDesign` cannot carry a custom family, so the app's raw `.system(...)`
/// call sites (about two hundred) would move to `AppFont` in the same pass.
/// iOS only: the Watch keeps the system face.
enum DisplayFont {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
