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
                // The painting itself (sky, sun, clouds, ridges, field) lives
                // in ValleyPainting.swift, which the home screen widget
                // compiles too, so its valley is this one.
                ValleySky(day: day, hour: p, size: geo.size, scale: s)

                clouds(scale: s, size: geo.size, hour: p, day: day)

                ValleyLand(day: day, size: geo.size)

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

    /// The clouds drift slowly all the time, wrapping round, so the sky is
    /// never a screenshot (Melvin, 2026-09-23: "i want the clouds to always
    /// be slowly drifting"). It used to move only with `progress`, which held
    /// every sky but the sit's perfectly still.
    private func clouds(scale s: CGFloat, size: CGSize, hour progress: Double, day: DayLight) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
            ValleyClouds(day: day, hour: progress, size: size, scale: s,
                         time: context.date.timeIntervalSinceReferenceDate)
        }
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
            Cushion.seated(in: size, scale: s, lift: ottoLift)
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


#Preview("Arrive") { ValleyScene(progress: 0) }
#Preview("Dusk") { ValleyScene(progress: 1) }
