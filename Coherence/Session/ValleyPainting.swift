import SwiftUI

// THE VALLEY'S PAINTING, in its own file since 2026-10-06 so the home screen
// widget (OttoWidget/) can compile it beside the app, the way it already
// compiles `DayLight`. Melvin approved the widget as "the app's valley"
// (`mockups/widget-v2.html`, direction 1): the same ridges, the same meadow
// and flowers, the same haze and cushion, lit for the same hour. A copy of
// these in the widget would drift the first time anyone touched the app's.
//
// Everything here is painting only: no Rive, no birds, no state. The parts
// of the scene that move or hold a rig (`ValleyScene`, `ValleyLife`,
// `OttoAuraFigure`) stay in the app and compose these.
//
// The colour literals here follow `ValleyScene`'s rule: they are keyframes
// and fixed pigments of a painting, not themeable tokens.

/// The sky at one hour: its gradient, the stars after dark and the sun.
struct ValleySky: View {
    let day: DayLight
    /// The hour drawn, on DayLight's 0 (full day) to 1 (night) scale.
    let hour: Double
    let size: CGSize
    let scale: CGFloat
    /// The sun on the right instead of the left. The home screen's small
    /// widget keeps its top left for the streak, and the daytime sun sat
    /// exactly there.
    var sunMirrored: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(colors: day.sky, startPoint: .top, endPoint: .bottom)

            Canvas { ctx, _ in
                for star in DayLight.stars {
                    let r = CGRect(x: star.x * size.width - 1,
                                   y: star.y * size.height - 1,
                                   width: 2, height: 2)
                    ctx.fill(Path(ellipseIn: r),
                             with: .color(.white.opacity(star.alpha)))
                }
            }
            .opacity(day.starOpacity)

            // Starts a little above the ridge and sets through it. Past dusk
            // it is gone and the stars carry the sky.
            ValleySunDisc(diameter: (44 + 4 * hour) * scale,
                          bottomFraction: 0.52 - 0.30 * hour,
                          fill: day.sun, glow: day.glow, scale: scale,
                          mirrored: sunMirrored)
        }
    }
}

/// The three clouds at one moment. The app drifts them by handing in the
/// time from a `TimelineView` (Melvin, 2026-09-23: "i want the clouds to
/// always be slowly drifting"); the widget hands in its entry's date, so
/// they sit where the app would have had them. About 4 to 7 points a second:
/// a cloud takes a minute or two to cross, findable if you look for it.
struct ValleyClouds: View {
    let day: DayLight
    let hour: Double
    let size: CGSize
    let scale: CGFloat
    let time: TimeInterval

    var body: some View {
        let s = scale
        let specs: [(w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat, speed: Double)] = [
            (132 * s, 68 * s, -0.09 * size.width, 0.06 * size.height, 5.0),
            (158 * s, 82 * s, size.width - 158 * s + 0.11 * size.width, 0.17 * size.height, 3.6),
            (96 * s, 50 * s, 0.12 * size.width, 0.31 * size.height, 6.4),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(0..<specs.count, id: \.self) { i in
                let c = specs[i]
                // Wraps from just off the right edge to just off the left.
                let span = Double(size.width + c.w)
                let raw = (Double(c.x + c.w) + time * c.speed).truncatingRemainder(dividingBy: span)
                ValleyCloud()
                    .fill(day.cloud)
                    .frame(width: c.w, height: c.h)
                    .offset(x: CGFloat(raw) - c.w, y: c.y)
                    .opacity(i == 2 && hour <= 0.35 ? 0 : 1)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(day.cloudOpacity)
    }
}

/// The land under the sky: three rows of ridges, far to near, then the
/// field with its haze.
struct ValleyLand: View {
    let day: DayLight
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        ZStack {
            // Three rows, far to near. The band sits at 30% up the frame and
            // is 30% tall, so the nearest ridge meets the meadow rather than
            // floating above it.
            ForEach(0..<3, id: \.self) { row in
                ValleyRidge(row: row)
                    .fill(day.ridge[row])
                    .frame(width: w, height: h * 0.30)
                    .offset(y: h * 0.05)
            }

            LinearGradient(colors: day.field, startPoint: .top, endPoint: .bottom)
                .frame(width: w, height: h * 0.34)
                .offset(y: h * 0.33)

            // Depth (Aziz, 2026-09-23): the field was one flat green, so a
            // grasshopper crossing it had nothing to be near or far in. Haze
            // where the grass meets the ridge, and the ground darkening as it
            // comes toward the viewer, the way distance actually reads
            // outdoors.
            LinearGradient(stops: [
                .init(color: .white.opacity(0.22), location: 0),
                .init(color: .white.opacity(0), location: 0.28),
                .init(color: .clear, location: 0.55),
                .init(color: Color(red: 0.16, green: 0.30, blue: 0.14).opacity(0.20), location: 1)
            ], startPoint: .top, endPoint: .bottom)
                .frame(width: w, height: h * 0.34)
                .offset(y: h * 0.33)
                .allowsHitTesting(false)
        }
        .frame(width: w, height: h)
    }
}

/// Places the sun by its bottom edge, the way the mockup does, so the scene
/// body stays a list of layers rather than a page of arithmetic.
///
/// It sits left of centre on purpose: directly behind his head it read as a
/// halo rather than a sun. Mirrored, it sits as far right of centre.
struct ValleySunDisc: View {
    let diameter: CGFloat
    let bottomFraction: Double
    let fill: Color
    let glow: Color
    let scale: CGFloat
    var mirrored: Bool = false

