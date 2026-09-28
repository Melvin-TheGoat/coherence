import SwiftUI

/// One hat, drawn on a card or on Otto's head.
///
/// **No hat art exists yet.** Real art will land as loose PNGs,
/// `Coherence/Shop/Hats/hat-<id>.png`, which XcodeGen bundles automatically
/// the way every other loose resource under `Coherence/` already is. Until a
/// file is there for a given id, this draws a clean placeholder instead, so
/// the whole feature (browsing, buying, wearing) works today. `HatArt` is
/// the one place that decides real art from a placeholder, so nothing else
/// in the shop needs to know which hats have art yet.
struct HatArt: View {
    /// nil draws nothing (an empty head slot).
    let id: String?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let id {
                if let uiImage = UIImage(named: "hat-\(id)") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    Self.placeholder(for: id)
                }
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Placeholder

    /// A colour and, where a good one exists, an SF Symbol per hat, so the
    /// eight cards read as eight different things rather than one shape
    /// recoloured eight times. Colours route through `AppColor` like
    /// everywhere else — these are existing tokens borrowed for a
    /// placeholder, not new hex values.
    private struct Look {
        let color: Color
        /// nil draws the generic hat silhouette instead.
        let symbol: String?
    }

    private static func look(for id: String) -> Look {
        switch id {
        case "goldcrown":    return Look(color: AppColor.accentGold, symbol: "crown.fill")
        case "wizardhat":    return Look(color: AppColor.auraRing, symbol: "wand.and.stars")
        case "leafcrown":    return Look(color: AppColor.meadowInk, symbol: "leaf.fill")
        case "flowercrown":  return Look(color: AppColor.streakBlushText, symbol: "leaf.fill")
        case "sunhat":       return Look(color: AppColor.accentGoldText, symbol: "sun.max.fill")
        case "monkhat":      return Look(color: AppColor.textSecondary, symbol: nil)
        case "bucket":       return Look(color: AppColor.skyDeep, symbol: nil)
        default:             return Look(color: AppColor.calmAccent, symbol: nil)   // beanie, and anything future
        }
    }

    @ViewBuilder
    private static func placeholder(for id: String) -> some View {
        let look = look(for: id)
        if let symbol = look.symbol {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(look.color)
                .padding(6)
        } else {
            HatSilhouette()
                .fill(look.color)
                .padding(2)
        }
    }
}

/// A plain hat silhouette (a dome over a brim), for a hat with no better SF
/// Symbol to stand in for it. Not any particular hat; just unmistakably A
/// hat, which is what a placeholder needs to be.
private struct HatSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.width * 0.20, y: rect.height * 0.04,
                                   width: rect.width * 0.60, height: rect.height * 0.58))
        path.addEllipse(in: CGRect(x: 0, y: rect.height * 0.54,
                                   width: rect.width, height: rect.height * 0.20))
        return path
    }
}
