import SwiftUI
import UIKit

/// The tab bar styles under test (2026-09-25, Melvin), chosen in Settings >
/// Block (debug) > "Tab bar (test)". DEBUG only: Release always draws the
/// classic bar.
enum TestTabBar: String, CaseIterable, Identifiable {
    case classic, meadow, lifted, ink
    /// The newest bar opens first. The key's version goes up with each new
    /// style, so a phone that had picked an older one in Settings still
    /// shows the newest after the update.
    static let storageKey = "debug.tabBarStyle.v2"
    static let debugDefault = TestTabBar.ink
    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: return "Classic"
        case .meadow: return "Meadow"
        case .lifted: return "Lifted"
        case .ink: return "Ink"
        }
    }
}

/// A floating cream bar with a darker lip under it, Duolingo's pressable
/// look. A TEST (Melvin, 2026-09-25), from the ChatGPT sheet he made after
/// the meadow bar: a cottage, a gate, two sloths and a signpost, and the
/// plus as the onboarding buttons' green circle with a white plus.
///
/// The selected tab sits in a rounded square with a 2.5pt outline and a
/// light wash in its own colour, the sheet's colours: blue for Home, Block
/// and Profile, green for Friends. The plus is drawn in code, so it stays
/// crisp; the four objects are cut from the sheet
/// (`Coherence/TabBar/lifted-*.png`, about 200 px each).
struct LiftedTabBar: View {
    @Binding var selection: MainTab
    let onPlus: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            item(.home, art: "lifted-home", label: "Home", tint: .blue, tour: nil)
            item(.block, art: "lifted-block", label: "Block", tint: .blue, tour: .block)
            plus
            item(.friends, art: "lifted-friends", label: "Friends", tint: .green, tour: .friends)
            item(.profile, art: "lifted-profile", label: "Profile", tint: .blue, tour: .profile)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
            ZStack {
                // The lip: the same shape, darker, a few points lower.
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Self.lip)
                    .offset(y: 5)
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(AppColor.backgroundPrimary)
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Self.lip.opacity(0.7), lineWidth: 1))
            }
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        // Floats above the home indicator rather than sinking into it.
        .padding(.bottom, -Self.intoInset)
    }

    static let intoInset: CGFloat = 14
    private static let lip = Color(red: 0.90, green: 0.85, blue: 0.77)

    private enum Tint {
        case blue, green
        var stroke: Color { self == .blue ? AppColor.skyDeep : OnboardingGreen.shade }
        var wash: Color {
            self == .blue ? Color(red: 0.88, green: 0.94, blue: 0.99) : Color(red: 0.89, green: 0.96, blue: 0.87)
        }
    }

    private func item(_ tab: MainTab, art name: String, label: String, tint: Tint,
                      tour: TourTarget?) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                art(name)
                    .frame(height: 38)
                Text(label)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected ? tint.stroke : ValleyGround.ink.opacity(0.62))
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.wash)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.stroke, lineWidth: 2.5))
                    .opacity(selected ? 1 : 0)
                    .padding(.horizontal, 3)
            }
            .anchorPreference(key: TourTargetKey.self, value: .bounds) { anchor in
                tour.map { [$0: anchor] } ?? [:]
            }
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The onboarding button as a circle: green with a darker lip under it
    /// and a heavy white plus.
    private var plus: some View {
        Button(action: onPlus) {
            ZStack {
                Circle().fill(OnboardingGreen.shade).offset(y: 4)
                Circle().fill(OnboardingGreen.fill)
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
        .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.begin: $0] }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Begin session")
    }

    @ViewBuilder
    private func art(_ name: String) -> some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Color.clear
        }
    }
}
