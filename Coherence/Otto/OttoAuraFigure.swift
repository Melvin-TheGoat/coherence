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

    @State private var lifted = false

    var body: some View {
        figure
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
            OttoRiveView(size: size, pose: .meditating, width: size, rig: rig)
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
    /// sheet (low 558, frustrated 585, curious 623 pixels). Curious runs a
    /// little past the frame because these drawings carry a smaller head than
    /// the rig's sitting Otto; matched by height alone they read as a size
    /// smaller. It overflows upward only, into the sky.
    static func drawnHeight(_ stage: OttoAura.Stage) -> CGFloat {
        let curious: CGFloat = 1.04
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