    var body: some View {
        GeometryReader { geo in
            let x = 0.24 * geo.size.width + diameter / 2
            Circle()
                .fill(fill)
                .frame(width: diameter, height: diameter)
                .shadow(color: glow, radius: 20 * scale)
                .shadow(color: glow.opacity(0.75), radius: 44 * scale)
                .position(x: mirrored ? geo.size.width - x : x,
                          y: geo.size.height * (1 - bottomFraction) - diameter / 2)
        }
    }
}

// MARK: - Shapes

/// One of the three mountain rows, traced from the mockup's SVG in its own
/// 300 x 260 box and stretched to whatever band it is given.
struct ValleyRidge: Shape {
    var row: Int = 0

    private static let rows: [[CGPoint]] = [
        [.init(x: 0, y: 150), .init(x: 48, y: 96), .init(x: 86, y: 132),
         .init(x: 132, y: 72), .init(x: 186, y: 128), .init(x: 224, y: 100),
         .init(x: 300, y: 148)],
        [.init(x: 0, y: 176), .init(x: 40, y: 138), .init(x: 92, y: 172),
         .init(x: 140, y: 122), .init(x: 192, y: 168), .init(x: 246, y: 138),
         .init(x: 300, y: 174)],
        [.init(x: 0, y: 206), .init(x: 56, y: 178), .init(x: 110, y: 204),
         .init(x: 168, y: 172), .init(x: 228, y: 202), .init(x: 300, y: 184)]
    ]

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 300, sy = rect.height / 260
        var p = Path()
        let pts = ValleyRidge.rows[row]
        p.move(to: CGPoint(x: pts[0].x * sx, y: pts[0].y * sy))
        for pt in pts.dropFirst() {
            p.addLine(to: CGPoint(x: pt.x * sx, y: pt.y * sy))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// Three lobes over a slab, which is the cheapest thing that reads as a cloud
/// at this size without looking like a speech bubble.
struct ValleyCloud: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 120, sy = rect.height / 62
        func e(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
            CGRect(x: (cx - rx) * sx, y: (cy - ry) * sy,
                   width: 2 * rx * sx, height: 2 * ry * sy)
        }
        var p = Path()
        p.addEllipse(in: e(33, 39, 26, 17))
        p.addEllipse(in: e(62, 30, 31, 22))
        p.addEllipse(in: e(91, 41, 23, 15))
        p.addRoundedRect(in: CGRect(x: 10 * sx, y: 38 * sy,
                                    width: 100 * sx, height: 18 * sy),
                         cornerSize: CGSize(width: 9 * sx, height: 9 * sy))
        return p
    }
}

/// The terracotta seat. A gradient, a lit rim, and a highlight across the top
/// so it reads as a solid object rather than a painted oval.
/// Also the one a standing Otto stands on in onboarding's welcome, drawn
/// there at exactly this size and place so it never changes between screens.
struct Cushion: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse()
                    .fill(LinearGradient(colors: [Color(red: 0.851, green: 0.545, blue: 0.431),
                                                  Color(red: 0.725, green: 0.416, blue: 0.314)],
                                         startPoint: .top, endPoint: .bottom))
                Ellipse()
                    .fill(Color(red: 1, green: 0.886, blue: 0.816).opacity(0.22))
                    .frame(width: w * 0.76, height: h * 0.27)
                    .offset(y: -h * 0.22)
            }
            .shadow(color: .black.opacity(0.22), radius: 4, y: 3)
        }
    }

    /// The cushion where the scene seats him, laid out in scene coordinates,
    /// with the meadow's nearer grass and flowers standing in front of it.
    /// `lift` raises it with him (the Ready screen's `ottoLift`).
    static func seated(in size: CGSize, scale s: CGFloat, lift: CGFloat = 0) -> some View {
        Cushion()
            .frame(width: 168 * s, height: 44 * s)
            .position(x: size.width / 2,
                      y: SitLayout.cushionBottom(in: size) - 22 * s - lift)
            .standsInMeadow(feetY: SitLayout.cushionFront(in: size, scale: s) - lift,
                            scale: s, sceneSize: size)
    }
}

