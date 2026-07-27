import SwiftUI

/// The 808 mark, rebuilt as clean vector line-art from Melvin's sketch: a
/// vertical figure-8 and a horizontal figure-8 that cross at the center (the "X"),
/// with the "O" ring over the crossing. Scalable + crisp; used as the home
/// wordmark and as the source geometry for the app icon.
struct LogoMark: View {
    var color: Color = AppColor.accentGold
    /// Stroke width as a fraction of the mark's size (keeps the weight consistent
    /// across sizes).
    var lineWidthRatio: CGFloat = 0.026

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            LogoMark.path(in: CGRect(x: (geo.size.width - s) / 2,
                                     y: (geo.size.height - s) / 2,
                                     width: s, height: s))
                .stroke(color, style: StrokeStyle(lineWidth: s * lineWidthRatio,
                                                  lineCap: .round, lineJoin: .round))
        }
    }

    /// Four round-ended petals (a vertical pair + a horizontal pair) overlapping
    /// through the center, plus the center O — the vertical "8", horizontal "8",
    /// and "O". Shared with the app-icon generator so they match exactly.
    static func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let w = s * 0.135         // petal half-width (narrow → each pair reads as an "8")
        let h = s * 0.205         // petal half-height (round-ended oval)
        let offset = s * 0.215    // petal center from middle; the pairs pinch at the waist
        let r0 = s * 0.150        // center O radius

        // Tune these with `swift tools/logo_lab.swift` — it renders the same
        // geometry to a PNG so you can sweep values without building the app.

        var p = Path()
        for dy in [-offset, offset] {   // top + bottom petals (tall ovals)
            p.addEllipse(in: CGRect(x: c.x - w, y: c.y + dy - h, width: 2 * w, height: 2 * h))
        }
        for dx in [-offset, offset] {   // left + right petals (wide ovals)
            p.addEllipse(in: CGRect(x: c.x + dx - h, y: c.y - w, width: 2 * h, height: 2 * w))
        }
        p.addEllipse(in: CGRect(x: c.x - r0, y: c.y - r0, width: 2 * r0, height: 2 * r0))
        return p
    }
}

#Preview {
    ZStack {
        AppColor.backgroundPrimary.ignoresSafeArea()
        LogoMark().frame(width: 160, height: 160)
    }
}
