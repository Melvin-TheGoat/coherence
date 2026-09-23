import SwiftUI

/// Otto as bright as your practice has kept him (`OttoAura`), for Home.
///
/// **Three drawings and the rig** (Melvin, 2026-09-21: he gets sad, and he
/// lives on Home). Low, Frustrated and Curious are still drawings, and they
/// hold still on purpose: a slumped sloth that bobs reads as a toy. From
/// Progressing up he is the Rive rig sitting cross-legged, breathing through
/// the mesh, so being alive is itself part of the reward. In flow adds a glow
/// and one orbit of light; Enlightened adds a second orbit, sparks, ripples on
/// the ground, and he lifts off it.
///
/// The aura is drawn here rather than baked into art, the same call as the
/// mockup (`mockups/otto-aura.html`): painted glow cannot move, and a glow
/// cut off a dark background turns to mud on the cream.
///
/// Everything outside the figure's own frame is a background or an overlay,
/// so the glow never moves the bubble beside him.
struct OttoAuraFigure: View {
    let stage: OttoAura.Stage
    /// The square frame Home gives him.
    var size: CGFloat
    @ObservedObject var rig: OttoRigHolder
    /// Bumped by a tap on him: he jiggles (`OttoJiggle`). His glow and
    /// orbits hold still, because it is Otto being poked, not the light.
    var jiggle: Int = 0

    @State private var lifted = false

    var body: some View {
        figure
            .ottoJiggle(jiggle)
            .frame(width: size, height: size, alignment: .bottom)
            .background { if stage >= .inFlow { glow } }
            .background { if stage >= .inFlow { AuraOrbits(size: size, half: .back, stage: stage) } }
            .overlay { if stage >= .inFlow { AuraOrbits(size: size, half: .front, stage: stage) } }
            .overlay { if stage == .enlightened { AuraSparks(size: size) } }
            .offset(y: stage == .enlightened ? -size * (lifted ? 0.13 : 0.07) : 0)
            .background(alignment: .bottom) { if stage == .enlightened { AuraRipples(size: size) } }
            .onAppear { setLift() }
            .onChange(of: stage) { _, _ in setLift() }
            .accessibilityElement()
            .accessibilityLabel("Otto, \(Self.mood(stage))")
    }

    @ViewBuilder private var figure: some View {
        switch stage {
        case .low, .frustrated, .curious:
            // Heights follow the drawings' own proportions on the sheet they
            // came from, so a slumped Otto is shorter than a curious one
            // rather than stretched to the same height.
            Image(Self.asset(stage))
                .resizable()
                .scaledToFit()
                .frame(height: size * Self.drawnHeight(stage))
        case .progressing, .inFlow, .enlightened:
            // No explicit width: a square frame letterboxes the 425 x 522
            // artboard and hangs it bottom LEFT, which drew him a thumb's
            // width left of his own cushion (Melvin, 2026-09-22).
            OttoRiveView(size: size, pose: .meditating, rig: rig)
        }
    }

