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
                        // Brim on the box's floor, so `fit`'s sink is measured
                        // from where the hat actually meets his head.
                        .frame(width: size, height: size, alignment: .bottom)
                } else {
                    Self.placeholder(for: id)
                }
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Where it sits

    /// Each hat's box on Steady (the `OttoAura4` drawing, in its 664 x 744
    /// canvas units), where the hat was GENERATED on him (Melvin, 2026-09-27).
    /// Every hat was drawn onto `mockups/otto-hats/otto-reference.png` and cut
    /// back out by `tools/hat_extract.swift`, which printed these boxes, so a
    /// hat sits exactly where the picture of him wearing it put it. The first
    /// set were product shots placed by eye and read as pasted on his
    /// forehead. `OttoAuraFigure` carries a box from Steady onto every other
    /// look by where that look's head is.
    ///
    /// The horns are the one hat from the old sheet (Melvin liked them), so
    /// their box is set by eye to seat the band on his skull.
    static let placement: [String: CGRect] = [
        "beanie":      CGRect(x: 146.9, y: -28.9, width: 368.0, height: 275.8),
        "sunhat":      CGRect(x: 83.6, y: 15.4, width: 490.4, height: 261.7),
        "bucket":      CGRect(x: 119.5, y: 23.8, width: 426.4, height: 240.6),
        "horns":       CGRect(x: 172, y: -70, width: 318, height: 206),
        "flowercrown": CGRect(x: 124.4, y: 34.4, width: 404.6, height: 218.1),
        "monkhat":     CGRect(x: 85.0, y: 17.5, width: 489.0, height: 238.5),
        "leafcrown":   CGRect(x: 131.5, y: 33.0, width: 401.1, height: 218.1),
        "wanderer":    CGRect(x: 82.6, y: 9.6, width: 497.3, height: 245.8),
        "enso":        CGRect(x: 82.6, y: -2.4, width: 497.3, height: 255.0),
        "wizardhat":   CGRect(x: 93.2, y: -49.0, width: 479.7, height: 322.8),
        "goldcrown":   CGRect(x: 175.9, y: -38.4, width: 310.8, height: 180.8),
        "halo":        CGRect(x: 211.9, y: -13.0, width: 238.1, height: 70.6),
    ]

    /// Steady's head in the same units, where every box above was measured
    /// from (`tools/otto_head_measure.swift` on `OttoAura4`): the top of his
    /// skull under the tuft, its centre, and its width.
    static let steadyHead = (skull: CGFloat(86), cx: CGFloat(330.5), width: CGFloat(341))

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
