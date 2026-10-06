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
    /// Which of the aura rig's thirteen drawings Home shows
    /// (`OttoAura.look(level:)`); nil is the stage's own.
    var auraLook: Int? = nil
    /// Change look at once instead of cross-fading, where a finger drags him
    /// through his looks (onboarding's stress bar).
    var auraSnap: Bool = false

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

    /// Grasshoppers in this scene's own meadow.
    var meadowLife: Bool = true

    /// A screen stands its OWN Otto on the meadow, on top of this scene, with
    /// his feet on the cushion's ground line (onboarding's welcome). The
    /// scene then splits its grasshoppers at that line as if he were its own,
    /// draws only the farther ones (behind him), and leaves the nearer ones
    /// to the screen, which draws them above him with the same `seed`
    /// (`ValleyFrontLife`). Without this a grasshopper in the scene could only
    /// ever pass behind that Otto, and read as hopping through him.
    var standingFigure: Bool = false

    /// Keep the cushion but not the sloth on it: a screen seats its own Otto
    /// there, a video clip of him doing something the rig cannot (onboarding's
    /// "Let's personalize", where he writes in a notepad). He fades rather
    /// than vanishing, so the handover from the scene's Otto to the clip is a
    /// cross-fade in the same spot.
    var figureHidden: Bool = false

    /// Fixes the birds and grasshoppers. Nil picks one at random; a screen
    /// that draws part of the life itself passes the same seed to both.
    var seed: UInt64? = nil

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

    /// Raise Otto and his cushion by this much, and nothing else.
    ///
    /// The Ready screen's Sound and Silence pills are Home's card size
    /// (Melvin, 2026-09-23), and on most phones they would sit on his lap.
    /// Only the sitter moves: lifting the whole painting moved the horizon
    /// and the sun with him, and it would have to slide the entire valley
    /// back down when the sit takes over. The sit itself passes 0, so a
    /// Ready screen that eases this back to 0 as the countdown starts hands
    /// over with no jump.
    var ottoLift: CGFloat = 0

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

                // Depth (Aziz, 2026-09-23): the field was one flat green, so
                // a grasshopper crossing it had nothing to be near or far
                // in. Haze where the grass meets the ridge, and the ground
                // darkening as it comes toward the viewer, the way distance
                // actually reads outdoors.
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.22), location: 0),
                    .init(color: .white.opacity(0), location: 0.28),
                    .init(color: .clear, location: 0.55),
                    .init(color: Color(red: 0.16, green: 0.30, blue: 0.14).opacity(0.20), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                    .frame(width: w, height: h * 0.34)
                    .offset(y: h * 0.33)
                    .allowsHitTesting(false)

                // Birds sit in front of the ridges and the field wash (or
                // the field, drawn after, would paint straight over one
                // dipping near the ridge line) and stay well clear of
                // Otto's head by construction, via `avoidRect`.
                if showLife {
                    ValleyLife(layer: .sky, size: geo.size, scale: s, seed: seed ?? lifeSeed, avoid: avoidRect)
                }

                // Everything alive takes the hour's light as one group, so
                // the cushion, the sloth and the flowers can never disagree
                // about what time it is. A grasshopper crossing farther back
                // than his cushion is drawn in here, behind him.
                groundScene(size: geo.size, scale: s, life: showLife && meadowLife)
                    .colorMultiply(Color(white: day.light))

                // And one crossing nearer than his cushion, in front of him.
                if showLife && meadowLife && !standingFigure {
                    ValleyLife(layer: .meadowFront, size: geo.size, scale: s, seed: seed ?? lifeSeed,
                               avoid: avoidRect, depthSplit: grasshopperSplit(size: geo.size))
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
        guard showsFigure || standingFigure, !ottoInCorner else { return nil }
        let seated = ottoHeight(scale: s)
        // A standing Otto's head is higher than a seated one's.
        let top = SitLayout.ottoTop(in: size) - 20 - ottoLift - (standingFigure ? 60 * s : 0)
        let cushionBottom = SitLayout.cushionBottom(in: size) + 22 * s - ottoLift
        let ottoBottom = size.height * (1 - 0.24) + 12 - ottoLift
        let bottom = max(cushionBottom, ottoBottom)
        let halfWidth = max(168 * s, seated * 0.85) / 2 + 24
        return CGRect(x: size.width / 2 - halfWidth, y: top,
                      width: halfWidth * 2, height: max(20, bottom - top))
    }

    /// The feet line that decides whether a grasshopper passes behind Otto
    /// or in front of him: the bottom of his cushion, where he meets the
    /// grass. Nil with nobody sitting in the middle of the meadow.
    private func grasshopperSplit(size: CGSize) -> CGFloat? {
        guard showsFigure || standingFigure, !ottoInCorner else { return nil }
        return SitLayout.cushionBottom(in: size) - ottoLift
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

    private func groundScene(size: CGSize, scale s: CGFloat, life: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Meadow(scale: s)
                .frame(width: size.width, height: size.height)

            if life {
                ValleyLife(layer: .meadowBehind, size: size, scale: s, seed: seed ?? lifeSeed,
                           avoid: nil, depthSplit: grasshopperSplit(size: size))
            }

            // The cushion gives him somewhere to be rather than floating on
            // grass, and it is the one warm object in a cool frame.
            Cushion()
                .frame(width: 168 * s, height: 44 * s)
                .position(x: size.width / 2,
                          y: SitLayout.cushionBottom(in: size) - 22 * s - ottoLift)
                .standsInMeadow(feetY: SitLayout.cushionFront(in: size, scale: s) - ottoLift,
                                scale: s, sceneSize: size)
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
                    OttoAuraFigure(stage: aura, look: auraLook, size: tall, rig: rig, jiggle: jiggle,
                                   snap: auraSnap)
                } else {
                    OttoRiveView(size: tall, pose: pose, rig: rig)
                }
            }
            .opacity(figureHidden ? 0 : 1)
            .animation(.easeInOut(duration: 0.35), value: figureHidden)
            .position(x: ottoInCorner ? Self.cornerX : size.width / 2,
                      y: ottoInCorner ? Self.cornerY
                                      : size.height * (1 - 0.24) - seated / 2 - ottoLift)
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
}


#Preview("Arrive") { ValleyScene(progress: 0) }
#Preview("Dusk") { ValleyScene(progress: 1) }
