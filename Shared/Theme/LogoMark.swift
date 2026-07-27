import SwiftUI

/// The 808 mark, rebuilt as clean vector line-art from Melvin's sketch: a
/// four-petal flower — a vertical "8" (top + bottom petals), a horizontal "8"
/// (left + right petals), and the "O" at the center. Scalable + crisp; used as the
/// home wordmark and as the source geometry for the app icon.
struct LogoMark: View {
    var color: Color = AppColor.accentGold
    var lineWidth: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            LogoMark.path(in: CGRect(x: (geo.size.width - s) / 2,
                                     y: (geo.size.height - s) / 2,
                                     width: s, height: s))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    /// Petal ellipses + center O, in the given square rect. Shared by the app-icon
    /// generator so the icon matches the in-app mark exactly.
    static func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let long = s * 0.40      // half-length along a petal's axis
        let short = s * 0.22     // half-width across a petal
        let offset = s * 0.21    // petal center distance from the middle
        let r0 = s * 0.145       // center O radius

        var p = Path()
        // Center O
        p.addEllipse(in: CGRect(x: c.x - r0, y: c.y - r0, width: 2 * r0, height: 2 * r0))
        // Top + bottom petals (tall ellipses)
        for dy in [-offset, offset] {
            p.addEllipse(in: CGRect(x: c.x - short, y: c.y + dy - long, width: 2 * short, height: 2 * long))
        }
        // Left + right petals (wide ellipses)
        for dx in [-offset, offset] {
            p.addEllipse(in: CGRect(x: c.x + dx - long, y: c.y - short, width: 2 * long, height: 2 * short))
        }
        return p
    }
}

#Preview {
    ZStack {
        AppColor.backgroundPrimary.ignoresSafeArea()
        LogoMark(lineWidth: 4).frame(width: 160, height: 160)
    }
}
