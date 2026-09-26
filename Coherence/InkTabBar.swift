import SwiftUI
import UIKit

/// Ink on paper: an ensō round a house, a river stone, a cairn of two
/// stones and a leaf, with the plus as a green brushed circle. A TEST
/// (Melvin, 2026-09-26: "Ooh try this one"), cut from his third ChatGPT
/// sheet (`Coherence/TabBar/ink-*.png`).
///
/// The selected tab stands in a pale blue watercolour wash and its label
/// turns blue, as the sheet draws it. There is ONE wash, lifted off the
/// sheet's selected Friends icon with the stones painted out, and each tab
/// shows it flipped or turned half round so no two look stamped. Only those
/// four poses: turned any other way the blob stands taller than the bar's
/// padding and pokes out over its top edge (seen on the first build).
///
/// The art was taken off the paper by un-mixing it from the paper's colour,
/// so a stroke is as see-through as the paint was. On the bar's paper that
/// reproduces the sheet, and over the wash the stones and the leaf darken
/// the way a glaze over blue does, which is how the sheet draws a selected
/// icon. Every icon is drawn at ONE scale (`artScale`), so they keep the
/// sizes the sheet gave them relative to one another.
struct InkTabBar: View {
    @Binding var selection: MainTab
    let onPlus: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            item(.home, art: "ink-home", label: "Home", wash: (0, false), tour: nil)
            item(.block, art: "ink-block", label: "Block", wash: (180, true), tour: .block)
            plus
            item(.friends, art: "ink-friends", label: "Friends", wash: (180, false), tour: .friends)
            item(.profile, art: "ink-profile", label: "Profile", wash: (0, true), tour: .profile)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(Self.paper)
                .overlay(Capsule(style: .continuous).stroke(Self.outline, lineWidth: 1.2))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        // Floats above the home indicator rather than sinking into it.
        .padding(.bottom, -Self.intoInset)
    }

    static let intoInset: CGFloat = 14
    /// Points per pixel of the sheet, the same for every icon.
    private static let artScale: CGFloat = 0.26
    /// The sheet's wash is about a quarter wider than the ensō it sits under.
    private static let washScale: CGFloat = 0.26
    private static let iconSlot: CGFloat = 40
    /// The sheet's colours, sampled: the bar's paper, its outline, and the
    /// two label inks.
    private static let paper = Color(red: 252 / 255, green: 245 / 255, blue: 235 / 255)
    private static let outline = Color(red: 216 / 255, green: 206 / 255, blue: 191 / 255)
    private static let ink = Color(red: 96 / 255, green: 86 / 255, blue: 72 / 255)
    private static let blue = Color(red: 12 / 255, green: 89 / 255, blue: 169 / 255)

    /// `wash` is the wash's pose under this tab: degrees turned, and mirrored.
    private func item(_ tab: MainTab, art name: String, label: String,
                      wash: (turn: Double, mirror: Bool), tour: TourTarget?) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    // Always laid out, so choosing a tab moves nothing.
                    art("ink-wash", scale: Self.washScale)
                        .rotationEffect(.degrees(wash.turn))
                        .scaleEffect(x: wash.mirror ? -1 : 1, y: 1)
                        .offset(y: -1)
                        .opacity(selected ? 1 : 0)
                        .scaleEffect(selected ? 1 : 0.82)
                    art(name, scale: Self.artScale)
                }
                .frame(height: Self.iconSlot)
                Text(label)
                    .font(.system(size: 12.5, weight: selected ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(selected ? Self.blue : Self.ink)
            }
            .frame(maxWidth: .infinity)
            .anchorPreference(key: TourTargetKey.self, value: .bounds) { anchor in
                tour.map { [$0: anchor] } ?? [:]
            }
            .contentShape(Rectangle())
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The sheet's green brushed circle with its white plus, a little larger
    /// than the icons and sitting inside the bar, not raised above it.
    private var plus: some View {
        Button(action: onPlus) {
            art("ink-plus", scale: 58 / 204)
        }
        .buttonStyle(.plain)
        .anchorPreference(key: TourTargetKey.self, value: .bounds) { [.begin: $0] }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Begin session")
    }

    /// A piece of the sheet at `scale` points per pixel. The PNGs carry no
    /// @2x suffix, so UIKit reports their size in pixels.
    @ViewBuilder
    private func art(_ name: String, scale: CGFloat) -> some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: image.size.width * scale, height: image.size.height * scale)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}
