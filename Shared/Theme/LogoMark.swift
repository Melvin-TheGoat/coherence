import SwiftUI

/// The 808 mark, rebuilt as clean vector line-art from Melvin's sketch: a
/// vertical figure-8 and a horizontal figure-8 that cross at the center (the "X"),
/// with the "O" ring over the crossing. Scalable + crisp; used as the home
/// wordmark and as the source geometry for the app icon.
struct LogoMark: View {
    var color: Color = AppColor.accentGold
    /// Stroke width as a fraction of the mark's size (keeps the weight consistent
    /// across sizes).
    var lineWidthRatio: CGFloat = 0.045

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

    /// Two crossing figure-8s (Gerono lemniscates) + the center O, in the given
    /// square rect. Shared with the app-icon generator so they match exactly.
    static func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let a = s * 0.33          // half the length of each 8
        let k: CGFloat = 1.05     // lobe fatness
        let r0 = s * 0.085        // center O radius

        var p = Path()
        for vertical in [true, false] {
            let steps = 240
            for i in 0...steps {
                let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
                let along = a * cos(t)
                let across = a * k * sin(t) * cos(t)
                let pt = vertical
                    ? CGPoint(x: c.x + across, y: c.y + along)
                    : CGPoint(x: c.x + along, y: c.y + across)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
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
