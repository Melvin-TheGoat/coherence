import SwiftUI

/// The five destinations. Search is a placeholder until friends exist.
enum MainTab: Hashable {
    case home, guide, search, profile
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
            item(.search, icon: "magnifyingglass", label: "Search")
            item(.profile, icon: "person.crop.circle", label: "Profile")
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
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
        .offset(y: -18)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Begin session")
        .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.begin: $0] }
    }
}
