import SwiftUI
import SwiftData

/// Otto as bright as your practice has kept him (`OttoAura`), for Home.
///
/// **Seven drawings from one sheet** (Melvin, 2026-09-22,
/// `mockups/otto-v4/sheet.png`): withered and gray with bugs on him at the
/// bottom, full caramel in the middle, levitating in light at the top. They
/// were drawn together so the change between any two is even, and cut onto
/// one shared canvas by `tools/otto_aura_cut.swift` so his body is the same
/// size and sits on the same line in all seven.
///
/// **The light is in the art.** The motes, the halo and the swirl were drawn
/// with him and cut out as real translucent light, so nothing is layered on
/// top here. What moves is the float: from Radiant up he has left the ground
/// and drifts up and down on it. (The Rive rig takes these over next, with
/// bugs that come and go and light that swirls.)
///
/// Everything outside the figure's own frame is an overflow, so the light
/// never moves the bubble beside him.
struct OttoAuraFigure: View {
    let stage: OttoAura.Stage
    /// Which of the rig's thirteen drawings (`OttoAura.look(level:)`). Nil
    /// draws the stage's own; the stills only ever have the seven.
    var look: Int? = nil
    /// The square frame Home gives him.
    var size: CGFloat
    @ObservedObject var rig: OttoRigHolder
    /// Bumped by a tap on him: he jiggles (`OttoJiggle`).
    var jiggle: Int = 0
    /// Change look at once rather than cross-fading (`OttoAuraRig.snap`),
    /// for a screen where a finger drags him through his looks.
    var snap: Bool = false
    /// The hat he wears (`HatCatalog`), from the shop (2026-09-27):
    /// **overrides** the worn hat read from `Preferences` below, so a
    /// caller previewing a hat (the Store tab, trying one on before buying)
    /// can show it before it is actually worn. Every other caller (Home
    /// included) leaves this nil and gets whatever is actually worn, with
    /// no change needed at the call site — `ContentView` never has to know
    /// the shop exists.
    var hatID: String? = nil

    /// Read directly rather than threaded down from Home, since Home's own
    /// file is owned elsewhere and should not need editing for the shop to
    /// show up on it. Home is exactly the case `hatID` is nil for.
    @Query(sort: \Preferences.createdAt) private var shopPrefsRows: [Preferences]
    private var effectiveHatID: String? {
        Self.previewHat ?? hatID ?? shopPrefsRows.first?.wornHatIDValue
    }

