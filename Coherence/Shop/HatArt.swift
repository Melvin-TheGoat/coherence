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
    /// Recut 2026-09-28 (Melvin: "white space, messed up cropping" under
    /// every brim but the flower crown's): the tool now keeps only what looks
    /// like the hat over his head, draws its own soft shadow under one clean
    /// edge, and cuts the halo to its ring. The flower crown keeps its first
    /// cut. The horns are gone.
    static let placement: [String: CGRect] = [
        "beanie":      CGRect(x: 146.9, y: -28.9, width: 368.0, height: 263.2),
        "sunhat":      CGRect(x: 83.6, y: 9.1, width: 490.4, height: 267.4),
        "bucket":      CGRect(x: 119.5, y: 14.7, width: 426.4, height: 247.7),
        "flowercrown": CGRect(x: 124.4, y: 34.4, width: 404.6, height: 218.1),
        "monkhat":     CGRect(x: 85.0, y: 15.4, width: 489.0, height: 239.2),
        "leafcrown":   CGRect(x: 131.5, y: 52.0, width: 401.1, height: 169.6),
        "wanderer":    CGRect(x: 82.6, y: 9.6, width: 497.3, height: 243.0),
        "enso":        CGRect(x: 82.6, y: -2.4, width: 497.3, height: 252.2),
        "wizardhat":   CGRect(x: 93.2, y: -49.0, width: 479.7, height: 320.0),
        "goldcrown":   CGRect(x: 175.9, y: -38.4, width: 310.8, height: 177.3),
        "halo":        CGRect(x: 211.9, y: -13.0, width: 238.1, height: 66.4),
    ]

    /// Steady's head in the same units, where every box above was measured
    /// from (`tools/otto_head_measure.swift` on `OttoAura4`): the top of his
    /// skull under the tuft, its centre, and its width.
    static let steadyHead = (skull: CGFloat(86), cx: CGFloat(330.5), width: CGFloat(341))

    /// How much higher each hat sits on each of the thirteen looks than his
    /// skull alone would put it, in these same Steady units (Melvin,
    /// 2026-09-28: at the bright looks "the hats start to cover [the brown
    /// around his eyes] and it looks like the hats are drooping down onto his
    /// face"). Those looks were drawn with a shorter forehead and bigger
    /// patches: their top sits 0.188 of his head's width below the skull at
    /// Steady and 0.100 at Nirvana.
    ///
    /// **Measured, per hat, by `tools/hat_lift.swift`**: along every column
    /// across his face, the gap from the hat's lowest point to the top of the
    /// patches; each look is raised until its closest gap matches Steady's
    /// (capped at 12, so a crown or the halo, far above his eyes, only has to
    /// stay off the patches), plus 3 from look 8 up, where the bigger patches
    /// run close to the brim along more of it. Never lowered, so the early
    /// looks keep the fit they were cut to. **`hat_extract --looks --lifts`
    /// must be given the same row, or each look's hidden-head mask sits in
    /// the wrong place.** A hat not listed is worn at its skull.
    static let faceLift: [String: [CGFloat]] = [
        "beanie": [0, 0, 0, 0, 0, 0, 0, 4.5, 8, 26, 16.5, 21.5, 24],
        "sunhat": [0, 0, 0, 0, 2, 0, 0, 10.5, 14.5, 11, 19, 17.5, 30.5],
        "bucket": [0, 0, 0, 0, 2, 0, 0, 9, 13, 10.5, 19, 23.5, 31],
        "flowercrown": [0, 0, 0, 0, 2, 0, 0, 10, 13, 17.5, 20.5, 17.5, 33],
        "monkhat": [0, 0, 0, 0, 2, 0, 0, 10, 14, 11.5, 19.5, 24, 32],
        "leafcrown": [0, 0, 0, 0, 0, 0, 0, 0, 0.5, 14, 6.5, 16.5, 17.5],
        "wanderer": [0, 0, 0, 0, 2, 0, 0, 10, 13.5, 11, 19.5, 24, 32.5],
        "enso": [0, 0, 0, 0, 1.5, 0, 0, 9, 13, 10.5, 18.5, 22, 31],
        "wizardhat": [0, 0, 0, 0, 1.5, 0, 0, 10, 14, 11, 18.5, 21, 30.5],
        "goldcrown": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2.5],
        "halo": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ]

    static func faceLift(_ id: String, look: Int) -> CGFloat {
        faceLift[id]?[min(max(look, 1), 13) - 1] ?? 0
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
