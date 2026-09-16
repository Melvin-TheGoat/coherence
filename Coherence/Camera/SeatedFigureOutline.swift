import SwiftUI

/// A seated meditator in a few strokes: head, shoulders and arms resting on
/// the knees, the torso between them, crossed legs with the shins crossing.
/// Laid over the camera preview so a person can sit into it.
///
/// Drawn from paths in a 300 x 400 design box (3:4, the front camera's own
/// frame) and fitted, centred, into whatever rect it is given, so it scales
/// with the preview and takes any stroke colour. Line-art like the logo; no
/// image asset. The same numbers draw the SVG in
/// `mockups/camera-framing.html`; change them in both places.
struct SeatedFigureOutline: Shape {
    static let designSize = CGSize(width: 300, height: 400)

    func path(in rect: CGRect) -> Path {
        let d = Self.designSize
        let s = min(rect.width / d.width, rect.height / d.height)
        let ox = rect.minX + (rect.width - d.width * s) / 2
        let oy = rect.minY + (rect.height - d.height * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var path = Path()

        // Head.
        path.addEllipse(in: CGRect(x: ox + 116 * s, y: oy + 50 * s, width: 68 * s, height: 68 * s))

        // Left shoulder and arm, down to the hand resting on the knee.
        path.move(to: p(122, 146))
        path.addCurve(to: p(80, 166), control1: p(104, 148), control2: p(88, 154))
        path.addCurve(to: p(56, 262), control1: p(66, 190), control2: p(58, 226))
        path.addCurve(to: p(98, 310), control1: p(56, 280), control2: p(70, 298))

        // Collar, under the head.
        path.move(to: p(122, 146))
        path.addCurve(to: p(178, 146), control1: p(136, 138), control2: p(164, 138))

        // Right shoulder and arm.
        path.move(to: p(178, 146))
        path.addCurve(to: p(220, 166), control1: p(196, 148), control2: p(212, 154))
        path.addCurve(to: p(244, 262), control1: p(234, 190), control2: p(242, 226))
        path.addCurve(to: p(202, 310), control1: p(244, 280), control2: p(230, 298))

        // Torso, inside the arms.
        path.move(to: p(106, 180))
        path.addCurve(to: p(106, 304), control1: p(100, 220), control2: p(100, 262))
        path.move(to: p(194, 180))
        path.addCurve(to: p(194, 304), control1: p(200, 220), control2: p(200, 262))

        // Crossed legs: the lap, knee to knee.
        path.move(to: p(22, 338))
        path.addCurve(to: p(278, 338), control1: p(66, 300), control2: p(234, 300))
        path.addCurve(to: p(22, 338), control1: p(234, 382), control2: p(66, 382))
        path.closeSubpath()

        // The shins crossing.
        path.move(to: p(108, 366))
        path.addCurve(to: p(200, 326), control1: p(128, 350), control2: p(160, 336))
        path.move(to: p(192, 366))
        path.addCurve(to: p(100, 326), control1: p(172, 350), control2: p(140, 336))

        return path
    }
}

#Preview {
    ZStack {
        AppColor.backgroundSecondary.ignoresSafeArea()
        SeatedFigureOutline()
            .stroke(AppColor.cameraOverlay,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 240, height: 320)
    }
}