    private var glow: some View {
        let d = size * (stage == .enlightened ? 2.3 : 1.85)
        return Circle()
            .fill(RadialGradient(colors: [AppColor.auraGlow.opacity(0.75),
                                          AppColor.auraGlow.opacity(0.32),
                                          AppColor.auraGlow.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: d / 2))
            .frame(width: d, height: d)
            .offset(y: -size * 0.02)
            .allowsHitTesting(false)
    }

    private func setLift() {
        guard stage == .enlightened else {
            withAnimation(.easeOut(duration: 0.3)) { lifted = false }
            return
        }
        lifted = false
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { lifted = true }
    }

    static func asset(_ stage: OttoAura.Stage) -> String {
        switch stage {
        case .low: return "OttoLow"
        case .frustrated: return "OttoFrustrated"
        case .curious: return "OttoCurious"
        default: return OttoPose.meditating.asset
        }
    }

    /// Share of the frame each still drawing stands, from its height on the
    /// sheet (low 558, frustrated 585, curious 623 pixels). Matched to the
    /// rig's sitting Otto by HEAD width, measured in the valley on Home
    /// (2026-09-21, after Aziz's rig update: curious 402 px against the rig's
    /// 360 at 1.04), because a face is what people compare between stages.
    static func drawnHeight(_ stage: OttoAura.Stage) -> CGFloat {
        let curious: CGFloat = 0.95
        switch stage {
        case .low: return curious * 558 / 623
        case .frustrated: return curious * 585 / 623
        default: return curious
        }
    }

    static func mood(_ stage: OttoAura.Stage) -> String {
        switch stage {
        case .low: return "slumped and a little sad"
        case .frustrated: return "grumpy"
        case .curious: return "curious"
        case .progressing: return "meditating"
        case .inFlow: return "glowing"
        case .enlightened: return "glowing and floating"
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

/// One or two tilted orbits of light around his middle. Drawn twice, once
/// behind him and once in front, each keeping only its half of every ring, so
/// the rings pass behind his back and across his lap.
private struct AuraOrbits: View {
    enum Half { case back, front }
    let size: CGFloat
    let half: Half
    let stage: OttoAura.Stage

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ring(width: 1.22, height: 0.28, y: 0.66, tilt: -7, phase: t / 3.2)
                if stage == .enlightened {
                    ring(width: 1.08, height: 0.24, y: 0.86, tilt: 9, phase: -t / 4.6)
                }
            }
            .frame(width: size, height: size)
        }
        .allowsHitTesting(false)
    }

    /// Ellipse paths start at the right-hand point and run clockwise, so the
    /// first half of a trim is the half nearer the viewer.
    private func ring(width: CGFloat, height: CGFloat, y: CGFloat, tilt: Double, phase: Double) -> some View {
        let span: ClosedRange<Double> = half == .front ? 0...0.5 : 0.5...1
        let head = phase - phase.rounded(.down)
        return ZStack {
            Ellipse()
                .trim(from: span.lowerBound, to: span.upperBound)
                .stroke(AppColor.auraRing.opacity(0.65), lineWidth: 1.6)
            // The travelling light. Warm, not white: a white stroke crossing
            // his lap read as a stick at this size.
            ForEach(Array(Self.pieces(head: head, length: 0.12, within: span).enumerated()), id: \.offset) { _, piece in
                Ellipse()
                    .trim(from: piece.lowerBound, to: piece.upperBound)
                    .stroke(AppColor.auraGlow, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .shadow(color: AppColor.auraGlow, radius: 3)
            }
        }
        .frame(width: size * width, height: size * height)
        .rotationEffect(.degrees(tilt))
        .position(x: size / 2, y: size * y)
    }

    /// The comet runs from `head` back `length`, wrapping past zero; this
    /// returns the parts of it that fall inside `span`.
    static func pieces(head: Double, length: Double, within span: ClosedRange<Double>) -> [ClosedRange<Double>] {
        let start = head - length
        let raw: [ClosedRange<Double>] = start >= 0 ? [start...head] : [0...head, (1 + start)...1]
        return raw.compactMap { r in
            let lo = max(r.lowerBound, span.lowerBound), hi = min(r.upperBound, span.upperBound)
            return lo < hi ? lo...hi : nil
        }
    }
}

/// Sparks of light drifting up around him at Enlightened.
private struct AuraSparks: View {
    let size: CGFloat
    private static let spots: [(x: CGFloat, y: CGFloat, delay: Double)] = [
        // Beside and below his head only: above it sits the date.
        (-0.2, 0.28, 0.0), (1.2, 0.22, 0.7), (-0.14, 0.66, 1.3), (1.14, 0.6, 0.4),
        (0.02, 0.1, 1.9), (0.98, 0.06, 1.1),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(Self.spots.enumerated()), id: \.offset) { _, s in
                    let wave = 0.5 + 0.5 * sin((t + s.delay) * 2 * .pi / 2.6)
                    Circle()
                        .fill(AppColor.auraRing)
                        .frame(width: 5, height: 5)
                        .shadow(color: AppColor.auraGlow, radius: 4)
                        .opacity(0.2 + 0.8 * wave)
                        .position(x: size * s.x, y: size * s.y - 6 * wave)
                }
            }
            .frame(width: size, height: size)
        }
        .allowsHitTesting(false)
    }
}

/// Rings spreading on the ground under him while he floats.
private struct AuraRipples: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let p = (t / 2.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Ellipse()
                        .stroke(AppColor.auraRing.opacity(0.8 * (1 - p)), lineWidth: 1.6)
                        .frame(width: size * 1.1, height: size * 0.22)
                        .scaleEffect(0.3 + 0.85 * p)
                }
            }
            .frame(width: size * 1.1, height: size * 0.22)
            .offset(y: size * 0.08)
        }
        .allowsHitTesting(false)
    }
}
