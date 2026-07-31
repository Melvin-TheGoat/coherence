import SwiftUI

/// Shared visual language on top of `AppColor` (the only color source). Typography
/// leans on the rounded system face for a calm, premium feel; spacing + component
/// modifiers keep every screen cohesive. Compiles into both apps.

enum AppMetrics {
    static let screenPadding: CGFloat = 20
    static let gap: CGFloat = 16
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 18
}

enum AppFont {
    static let hero = Font.system(size: 40, weight: .bold, design: .rounded)
    static let title = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout)
    /// Reading size for user-written text (session notes, and later, comments) —
    /// a step down from callout so a long note stays comfortable at full width.
    static let note = Font.system(.subheadline)
    static let caption = Font.system(.caption)
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
            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
    func card(padding: CGFloat = AppMetrics.cardPadding) -> some View { modifier(CardStyle(padding: padding)) }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.headline)
            .foregroundStyle(AppColor.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColor.accentGold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.callout.weight(.medium))
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Small components

/// A small uppercase section label.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(AppColor.textSecondary)
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
                .foregroundStyle(AppColor.accentGold)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