    /// PREVIEW_HAT=<id> (DEBUG) puts a hat on him anywhere, to check its fit.
    static var previewHat: String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PREVIEW_HAT"]
        #else
        return nil
        #endif
    }

    /// How far a hat reaches above the top of his fur, in points, for a
    /// figure drawn `size` tall: what a screen that puts words above his head
    /// has to leave room for (Home's bubble). Reads the art's own shape, so a
    /// flat halo is not given a beanie's room.
    static func hatRise(_ id: String?, size: CGFloat) -> CGFloat {
        guard let id else { return 0 }
        let canvas = size * 0.95 / bodyShare
        let fit = HatArt.fit(for: id)
        let box = canvas * canvasAspect * fit.width
        var drawn = box
        if let image = UIImage(named: "hat-\(id)"), image.size.width > 0 {
            drawn = min(box, box * image.size.height / image.size.width)
        }
        return max(0, drawn - box * fit.sink)
    }

    @State private var bob = false
    /// A free-running oscillator for the RIG's own float, which the app
    /// cannot read back (see `rigHatLift` below). Runs unconditionally; it
    /// only ever moves the hat when `rigHatLift` decides to use it.
    @State private var rigBob = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The animated seven (`OttoAura.riv`). Nil until that file ships, and
    /// whenever it will not load; the stills below stand in either way.
    @StateObject private var aura = OttoAuraRigHolder()

    /// The shared canvas, from `mockups/otto-v4/canvas.json`: 664 x 744, his
    /// body's bottom at 87.2% of the height, and Steady's body 82% of it.
    static let canvasAspect: CGFloat = 664.0 / 744.0
    static let baseline: CGFloat = 0.872
    static let bodyShare: CGFloat = 0.82

    var body: some View {
        let canvas = size * 0.95 / Self.bodyShare
        ZStack(alignment: .top) {
            drawing
            hatOverlay(canvas: canvas)
        }
            .frame(width: canvas * Self.canvasAspect, height: canvas)
            // Hang his baseline on the bottom of the frame; the light under
            // him (Nirvana's swirl, Radiant's motes) overflows below it.
            .offset(y: canvas * (1 - Self.baseline))
            .ottoJiggle(jiggle)
            // The rig floats him itself; only the stills need lifting here.
            // The hat, inside this same ZStack, rides along for free.
            .offset(y: aura.rig == nil && stage.floats ? -size * (bob ? 0.085 : 0.05) : 0)
            .frame(width: size, height: size, alignment: .bottom)
            .animation(.spring(duration: 0.5, bounce: 0.2), value: stage)
            .onAppear { setBob(); startRigBob() }
            .onChange(of: stage) { _, _ in setBob() }
            .accessibilityElement()
            .accessibilityLabel("Otto, \(Self.mood(stage))\(effectiveHatID != nil ? ", wearing a hat" : "")")
    }

    // MARK: - The hat

    /// Where the hat sits, drawn in the SAME 664 x 744 canvas frame
    /// `drawing` renders in, so a fraction measured off that canvas is a
    /// fraction of this view with no further conversion.
    ///
    /// **Measured, not guessed**, 2026-09-27: the topmost fur pixel (any
    /// channel below 178, the darkness threshold `tools/otto_aura_cut.swift`
    /// already uses to find him against the paper) in a 260pt band centred
    /// on his body's own x (332 of 664), scanned on the real `OttoAura1`
    /// through `OttoAura7` art. Nirvana's tuft sits LOWER in frame than
    /// Withered's (he is drawn bigger and closer for the brighter stages) —
    /// that is what the source art actually does, not a bug in the scan.
    private static let headTopFraction: [OttoAura.Stage: CGFloat] = [
        .withered: 67.0 / 744, .faded: 59.0 / 744, .stirring: 46.0 / 744,
        .steady: 40.0 / 744, .bright: 64.0 / 744, .radiant: 112.0 / 744,
        .nirvana: 167.0 / 744
    ]

    /// The same, indexed by the rig's LOOK (1 to 13): the seven stages sit
    /// at the odd numbers exactly; the six in-between looks are a straight
    /// line between their neighbours, matching how those drawings are
    /// themselves described ("a body halfway between each pair").
    private static func headTopFraction(look: Int) -> CGFloat {
        let stages = OttoAura.Stage.allCases   // declared 1...7, already in order
        let clamped = min(max(look, 1), 13)
        if clamped % 2 == 1 {
            return headTopFraction[stages[(clamped - 1) / 2]] ?? 0.08
        }
        let lower = headTopFraction[stages[clamped / 2 - 1]] ?? 0.08
        let upper = headTopFraction[stages[clamped / 2]] ?? 0.08
        return (lower + upper) / 2
    }

    // Each hat's size and how far it sits down on him: `HatArt.fit`.

    /// The rig's own vertical motion for a floating look, so the hat can
    /// approximate it: `Lift`, a fixed per-look rise, plus `Bob`, a slow
    /// oscillation. **Read straight off `tools/otto_aura_rig_build.py`**,
    /// which built `OttoAura.riv`: `Lift` keys `{6: -26, 7: -40}` (canvas
    /// units, stage 6 = Radiant, stage 7 = Nirvana, everything below zero),
    /// and the `Float` timeline bobs `Bob` between 0 and -10 over its own
    /// 5.0 s duration (300 frames at 60 fps). **This can only ever be an
    /// approximation**: the rig runs that animation internally and SwiftUI
    /// cannot read its live value back, so the hat plays an independent
    /// oscillation of the same amplitude and period rather than a true
    /// mirror — close enough that it rides with him instead of sitting
    /// still while he moves.
    ///
    /// Applied only from look 9 (Bright) up, where the rig's own Float
    /// state starts to engage.
    private func rigHatLift(look: Int, canvas: CGFloat) -> CGFloat {
        guard aura.rig != nil, look >= 9 else { return 0 }
        // Bright (9) carries no Lift keyframe in the build script; only
        // Radiant (11) and Nirvana (13) do. The in-between looks (10, 12)
        // are a straight line between their neighbours, the same rule
        // `headTopFraction(look:)` uses.
        let lift: CGFloat
        switch look {
        case 9: lift = 0
        case 10: lift = -13
        case 11: lift = -26
        case 12: lift = -33
        default: lift = -40
        }
        let bobAmplitude: CGFloat = 10.0 / 744
        return canvas * (lift / 744 - (rigBob ? bobAmplitude : 0))
    }

    @ViewBuilder
    private func hatOverlay(canvas: CGFloat) -> some View {
        if let effectiveHatID {
            let effectiveLook = look ?? stage.look
            let headFraction = Self.headTopFraction(look: effectiveLook)
            let fit = HatArt.fit(for: effectiveHatID)
            let hatSize = canvas * Self.canvasAspect * fit.width
            let sink = hatSize * fit.sink
            let bottomY = canvas * headFraction + sink
            HatArt(id: effectiveHatID, size: hatSize)
                .position(x: canvas * Self.canvasAspect * (332.0 / 664.0), y: bottomY - hatSize / 2)
                .offset(y: rigHatLift(look: effectiveLook, canvas: canvas))
                .allowsHitTesting(false)
        }
    }

    /// Runs for the figure's whole lifetime; `rigHatLift` is the only reader
    /// and it only ever consumes this above look 9, so the cost elsewhere is
    /// one Bool quietly flipping every 2.5 s.
    private func startRigBob() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { rigBob = true }
    }

    /// How much wider than his canvas the rig is drawn. The moth that visits
    /// the three lowest looks flies in from beyond the left edge of the
    /// screen and away past the right (Melvin, 2026-09-23: it "disappears at
    /// a cut off"), and a Rive view cannot draw outside its own bounds. So
    /// the view is this much wider, centred on him; the artboard does not
    /// clip, and `.contain` still sizes him by height, so he is exactly where
    /// and as big as he was. Only the layout footprint stays the canvas.
    static let flightSpan: CGFloat = 2.6

    /// How much taller than his canvas the rig is drawn from this look up
    /// (Bright and above, where the light and the halo rise over his head).
    static let tallFromLook = 9
    static let headroom: CGFloat = 1.6

    /// The rig when it loaded, else the still for this stage. Both are the
    /// same 664 x 744 canvas, so they frame identically.
    @ViewBuilder private var drawing: some View {
        if let rig = aura.rig {
            GeometryReader { geo in
                // The rig can only draw inside its own view, and `.contain`
                // fills that view's LIMITING side with the artboard, so only
                // one side can be given room without making him bigger. The
                // low looks need width (the moth flies off past the screen's
                // edges); the bright looks need height: he floats and wears a
                // halo above his head, which was cut off flat along the top of
                // the view (Aziz, 2026-09-23). So the view is wide for one and
                // tall for the other, bottom-aligned both ways, and he is the
                // same size and in the same place in either.
                let tall = (look ?? stage.look) >= Self.tallFromLook
                rig.viewModel.view()
                    .frame(width: geo.size.width * (tall ? 1 : Self.flightSpan),
                           height: geo.size.height * (tall ? Self.headroom : 1))
                    .position(x: geo.size.width / 2,
                              y: geo.size.height - geo.size.height * (tall ? Self.headroom : 1) / 2)
            }
            // Only the drawing is wider: taps belong to whatever is on top.
            .allowsHitTesting(false)
            .onAppear {
                rig.snap = snap
                rig.stage = look ?? stage.look
            }
            .onChange(of: snap) { _, new in rig.snap = new }
            .onChange(of: stage) { _, new in rig.stage = look ?? new.look }
            .onChange(of: look) { _, new in rig.stage = new ?? stage.look }
        } else {
            Image(Self.asset(stage))
                .resizable()
                .scaledToFit()
        }
    }

    /// Up and down on a slow breath once he floats, and still on the ground
    /// below Radiant.
    private func setBob() {
        guard stage.floats, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.3)) { bob = false }
            return
        }
        bob = false
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { bob = true }
    }

    static func asset(_ stage: OttoAura.Stage) -> String { "OttoAura\(stage.rawValue)" }

    static func mood(_ stage: OttoAura.Stage) -> String {
        switch stage {
        case .withered: return "gray and worn out, with bugs on him"
        case .faded: return "faded and looking at the ground"
        case .stirring: return "coming back to life"
        case .steady: return "healthy and calm"
        case .bright: return "bright, with a little light around him"
        case .radiant: return "glowing and floating"
        case .nirvana: return "floating in a halo of light"
        }
    }
}