extension View {
    /// **Anything standing IN the meadow goes through this.** The meadow is
    /// one canvas painted before everything on it, so whatever is placed
    /// afterwards covers every flower, near or far. That has now gone wrong
    /// three times (Aziz, 2026-09-23): a grasshopper "landing on the petals"
    /// of a nearer flower, and Otto's cushion, on the welcome AND on every
    /// seated screen, covering the flowers in front of it. This repaints the
    /// grass and flowers whose foot is nearer than `feetY` over the view,
    /// cut to the view's own outline, so they stand in front of it and
    /// nothing outside it is drawn twice.
    ///
    /// The view must be laid out in SCENE coordinates (full scene size, its
    /// content placed with `.position`), the same space the meadow is drawn
    /// in. `feetY` is where the thing meets the ground, in points from the
    /// top of the scene.
    func standsInMeadow(feetY: CGFloat, scale: CGFloat, sceneSize: CGSize) -> some View {
        let placed = frame(width: sceneSize.width, height: sceneSize.height)
        return placed.overlay {
            Meadow(scale: scale, nearerThan: feetY)
                .frame(width: sceneSize.width, height: sceneSize.height)
                .mask { placed }
                .allowsHitTesting(false)
        }
    }
}

/// The meadow, drawn once into a canvas rather than as 26 view hierarchies.
///
/// Placement is not random. The flowers were dart-thrown in pixel space so
/// none sits on another, and they are drawn **back to front**: smaller and
/// paler toward the ridge, bigger and brighter at the bottom edge, which is
/// what makes a flat field read as ground going away from you.
struct Meadow: View {
    let scale: CGFloat
    /// Draw only the grass and flowers standing NEARER than this feet line
    /// (points from the top). A grasshopper redraws these over itself, cut to
    /// its own outline, so a flower in front of it covers it instead of
    /// looking like a petal it has landed on (Aziz, 2026-09-23). Nil draws
    /// the whole meadow.
    var nearerThan: CGFloat? = nil

    /// Clumps of grass scattered over the field, fixed so the meadow is the
    /// same every time. Smaller and paler toward the ridge, bigger and darker
    /// near the bottom edge: the same rule the flowers follow, and the main
    /// thing that makes the ground read as going away from you.
    fileprivate struct Tuft {
        let x: CGFloat
        /// Fraction of the height, from the bottom.
        let bottom: CGFloat
        let blades: Int
        let lean: CGFloat
        /// 0 at the ridge, 1 at the bottom edge.
        var near: CGFloat { max(0, min(1, 1 - bottom / 0.34)) }
    }

    fileprivate static let tufts: [Tuft] = {
        var seed: UInt64 = 0x808_5EED
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        var out: [Tuft] = []
        for _ in 0..<46 {
            // Denser toward the ridge, where everything is smaller.
            let depth = pow(next(), 0.8)
            out.append(Tuft(x: next(), bottom: 0.015 + depth * 0.31,
                            blades: 3 + Int(next() * 3), lean: (next() - 0.5) * 0.3))
        }
        // Far first, so a near tuft is drawn over a far one.
        return out.sorted { $0.bottom > $1.bottom }
    }()

