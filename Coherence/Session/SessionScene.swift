import SwiftUI

/// The valley Otto sits in while you meditate.
///
/// Built from `mockups/session-v3.html`, which is where the composition
/// numbers were argued out: the horizon at 34%, Otto at 24%, the ring at the
/// top third, the sun starting just above the ridge. Those are the numbers
/// that are painful to change later, so they are carried over exactly, as
/// fractions of the frame rather than the mockup's pixels.
///
/// **The sun does the work a progress bar would.** It is the one thing on
/// screen that is honestly moving, and it cannot be read precisely, which is
/// what you want someone looking at mid-sit. The sky, the ridge, the meadow
/// and the light on Otto all follow the same single number.
///
/// ## Why the colours are literals here and not colorsets
///
/// The house rule is that no view hardcodes a hex value, because a themeable
/// colour that lives in two places drifts. This is the one place the rule
/// does not apply and the reason is mechanical: these are not tokens, they
/// are **keyframes of a painting that is interpolated every frame**. An asset
/// catalog can hand back a `Color` but not its components, so a palette kept
/// there could be read and never blended. They are also not themeable: the
/// app has one appearance, and dusk is dusk on every phone.
struct ValleyScene: View {
    /// 0 when the sit begins, 1 when it ends. Everything below reads this.
    var progress: Double

    /// What Otto is doing in it. The pre-sit screen wants him awake and
    /// waving; the sit itself wants him cross-legged with his eyes shut.
    /// Both are the same rig in the same valley, so tapping Begin settles
    /// him rather than cutting to a different picture.
    var pose: OttoPose = .meditating

    /// Home seats Otto at his aura stage instead (`OttoAura`): the same
    /// valley, the same cushion, with the glow the practice has earned. nil
    /// is the sit and the Ready screen, which draw `pose`.
    var aura: OttoAura.Stage? = nil

    /// Bumped by a tap on him on Home: the aura figure jiggles
    /// (`OttoJiggle`). Nothing else sets it, so the sit and the Ready screen
    /// never move this way.
    var jiggle: Int = 0

    /// Draw the valley with nobody in it.
    ///
    /// Profile's band needs the place without the character: Otto is the
    /// portrait on that page, and drawing him in the band as well would put
    /// two of him on one screen. The cushion goes with him, since an empty
    /// cushion reads as somebody having just left. The Block tab and Otto's
    /// screens ask for it too: they stand their own pose (clipboard, waving,
    /// slumped) in the meadow.
    var showsFigure: Bool = true

    /// Birds and grasshoppers, every ten-ish and eight-ish seconds — only
    /// while nobody is meditating (`progress == 0`: Home, onboarding, the
    /// Ready screen, the Block/Friends/Profile/Guide bands). The sit itself
    /// stays still the moment `progress` moves. See `ValleyLife.swift`.
    var life: Bool = true

    /// Draw the real time of day instead of the top of it (Melvin,
    /// 2026-09-23: "we want the sun and time of day to match the real time
    /// of day"). With it on, `progress` still moves a sit toward night, but
    /// from wherever the clock already is: a sit begun at dusk carries on
    /// from dusk. See `DayLight.clockProgress`.
    var clock: Bool = false

    /// Move him up to the corner, small, so a list can have the meadow.
    ///
    /// **It is a placement on the SAME view, not a second Otto.** Swapping
    /// in a separate small figure would tear down the Rive rig and build
    /// another, which costs a frame of nothing and restarts his wave; moving
    /// and resizing one view is a spring the rig plays straight through.
    var ottoInCorner: Bool = false

    /// The rig, so he actually breathes while you do.
    ///
    /// `@StateObject` rather than a fresh `OttoRig` per body: the Rive view
    /// model has to survive every redraw of the scene, and the scene redraws
    /// once a second for the clock. If the .riv is missing or refuses to
    /// load, `OttoRiveView` falls back to the still art with a scale pulse,
    /// so a bad export costs motion and never a screen.
    @StateObject private var rig = OttoRigHolder()

    /// One seed per `ValleyScene` instance, not per redraw: Home's birds
    /// and a Friends band's birds fly different patterns rather than
    /// mirroring each other, and the clock ticking once a second elsewhere
    /// on screen never reshuffles either one mid-flight.
    @State private var lifeSeed = UInt64.random(in: UInt64.min...UInt64.max)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The hour drawn, on DayLight's 0 (full day) to 1 (night) scale.
    private func hour(at date: Date) -> Double {
        guard clock else { return progress }
        let start = DayLight.clockProgress(at: date)
        return start + (1 - start) * progress
    }

