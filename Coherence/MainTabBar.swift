import SwiftUI

/// How much of the bottom of the screen the tab bar covers, for pages PUSHED
/// inside a tab.
///
/// **The bar is a `safeAreaInset` on the tab's root, and that inset does not
/// reach a page pushed onto a NavigationStack inside the tab.** Measured on
/// the guide's method page (2026-09-22): its bottom inset read 34, the home
/// indicator alone, so a Begin button pinned to its bottom sat behind the
/// bar. The root screens never noticed because they scroll under the bar by
/// design. A pushed page that pins something to its bottom adds this.
private struct TabBarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var tabBarClearance: CGFloat {
        get { self[TabBarClearanceKey.self] }
        set { self[TabBarClearanceKey.self] = newValue }
    }
}

/// The five destinations.
enum MainTab: Hashable {
    /// `guide` is the tab only while Block is switched off; with Block on the
    /// guide lives in its circle under the streak on Home (2026-09-21).
    case home, guide, block, friends, profile
}

/// The bottom bar (2026-09-12, Melvin): the layout most apps use, so the app
/// is understood on sight. Four grey tabs and one raised gold plus in the
/// middle that starts a session. The plus is the single gold object on the
/// bar, which keeps the colour rule (one gold thing per section): selected
/// tabs read in the text colour, never gold.
struct MainTabBar: View {
    @Binding var selection: MainTab
    let onPlus: () -> Void

    /// New bars are under TEST (`TestTabBar`, 2026-09-25): chosen in
    /// Settings > Block (debug) > "Tab bar (test)", the newest by default,
    /// the classic bar with `CLASSIC_TAB_BAR=1`, and never in Release. They
    /// all draw the Block and Friends tabs, so they step aside when either
    /// flag is off.
    @AppStorage(TestTabBar.storageKey) private var testStyle = TestTabBar.debugDefault.rawValue

    private var style: TestTabBar {
        #if DEBUG
        guard FeatureFlags.block, FeatureFlags.friends,
              ProcessInfo.processInfo.environment["CLASSIC_TAB_BAR"] != "1" else { return .classic }
        return TestTabBar(rawValue: testStyle) ?? .debugDefault
        #else
        return .classic
        #endif
    }

    var body: some View {
        switch style {
        case .classic: classic
        case .meadow: MeadowTabBar(selection: $selection, onPlus: onPlus)
        case .lifted: LiftedTabBar(selection: $selection, onPlus: onPlus)
        case .ink: InkTabBar(selection: $selection, onPlus: onPlus)
        }
    }

    private var classic: some View {
        HStack(alignment: .top, spacing: 0) {
            item(.home, icon: "house", label: "Home")
            if FeatureFlags.block {
                // Block replaces the Guide tab (Melvin, 2026-09-21).
                item(.block, icon: "hand.raised", label: "Block", tour: .block)
            } else {
                item(.guide, icon: "book.closed", label: "Guide")
            }
            plus
            if FeatureFlags.friends {
                item(.friends, icon: "person.2", label: "Friends", tour: .friends)
            } else {
                item(.friends, icon: "magnifyingglass", label: "Search")
            }
            item(.profile, icon: "person.crop.circle", label: "Profile", tour: .profile)
        }
        // 12 over the icons and nothing under the labels: the home
        // indicator's own inset is the air below (Melvin, 2026-09-19: "the
        // bottom is raised slightly too high"). It was 6 until 2026-09-23
        // ("i actually like the height but the icons are slightly too high,
        // lower them"): the icons came down 6 and `intoInset` grew by the
        // same 6, so the bar itself did not change height.
        .padding(.top, 12)
        .background(
            AppColor.backgroundSecondary
                .overlay(alignment: .top) {
                    Rectangle().fill(AppColor.textSecondary.opacity(0.14)).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        // Down into the home indicator's inset, which is taller than the
        // indicator needs (Melvin, 2026-09-21, second time: "too much white
        // space below the icons, lower it"). Taking 6 off the top on
        // 2026-09-19 was not enough, because the air was never above the
        // icons, it was the inset under the labels. Brainrot's labels sit
        // about 39pt off the bottom edge; ours sat 55pt off it.
        .padding(.bottom, -Self.intoInset)
    }

    /// How far the bar sits down into the bottom safe area.
    static let intoInset: CGFloat = 22

    /// `tour` names the item for the onboarding tour, which lights it.
    private func item(_ tab: MainTab, icon: String, label: String,
                      tour: TourTarget? = nil) -> some View {
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
            // On the icon and its label, not the button's fifth of the bar,
            // which would light the neighbours and run off the screen's edge.
            .anchorPreference(key: TourTargetKey.self, value: .bounds) { anchor in
                tour.map { [$0: anchor] } ?? [:]
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