    var body: some View {
        Canvas { ctx, size in
            // Grass tufts first, far to near, so the flowers stand in them.
            for t in Meadow.tufts {
                let near = t.near
                let h = (5 + 15 * near) * scale
                let base = CGPoint(x: t.x * size.width, y: size.height * (1 - t.bottom))
                if let nearerThan, base.y <= nearerThan { continue }
                var path = Path()
                for blade in 0..<t.blades {
                    let spread = (CGFloat(blade) - CGFloat(t.blades - 1) / 2) * 0.32
                    let tip = CGPoint(x: base.x + spread * h + t.lean * h,
                                      y: base.y - h * (0.75 + 0.25 * CGFloat((blade * 7 + 3) % 4) / 3))
                    path.move(to: CGPoint(x: base.x + spread * h * 0.25, y: base.y))
                    path.addQuadCurve(to: tip,
                                      control: CGPoint(x: base.x + spread * h * 0.4, y: base.y - h * 0.5))
                }
                ctx.stroke(path,
                           with: .color(Color(red: 0.29 - 0.08 * near, green: 0.48 - 0.08 * near,
                                              blue: 0.27 - 0.06 * near)
                                .opacity(0.30 + 0.45 * Double(near))),
                           style: StrokeStyle(lineWidth: (0.8 + 1.4 * near) * scale, lineCap: .round))
            }
            for f in Meadow.flowers {
                let w = f.w * scale, h = f.h * scale
                let anchor = CGPoint(x: f.left * size.width,
                                     y: size.height * (1 - f.bottom))
                if let nearerThan, anchor.y <= nearerThan { continue }
                ctx.drawLayer { layer in
                    layer.translateBy(x: anchor.x, y: anchor.y)
                    layer.rotate(by: .degrees(f.rotation))
                    layer.opacity = f.opacity
                    draw(into: &layer, w: w, h: h, petal: f.petal, centre: f.centre)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// The flower in its own 60 x 130 box, origin at the foot of the stem.
    private func draw(into ctx: inout GraphicsContext,
                      w: CGFloat, h: CGFloat, petal: Color, centre: Color) {
        func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: u / 60 * w - w / 2, y: v / 130 * h - h)
        }

        var stem = Path()
        stem.move(to: p(30, 130))
        stem.addCurve(to: p(30, 62), control1: p(23, 104), control2: p(37, 86))
        ctx.stroke(stem, with: .color(Color(red: 0.369, green: 0.604, blue: 0.384)),
                   style: StrokeStyle(lineWidth: 4.5 / 60 * w, lineCap: .round))

        let leafC = p(42, 92)
        ctx.drawLayer { l in
            l.translateBy(x: leafC.x, y: leafC.y)
            l.rotate(by: .degrees(-22))
            l.fill(Path(ellipseIn: CGRect(x: -10 / 60 * w, y: -5 / 130 * h,
                                          width: 20 / 60 * w, height: 10 / 130 * h)),
                   with: .color(Color(red: 0.420, green: 0.682, blue: 0.431)))
        }

        let head = p(30, 30)
        for i in 0..<5 {
            let angle = Angle.degrees(Double(i) * 72)
            ctx.drawLayer { l in
                l.translateBy(x: head.x, y: head.y)
                l.rotate(by: angle)
                l.fill(Path(ellipseIn: CGRect(x: -8.5 / 60 * w,
                                              y: -14 / 130 * h - 12.5 / 130 * h,
                                              width: 17 / 60 * w, height: 25 / 130 * h)),
                       with: .color(petal))
            }
        }
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 7.5 / 60 * w,
                                        y: head.y - 7.5 / 130 * h,
                                        width: 15 / 60 * w, height: 15 / 130 * h)),
                 with: .color(centre))
    }

    struct Flower {
        let left: Double, bottom: Double
        let w: CGFloat, h: CGFloat
        let rotation: Double, opacity: Double
        let petal: Color, centre: Color
    }

    private static let white = Color(red: 1, green: 1, blue: 1)
    private static let cream = Color(red: 1, green: 0.953, blue: 0.839)
    private static let peach = Color(red: 1, green: 0.761, blue: 0.659)
    private static let pink  = Color(red: 1, green: 0.702, blue: 0.788)
    private static let honey = Color(red: 1, green: 0.847, blue: 0.420)
    private static let amber = Color(red: 0.961, green: 0.651, blue: 0.137)
    private static let rose  = Color(red: 0.910, green: 0.337, blue: 0.310)
    private static let rust  = Color(red: 0.910, green: 0.525, blue: 0.169)

    /// Back to front. Never reorder this list: the draw order is the depth.
    static let flowers: [Flower] = [
        .init(left: 0.128, bottom: 0.307, w: 11, h: 22, rotation: 7, opacity: 0.83, petal: white, centre: amber),
        .init(left: 0.194, bottom: 0.304, w: 11, h: 23, rotation: 6, opacity: 0.83, petal: peach, centre: rose),
        .init(left: 0.051, bottom: 0.303, w: 11, h: 23, rotation: -6, opacity: 0.83, petal: honey, centre: rust),
        .init(left: 0.798, bottom: 0.294, w: 12, h: 25, rotation: 4, opacity: 0.83, petal: white, centre: amber),
        .init(left: 0.847, bottom: 0.291, w: 12, h: 25, rotation: 8, opacity: 0.83, petal: pink, centre: rose),
        .init(left: 0.900, bottom: 0.263, w: 14, h: 30, rotation: 0, opacity: 0.85, petal: cream, centre: amber),
        .init(left: 0.174, bottom: 0.256, w: 15, h: 31, rotation: 3, opacity: 0.86, petal: white, centre: amber),
        .init(left: 0.767, bottom: 0.252, w: 15, h: 32, rotation: -5, opacity: 0.86, petal: white, centre: amber),
        .init(left: 0.240, bottom: 0.246, w: 16, h: 33, rotation: -3, opacity: 0.86, petal: pink, centre: rose),
        .init(left: 0.041, bottom: 0.236, w: 17, h: 35, rotation: 4, opacity: 0.87, petal: white, centre: amber),
        .init(left: 0.116, bottom: 0.213, w: 18, h: 39, rotation: 4, opacity: 0.88, petal: cream, centre: amber),
        .init(left: 0.831, bottom: 0.213, w: 18, h: 39, rotation: -7, opacity: 0.88, petal: cream, centre: amber),
        .init(left: 0.232, bottom: 0.190, w: 20, h: 43, rotation: -4, opacity: 0.90, petal: pink, centre: rose),
        .init(left: 0.760, bottom: 0.184, w: 21, h: 44, rotation: -2, opacity: 0.90, petal: honey, centre: rust),
        .init(left: 0.057, bottom: 0.179, w: 21, h: 45, rotation: -5, opacity: 0.90, petal: peach, centre: rose),
        .init(left: 0.148, bottom: 0.167, w: 22, h: 47, rotation: 5, opacity: 0.91, petal: honey, centre: rust),
        .init(left: 0.905, bottom: 0.166, w: 22, h: 47, rotation: -1, opacity: 0.91, petal: peach, centre: rose),
        .init(left: 0.816, bottom: 0.126, w: 26, h: 54, rotation: -2, opacity: 0.94, petal: peach, centre: rose),
        .init(left: 0.521, bottom: 0.105, w: 27, h: 57, rotation: -7, opacity: 0.95, petal: cream, centre: amber),
        .init(left: 0.908, bottom: 0.102, w: 28, h: 58, rotation: -4, opacity: 0.95, petal: peach, centre: rose),
        .init(left: 0.705, bottom: 0.088, w: 29, h: 60, rotation: 6, opacity: 0.96, petal: peach, centre: rose),
        .init(left: 0.264, bottom: 0.049, w: 32, h: 67, rotation: 4, opacity: 0.99, petal: honey, centre: rust),
        .init(left: 0.405, bottom: 0.037, w: 33, h: 69, rotation: -2, opacity: 0.99, petal: cream, centre: amber),
        .init(left: 0.817, bottom: 0.033, w: 33, h: 70, rotation: -1, opacity: 1.00, petal: white, centre: amber),
        .init(left: 0.114, bottom: 0.032, w: 33, h: 70, rotation: 8, opacity: 1.00, petal: honey, centre: rust),
        .init(left: 0.580, bottom: 0.032, w: 33, h: 70, rotation: 8, opacity: 1.00, petal: pink, centre: rose)
    ]
}

