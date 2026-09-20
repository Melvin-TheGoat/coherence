import SwiftUI

/// The five destinations.
enum MainTab: Hashable {
    case home, guide, friends, profile
}

/// The bottom bar (2026-09-12, Melvin): the layout most apps use, so the app
/// is understood on sight. Four grey tabs and one raised gold plus in the
/// middle that starts a session. The plus is the single gold object on the
/// bar, which keeps the colour rule (one gold thing per section): selected
/// tabs read in the text colour, never gold.
struct MainTabBar: View {
    @Binding var selection: MainTab
    let onPlus: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            item(.home, icon: "house", label: "Home")
            item(.guide, icon: "book.closed", label: "Guide")
                .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.guide: $0] }
            plus
            if FeatureFlags.friends {
                item(.friends, icon: "person.2", label: "Friends")
            } else {
                item(.friends, icon: "magnifyingglass", label: "Search")
            }
            item(.profile, icon: "person.crop.circle", label: "Profile")
        }
        // 6 over the icons and nothing under the labels: the home indicator's
        // own inset is the air below (Melvin, 2026-09-19: "the bottom is
        // raised slightly too high, too much white space at the bottom").
        .padding(.top, 6)
        .background(
            AppColor.backgroundSecondary
                .overlay(alignment: .top) {
                    Rectangle().fill(AppColor.textSecondary.opacity(0.14)).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ tab: MainTab, icon: String, label: String) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selected ? icon + ".fill" : icon)
                    .font(.system(size: 22, weight: .regular))
                    .frame(height: 26)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selected ? AppColor.textPrimary : AppColor.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Raised above the bar, the way the pattern is drawn everywhere else, so
    /// the thumb finds it without looking.
    private var plus: some View {
        Button(action: onPlus) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppColor.backgroundPrimary)
                .frame(width: 58, height: 58)
                .background(AppColor.accentGold, in: Circle())
                .shadow(color: AppColor.accentGold.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        // The tour's anchor sits on the circle, BEFORE the offset and the
        // full-width frame. It used to sit after both, so the spotlight was
        // the whole slot's width and 18pt lower than the drawn button: the
        // top of the plus was outside the lit window (Melvin, 2026-09-19:
        // "the plus is cut off").
        .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.begin: $0] }
        .offset(y: -18)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Begin session")
    }
}