    var body: some View {
        // Once a minute is plenty for the sky to follow the clock.
        TimelineView(.everyMinute) { context in
            scene(hour: hour(at: context.date))
        }
    }

    private func scene(hour p: Double) -> some View {
        let day = DayLight.at(p)
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let s = SitLayout.scale(in: geo.size)
            // Ambient wildlife only while nobody is meditating: `progress`
            // starts at 0 for the Ready screen and Home alike, but moves
            // the instant a real sit begins, and the sit stays still. And
            // only in daylight: the birds go to roost at dusk.
            let showLife = life && progress == 0 && p < 0.4 && !reduceMotion
            let avoidRect = showLife ? lifeAvoidRect(size: geo.size, scale: s) : nil

            ZStack {
                LinearGradient(colors: day.sky,
                               startPoint: .top, endPoint: .bottom)

                stars(in: geo.size, day: day)

                sun(scale: s, hour: p, day: day)

                clouds(scale: s, size: geo.size, hour: p, day: day)

                // Three rows, far to near. The band sits at 30% up the
                // frame and is 30% tall, so the nearest ridge meets the
                // meadow rather than floating above it.
                ForEach(0..<3, id: \.self) { row in
                    Ridge(row: row)
                        .fill(day.ridge[row])
                        .frame(width: w, height: h * 0.30)
                        .offset(y: h * 0.05)
                }

                LinearGradient(colors: day.field, startPoint: .top, endPoint: .bottom)
                    .frame(width: w, height: h * 0.34)
                    .offset(y: h * 0.33)

                // Birds sit in front of the ridges and the field wash (or
                // the field, drawn after, would paint straight over one
                // dipping near the ridge line) and stay well clear of
                // Otto's head by construction, via `avoidRect`.
                if showLife {
                    ValleyLife(layer: .sky, size: geo.size, scale: s, seed: lifeSeed, avoid: avoidRect)
                }

                // Everything alive takes the hour's light as one group, so
                // the cushion, the sloth and the flowers can never disagree
                // about what time it is.
                groundScene(size: geo.size, scale: s)
                    .colorMultiply(Color(white: day.light))

                // Grasshoppers ride on top of the meadow and the sitter, but
                // their lanes are chosen beside `avoidRect`, never inside it.
                if showLife {
                    ValleyLife(layer: .meadow, size: geo.size, scale: s, seed: lifeSeed, avoid: avoidRect)
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
    }

    /// Otto and his cushion, generously boxed, so birds and grasshoppers
    /// have one rectangle to clear rather than needing to know his rig's
    /// exact silhouette. `nil` when there is no figure to avoid: nothing is
    /// drawn (`!showsFigure`), or he is tucked in the corner, well clear of
    /// the meadow already.
    private func lifeAvoidRect(size: CGSize, scale s: CGFloat) -> CGRect? {
        guard showsFigure, !ottoInCorner else { return nil }
        let seated = ottoHeight(scale: s)
        let top = SitLayout.ottoTop(in: size) - 20
        let cushionBottom = size.height * (1 - 0.215) + 22 * s
        let ottoBottom = size.height * (1 - 0.24) + 12
        let bottom = max(cushionBottom, ottoBottom)
        let halfWidth = max(168 * s, seated * 0.85) / 2 + 24
        return CGRect(x: size.width / 2 - halfWidth, y: top,
                      width: halfWidth * 2, height: max(20, bottom - top))
    }

    // MARK: - Sky furniture

    private func sun(scale s: CGFloat, hour progress: Double, day: DayLight) -> some View {
        // Starts a little above the ridge and sets through it. Past dusk it
        // is gone and the stars carry the sky.
        SunDisc(diameter: (44 + 4 * progress) * s,
                bottomFraction: 0.52 - 0.30 * progress,
                fill: day.sun, glow: day.glow, scale: s)
    }

    /// The clouds drift slowly all the time, wrapping round, so the sky is
    /// never a screenshot (Melvin, 2026-09-23: "i want the clouds to always
    /// be slowly drifting"). It used to move only with `progress`, which held
    /// every sky but the sit's perfectly still. About 4 to 7 points a second:
    /// a cloud takes a minute or two to cross, findable if you look for it.
    private func clouds(scale s: CGFloat, size: CGSize, hour progress: Double, day: DayLight) -> some View {
        let specs: [(w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat, speed: Double)] = [
            (132 * s, 68 * s, -0.09 * size.width, 0.06 * size.height, 5.0),
            (158 * s, 82 * s, size.width - 158 * s + 0.11 * size.width, 0.17 * size.height, 3.6),
            (96 * s, 50 * s, 0.12 * size.width, 0.31 * size.height, 6.4),
        ]
        return TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(0..<specs.count, id: \.self) { i in
                    let c = specs[i]
                    // Wraps from just off the right edge to just off the left.
                    let span = Double(size.width + c.w)
                    let raw = (Double(c.x + c.w) + t * c.speed).truncatingRemainder(dividingBy: span)
                    cloud(w: c.w, h: c.h, x: CGFloat(raw) - c.w, y: c.y, day: day)
                        .opacity(i == 2 && progress <= 0.35 ? 0 : 1)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .opacity(day.cloudOpacity)
    }

    private func cloud(w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat, day: DayLight) -> some View {
        Cloud()
            .fill(day.cloud)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }

    private func stars(in size: CGSize, day: DayLight) -> some View {
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
    }

    /// The drawn height of the rig. `SitLayout` measures Otto as 186 units
    /// because that is what the flat cutout occupies; the artboard carries
    /// roughly a sixth again in empty sky above his tuft, so it is drawn
    /// taller to put the sloth himself at the same size on screen.
    private func ottoHeight(scale s: CGFloat) -> CGFloat { 186 * s * 1.17 }

    /// Where he stands when a list needs the meadow. He bleeds a little past
    /// the left gutter, the way he does on Home.
    private static let cornerHeight: CGFloat = 104
    private static let cornerX: CGFloat = 52
    private static let cornerY: CGFloat = 132

    // MARK: - The ground and the sitter

    private func groundScene(size: CGSize, scale s: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Meadow(scale: s)
                .frame(width: size.width, height: size.height)

            // The cushion gives him somewhere to be rather than floating on
            // grass, and it is the one warm object in a cool frame.
            Cushion()
                .frame(width: 168 * s, height: 44 * s)
                .position(x: size.width / 2,
                          y: size.height * (1 - 0.215) - 22 * s)
                .opacity(ottoInCorner || !showsFigure ? 0 : 1)

            // The artboard carries headroom above his tuft that the cutout
            // PNG does not, so it is drawn taller to put the sloth himself at
            // the same size, and hung from its own bottom edge.
            let seated = ottoHeight(scale: s)
            let tall = ottoInCorner ? Self.cornerHeight : seated
            Group {
                if !showsFigure {
                    EmptyView()
                } else if let aura {
                    OttoAuraFigure(stage: aura, size: tall, rig: rig, jiggle: jiggle)
                } else {
                    OttoRiveView(size: tall, pose: pose, rig: rig)
                }
            }
            .position(x: ottoInCorner ? Self.cornerX : size.width / 2,
                      y: ottoInCorner ? Self.cornerY
                                      : size.height * (1 - 0.24) - seated / 2)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Places the sun by its bottom edge, the way the mockup does, so the scene
/// body stays a list of layers rather than a page of arithmetic.
///
/// It sits left of centre on purpose: directly behind his head it read as a
/// halo rather than a sun.
private struct SunDisc: View {
    let diameter: CGFloat
    let bottomFraction: Double
    let fill: Color
    let glow: Color
    let scale: CGFloat

    var body: some View {
        GeometryReader { geo in
            Circle()
                .fill(fill)
                .frame(width: diameter, height: diameter)
                .shadow(color: glow, radius: 20 * scale)
                .shadow(color: glow.opacity(0.75), radius: 44 * scale)
                .position(x: 0.24 * geo.size.width + diameter / 2,
                          y: geo.size.height * (1 - bottomFraction) - diameter / 2)
        }
    }
}

// MARK: - Shapes

/// One of the three mountain rows, traced from the mockup's SVG in its own
/// 300 x 260 box and stretched to whatever band it is given.
private struct Ridge: Shape {
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
        let pts = Ridge.rows[row]
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
private struct Cloud: Shape {
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
private struct Cushion: View {
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
}

/// The meadow, drawn once into a canvas rather than as 26 view hierarchies.
///
/// Placement is not random. The flowers were dart-thrown in pixel space so
/// none sits on another, and they are drawn **back to front**: smaller and
/// paler toward the ridge, bigger and brighter at the bottom edge, which is
/// what makes a flat field read as ground going away from you.
private struct Meadow: View {
    let scale: CGFloat

    var body: some View {
        Canvas { ctx, size in
            for f in Meadow.flowers {
                let w = f.w * scale, h = f.h * scale
                let anchor = CGPoint(x: f.left * size.width,
                                     y: size.height * (1 - f.bottom))
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
    static func scale(in size: CGSize) -> CGFloat {
        min(size.width / 300, size.height / 620)
    }

    /// The top of Otto's head. His face is roughly the third of him below it,
    /// and nothing may be drawn across it.
    static func ottoTop(in size: CGSize) -> CGFloat {
        size.height - (size.height * 0.24 + 186 * scale(in: size))
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

    static func ringCentreY(in size: CGSize) -> CGFloat {
        ottoTop(in: size) - 12 - ringDiameter(in: size) / 2
    }

    static func ringTop(in size: CGSize) -> CGFloat {
        ringCentreY(in: size) - ringDiameter(in: size) / 2
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
    static func headlineY(in size: CGSize) -> CGFloat {
        (skyTop(in: size) + ringTop(in: size)) / 2
    }
}

// MARK: - The light

/// The palette at one moment of the sit, blended from four keyframes: the sun
/// up, the sun on the ridge, the first dark, and the afterglow.
///
/// **It ends at dusk rather than back in daylight.** A sunrise would be a
/// brighter screen at the exact moment somebody is most settled, and the
/// quiet afterglow is a better reward than a bright one. It is also the
/// practical reason the sun sets: by the middle of a sit the screen is dark
/// enough to sit with in a room at night.
struct DayLight {
    var sky: [Color]
    var ridge: [Color]
    var field: [Color]
    var sun: Color
    var glow: Color
    var cloud: Color
    var cloudOpacity: Double
    var starOpacity: Double
    /// What the hour does to everything alive, as a multiply.
    var light: Double
    /// The empty ring against this sky. White on a pale morning is no ring at
    /// all, so the track takes ink early and cream late.
    var ringTrack: Color
    var ink: Color
    var inkSoft: Color

    private struct Stop {
        let t: Double
        let sky: [UInt32]
        let ridge: [UInt32]
        let field: [UInt32]
        let sun: UInt32, glow: UInt32, glowA: Double
        let cloud: UInt32, cloudA: Double
        let stars: Double
        let light: Double
        let track: UInt32, trackA: Double
        let ink: UInt32, inkSoft: UInt32
    }

    private static let stops: [Stop] = [
        .init(t: 0.00,
              sky: [0x8CBBD4, 0xBBD8E4, 0xE3E8DA, 0xEFE0C9],
              ridge: [0xAFC6CE, 0x8FAFB4, 0x6E9078],
              field: [0x7FA87E, 0x9CBC85],
              sun: 0xFFE9B8, glow: 0xFFE9B8, glowA: 0.55,
              cloud: 0xFFFFFF, cloudA: 0.92,
              stars: 0, light: 1.00,
              track: 0x1C3E4E, trackA: 0.17,
              ink: 0x26404E, inkSoft: 0x47697A),
        .init(t: 0.32,
              sky: [0x6E92B4, 0xB69AA6, 0xE4B189, 0xE9BE92],
              ridge: [0x93A0B4, 0x7C8394, 0x5E6B62],
              field: [0x5F7E67, 0x7A9470],
              sun: 0xFFD79A, glow: 0xFFBE82, glowA: 0.60,
              cloud: 0xF4C3B4, cloudA: 0.90,
              stars: 0, light: 0.92,
              track: 0xFFFFFF, trackA: 0.18,
              ink: 0xFFF6EB, inkSoft: 0xF0DCC9),
        .init(t: 0.65,
              sky: [0x26324A, 0x4A4560, 0x7A5560, 0x96685B],
              ridge: [0x3F4A61, 0x333A4A, 0x262C2E],
              field: [0x232E28, 0x2E3730],
              sun: 0xC98A6A, glow: 0x96685B, glowA: 0.22,
              cloud: 0x3E3D5C, cloudA: 0.85,
              stars: 1, light: 0.72,
              track: 0xFFFFFF, trackA: 0.18,
              ink: 0xFFF6EB, inkSoft: 0xC3B2A4),
        .init(t: 1.00,
              sky: [0x141E33, 0x24293F, 0x453447, 0x6B4740],
              ridge: [0x2A3348, 0x212736, 0x171B1C],
              field: [0x171F1C, 0x212823],
              sun: 0x6B4740, glow: 0x6B4740, glowA: 0.0,
              cloud: 0x2A2A44, cloudA: 0.0,
              stars: 1, light: 0.78,
              track: 0xFFFFFF, trackA: 0.18,
              ink: 0xF3E7D8, inkSoft: 0xC3B2A4)
    ]

    /// Where the real clock sits on the sit's 0 (full day) to 1 (night)
    /// scale: full day from 8 to half past 5, sunset colours toward half past
    /// 7, night from half past 9 to 5, and the sunset stops run backwards for
    /// dawn. Fixed hours, not the local sunset: close enough to read as the
    /// right time of day without asking anyone for their location.
    static func clockProgress(at date: Date = Date(), calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        var h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        #if DEBUG
        // VALLEY_HOUR=<0...24> shows the valley at any hour on a simulator.
        if let raw = ProcessInfo.processInfo.environment["VALLEY_HOUR"], let forced = Double(raw) { h = forced }
        #endif
        let points: [(Double, Double)] = [(0, 1), (5, 1), (6.5, 0.32), (8, 0), (17.5, 0),
                                          (19.5, 0.32), (20.5, 0.65), (21.5, 1), (24, 1)]
        for i in 0..<(points.count - 1) where h >= points[i].0 && h <= points[i + 1].0 {
            let (h0, p0) = points[i], (h1, p1) = points[i + 1]
            return p0 + (p1 - p0) * (h - h0) / (h1 - h0)
        }
        return 0
    }

    /// The valley as it looks at this moment, for type drawn on its sky and
    /// for the grass a page continues under it.
    static var now: DayLight { at(clockProgress()) }

    static func at(_ progress: Double) -> DayLight {
        let t = min(max(progress, 0), 1)
        var lo = stops[0], hi = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) where t >= stops[i].t && t <= stops[i + 1].t {
            lo = stops[i]; hi = stops[i + 1]
        }
        let span = hi.t - lo.t
        let k = span <= 0 ? 0 : (t - lo.t) / span

        func c(_ a: UInt32, _ b: UInt32, _ alpha: Double = 1) -> Color {
            blend(a, b, k).opacity(alpha)
        }
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }

        return DayLight(
            sky: (0..<4).map { c(lo.sky[$0], hi.sky[$0]) },
            ridge: (0..<3).map { c(lo.ridge[$0], hi.ridge[$0]) },
            field: (0..<2).map { c(lo.field[$0], hi.field[$0]) },
            sun: c(lo.sun, hi.sun),
            glow: c(lo.glow, hi.glow, mix(lo.glowA, hi.glowA)),
            cloud: c(lo.cloud, hi.cloud),
            cloudOpacity: mix(lo.cloudA, hi.cloudA),
            starOpacity: mix(lo.stars, hi.stars),
            light: mix(lo.light, hi.light),
            ringTrack: c(lo.track, hi.track, mix(lo.trackA, hi.trackA)),
            ink: c(lo.ink, hi.ink),
            inkSoft: c(lo.inkSoft, hi.inkSoft)
        )
    }

    private static func blend(_ a: UInt32, _ b: UInt32, _ k: Double) -> Color {
        func part(_ v: UInt32, _ shift: UInt32) -> Double {
            Double((v >> shift) & 0xFF) / 255
        }
        return Color(red: part(a, 16) + (part(b, 16) - part(a, 16)) * k,
                     green: part(a, 8) + (part(b, 8) - part(a, 8)) * k,
                     blue: part(a, 0) + (part(b, 0) - part(a, 0)) * k)
    }

    /// Fixed, not random: a sky that reshuffles its stars every redraw is a
    /// sky nobody can settle under.
    static let stars: [(x: Double, y: Double, alpha: Double)] = [
        (0.35, 0.39, 0.35), (0.52, 0.35, 0.90), (0.79, 0.09, 0.90), (0.06, 0.35, 0.60),
        (0.75, 0.19, 0.35), (0.65, 0.39, 0.90), (0.65, 0.30, 0.90), (0.24, 0.19, 0.90),
        (0.24, 0.38, 0.60), (0.06, 0.09, 0.35), (0.80, 0.07, 0.60), (0.08, 0.22, 0.60),
        (0.81, 0.29, 0.90), (0.59, 0.30, 0.90), (0.78, 0.33, 0.35), (0.51, 0.11, 0.35),
        (0.22, 0.36, 0.35), (0.38, 0.32, 0.90), (0.43, 0.31, 0.90), (0.54, 0.27, 0.90),
        (0.79, 0.31, 0.90), (0.34, 0.26, 0.90)
    ]
}

#Preview("Arrive") { ValleyScene(progress: 0) }
#Preview("Dusk") { ValleyScene(progress: 1) }