// MARK: - Otto's stills

/// The canvas every one of Otto's aura stills is drawn on
/// (`mockups/otto-v4/canvas.json`): 664 x 744, his body's bottom at 87.2% of
/// the height, and Steady's body 82% of it. `OttoAuraFigure` frames the app's
/// stills by these and the widget frames its smaller copies by the same.
enum OttoStillCanvas {
    static let aspect: CGFloat = 664.0 / 744.0
    static let baseline: CGFloat = 0.872
    static let bodyShare: CGFloat = 0.82
}

// MARK: - Layout

/// Where the pieces of the sit sit, shared by the scene and the screen on top
/// of it so the two can never disagree about how big Otto is or where his
/// head ends.
///
/// The mockup is a 300 x 620 panel and every size in it is in those units, so
/// one scale factor ports all of them. It takes the SMALLER of the two ratios:
/// scaling by width alone made Otto eat a short phone, because he is sized by
/// width and placed by height, and on a 667pt screen that put the top of his
/// head 130pt higher up the frame than the composition intends.
enum SitLayout {
    /// Where a grasshopper passes from behind Otto to in front of him: the
    /// bottom of his cushion, where he meets the grass.
    static func grasshopperSplit(in size: CGSize) -> CGFloat { cushionBottom(in: size) }