/// The glow Otto gains when a session lands: light swelling off him, a few
/// sparks rising, and what he gained (Melvin, 2026-09-22: the first thing
/// after meditating should be Otto gaining aura, with a nice animation).
///
/// One animated `phase` drives all of it, so the whole burst is a single
/// curve and nothing can drift apart. It plays once, on appear, because it is
/// put on screen by the session landing.
struct AuraGainBurst: View {
    /// Points of glow gained. 0 draws the light and no number, which is a
    /// second session on a day already counted.
    let gain: Int
    /// Otto's height, which the burst is drawn around.
    let size: CGFloat

    /// Bumped on appear, because a keyframe animation plays when its trigger
    /// changes and this view is put on screen by the session landing.
    @State private var go = 0

    private static let sparkCount = 11

    var body: some View {
        Color.clear
            .frame(width: size * 2, height: size * 2)
            .keyframeAnimator(initialValue: 0.0, trigger: go) { view, phase in
                view.overlay { burst(phase) }
            } keyframes: { _ in
                CubicKeyframe(1.0, duration: 2.1)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { go += 1 }
    }

    /// **The phase is passed in, not derived from animated state.** An
    /// `.opacity(f(phase))` under `withAnimation` interpolates between its
    /// first and last values only, and this curve rises and falls, so both
    /// ends are invisible and the whole burst never appeared (2026-09-22).
    /// A keyframe animator re-runs this for every frame.
    @ViewBuilder private func burst(_ phase: Double) -> some View {
        let fade: Double = sin(.pi * min(1, phase))
        ZStack {
            glow(phase, fade: fade)
            ForEach(0..<Self.sparkCount, id: \.self) { spark($0, phase, fade: fade) }
            if gain > 0 { plus(phase) }
        }
    }

    private func glow(_ phase: Double, fade: Double) -> some View {
        Circle()
            .fill(RadialGradient(colors: [AppColor.auraGlow.opacity(0.85),
                                          AppColor.auraGlow.opacity(0.35),
                                          AppColor.auraGlow.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size * 0.95))
            .frame(width: size * 1.9, height: size * 1.9)
            .scaleEffect(0.45 + 0.75 * phase)
            .opacity(fade * 0.85)
    }

    /// Sparks lift off him and spread as they go, the way embers do.
    private func spark(_ i: Int, _ phase: Double, fade: Double) -> some View {
        let fraction: Double = Double(i) / Double(Self.sparkCount - 1)
        let angle: Double = -Double.pi / 2 + (fraction - 0.5) * 2.4
        let eased: Double = 1 - pow(1 - phase, 2.4)
        let distance: Double = Double(size) * (0.2 + 0.8 * eased)
        let wobble: Double = (fraction * 7).truncatingRemainder(dividingBy: 1)
        let dot: CGFloat = size * CGFloat(0.04 + 0.025 * wobble)
        let dx: CGFloat = CGFloat(cos(angle) * distance)
        let dy: CGFloat = CGFloat(sin(angle) * distance) - size * 0.1
        let colour: Color = i.isMultiple(of: 3) ? AppColor.auraRing : AppColor.auraGlow
        return Circle()
            .fill(colour)
            .frame(width: dot, height: dot)
            .offset(x: dx, y: dy)
            .opacity(fade)
            .scaleEffect(0.6 + 0.9 * (1 - phase))
    }

    /// Beside his head, not above it: above is where his bubble is.
    private func plus(_ phase: Double) -> some View {
        let lift: CGFloat = size * CGFloat(0.02 - 0.37 * phase)
        let arriving: Double = min(1, phase / 0.12)
        let leaving: Double = 1 - max(0, (phase - 0.5) / 0.5)
        return Text("+\(gain)%")
            .font(DisplayFont.display(26, .heavy))
            .foregroundStyle(AppColor.auraRing)
            .shadow(color: AppColor.auraGlow.opacity(0.7), radius: 8)
            .offset(x: size * 0.48, y: lift)
            .opacity(min(arriving, leaving))
    }
}

/// A tap on Otto jiggles him (Melvin, 2026-09-22): a quick squash from his
/// feet and a wobble that dies away, like poking something soft. It is plain
/// SwiftUI on the figure's frame, so the Rive rig and the still drawings
/// react the same way, and the rig keeps breathing underneath it.
///
/// Anchored at the BOTTOM: he is sitting or standing on something, so his
/// feet stay put and the top of him does the moving. Skipped under Reduce
/// Motion, where a tap still does whatever else it does.
struct OttoJiggle: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Wobble {
        /// Vertical scale; the width takes the opposite, so he keeps his bulk.
        var squash: CGFloat = 1
        /// Degrees, about his feet.
        var tilt: Double = 0
    }

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: Wobble(), trigger: trigger) { view, wobble in
                view
                    .scaleEffect(x: 2 - wobble.squash, y: wobble.squash, anchor: .bottom)
                    .rotationEffect(.degrees(wobble.tilt), anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack(\.squash) {
                    CubicKeyframe(0.91, duration: 0.09)
                    SpringKeyframe(1.05, duration: 0.16, spring: Spring(duration: 0.3, bounce: 0.4))
                    SpringKeyframe(1.0, duration: 0.4, spring: Spring(duration: 0.35, bounce: 0.5))
                }
                KeyframeTrack(\.tilt) {
                    CubicKeyframe(-4.5, duration: 0.10)
                    CubicKeyframe(3.5, duration: 0.13)
                    CubicKeyframe(-2.2, duration: 0.12)
                    CubicKeyframe(1.0, duration: 0.11)
                    CubicKeyframe(0, duration: 0.12)
                }
            }
        }
    }
}

extension View {
    /// Jiggle when `trigger` changes. See `OttoJiggle`.
    func ottoJiggle(_ trigger: Int) -> some View { modifier(OttoJiggle(trigger: trigger)) }
}

#if DEBUG
/// Testing hooks for Otto's state on a real phone (Settings > Testing).
enum DebugOtto {
    static let stageKey = "debug.ottoStage"

    /// A level that shows this drawing (`OttoAura.look(level:)`), for the
    /// glow card beside him and the stage his mood follows.
    static func level(forLook look: Int) -> Int {
        [0, 0, 10, 20, 30, 40, 47, 50, 60, 70, 77, 80, 90, 100][min(max(look, 1), 13)]
    }

    /// The seven stages by their own names, the six drawings between them by
    /// the pair they sit between.
    static func name(look: Int) -> String {
        let stages = ["Withered", "Faded", "Stirring", "Steady", "Bright", "Radiant", "Nirvana"]
        if look % 2 == 1 { return "\(look) \(stages[(look - 1) / 2])" }
        return "\(look) Between \(stages[look / 2 - 1]) and \(stages[look / 2])"
    }
}
#endif