    /// The cushion's front edge on the grass: flowers and tufts whose foot is
    /// below this line stand in front of it (`standsInMeadow`).
    static func cushionFront(in size: CGSize, scale s: CGFloat) -> CGFloat {
        cushionBottom(in: size) - 6 * s
    }

    static func scale(in size: CGSize) -> CGFloat {
        min(size.width / 300, size.height / 620)
    }

    /// The top of Otto's head. His face is roughly the third of him below it,
    /// and nothing may be drawn across it.
    static func ottoTop(in size: CGSize) -> CGFloat {
        size.height - (size.height * 0.24 + 186 * scale(in: size))
    }

    /// The bottom edge of his cushion, a little below where he sits. The
    /// scene draws the cushion from here, and the Ready screen reads it to
    /// know how far to lift him clear of its pills.
    static func cushionBottom(in size: CGSize) -> CGFloat {
        size.height * (1 - 0.215)
    }

    /// The clock's ring.
    ///
    /// It was 79% of the width, centred at 39.5% of the height, which is a
    /// hoop AROUND him: measured, it ran 88pt into his face on a tall phone
    /// and 137pt on a short one. It is a medallion in the sky above him now,
    /// sized off both axes so it survives a short screen, and hung from the
    /// top of his head rather than pinned to a fraction of the frame, so the
    /// clearance is the same 12pt on every device.
    static func ringDiameter(in size: CGSize) -> CGFloat {
        min(size.width * 0.40, size.height * 0.175)
    }

    /// `hat` is how far his hat stands above his head
    /// (`OttoRiveView.hatRise`): the ring hangs from the top of the hat, so
    /// a tall one never runs through the clock.
    static func ringCentreY(in size: CGSize, hat: CGFloat = 0) -> CGFloat {
        ottoTop(in: size) - hat - 12 - ringDiameter(in: size) / 2
    }

    static func ringTop(in size: CGSize, hat: CGFloat = 0) -> CGFloat {
        ringCentreY(in: size, hat: hat) - ringDiameter(in: size) / 2
    }

    /// Roughly where the Dynamic Island stops. Read as a fraction rather than
    /// from the safe area, because the scene deliberately ignores it: the sky
    /// has to run under the island or the band above it paints in the wrong
    /// colour.
    static func skyTop(in size: CGSize) -> CGFloat { size.height * 0.075 }

    /// The headline block's centre: the middle of the band between the island
    /// and the ring.
    ///
    /// It was a flat 12.5% of the height, which put it in the island's shadow
    /// with nothing above it and the ring crowding it from below. Centring it
    /// in the space it actually has drops it about 45pt on a tall phone and
    /// still clears the ring on a short one, which a second fixed fraction
    /// could not have done for both.
    static func headlineY(in size: CGSize, hat: CGFloat = 0) -> CGFloat {
        (skyTop(in: size) + ringTop(in: size, hat: hat)) / 2
    }

    /// The height the scene draws the seated Otto at, for asking
    /// `OttoRiveView.hatRise` about this screen.
    static func ottoHeight(in size: CGSize) -> CGFloat { 186 * scale(in: size) * 1.17 }

    /// The centre of the box the scene seats him in, hung from 24% up the
    /// frame. The widget places his still here.
    static func seatedCentreY(in size: CGSize) -> CGFloat {
        size.height * (1 - 0.24) - ottoHeight(in: size) / 2
    }
}
