import SwiftUI

/// Small wildlife drifting through the valley while nobody is meditating:
/// birds crossing the sky, and now and then one grasshopper hopping slowly
/// across the grass from the left edge to the right.
///
/// Both are pure functions of wall-clock time, the same recipe as
/// `AuraOrbits` / `AuraSparks` in `OttoAuraFigure.swift`: a `TimelineView
/// (.animation)` feeds a `Date`, and every position is computed fresh from
/// `(seed, time)` — nothing here is `@State`, so there is nothing to
/// animate and nothing that can desync from a redraw the clock causes
/// elsewhere on screen. `ValleyScene` hands down one random `seed`,
/// generated once per scene instance (`@State`), so Home's birds and a
/// Friends band's birds fly different patterns rather than mirroring each
/// other.
///
/// Real sprites are in `Shared/Assets.xcassets/Life/` and are drawn in
/// preference to the placeholders below, per species: `BirdA1`...`BirdA4`
/// (a brown sparrow), `BirdB1`...`BirdB4` (a red cardinal), `BirdC1`...
/// `BirdC4` (a blue bird), all facing right (mirrored for right-to-left
/// flight), frames 1/2/3/4 = wings fully up / level / fully down / level
/// again (the glide frame) — all four frames of one bird share a box with
/// the beak in a fixed place, so swapping frames never jitters the bird.
/// `Hopper1`...`Hopper4` (sitting / crouched / mid-jump, legs stretched
/// back / landing) are cropped tight and DIFFER in size frame to frame, so
/// they are drawn bottom-anchored rather than centred, and only frame 3
/// shows while actually airborne. Any missing frame in a set falls back to
/// the drawn placeholder for that one creature, not the whole layer.
struct ValleyLife: View {
    enum Layer { case sky, meadowBehind, meadowFront }

    /// Sky draws birds; the two meadow layers draw the grasshopper, one
    /// behind Otto and one in front of him. Separate places in
    /// `ValleyScene`'s z-order: birds in front of the clouds and ridges, the
    /// grasshopper behind the sitter when it crosses farther back in the
    /// grass and in front of him when it crosses nearer. Both meadow layers
    /// compute the same crossing, and each draws it only on its own side of
    /// `depthSplit`, so it can never be in both or flicker between them.
    var layer: Layer
    var size: CGSize
    var scale: CGFloat
    var seed: UInt64
    /// Otto and his cushion, in this view's local space. Birds stay above
    /// it. `nil` when there is nothing to avoid: no figure on screen, or
    /// Otto tucked in a corner well clear of the meadow.
    var avoid: CGRect?
    /// Where Otto's cushion meets the grass. A grasshopper whose feet land
    /// above this line is farther away and passes behind him. `nil` when
    /// there is no one sitting, and everything is drawn in front.
    var depthSplit: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || size.width < 2 || size.height < 2 {
                Color.clear
            } else {
                TimelineView(.animation) { context in
                    ZStack {
                        switch layer {
                        case .sky: birds(at: context.date.timeIntervalSinceReferenceDate)
                        case .meadowBehind: hoppers(at: context.date.timeIntervalSinceReferenceDate, behind: true)
                        case .meadowFront: hoppers(at: context.date.timeIntervalSinceReferenceDate, behind: false)
                        }
                    }
                }
            }
        }
        .frame(width: max(size.width, 0), height: max(size.height, 0))
        .allowsHitTesting(false)
    }

    // MARK: - Birds

    /// One slot's worth of birds (one to three) crosses roughly every 10s,
    /// jittered ±2s to land the promised "every 8 to 12 seconds or so".
    fileprivate static let birdSlot: Double = 10

    /// Where birds are allowed: open sky, well clear of Otto's head. Falls
    /// back to the top 40% of the frame when there is no figure to clear.
    private var skyBand: ClosedRange<CGFloat> {
        let top = size.height * 0.06
        var bottom = size.height * 0.40
        if let avoid { bottom = min(bottom, avoid.minY - 28) }
        bottom = max(bottom, top + 24)
        return top...bottom
    }

    private func birds(at t: Double) -> some View {
        let slot = Int((t / Self.birdSlot).rounded(.down))
        let sky = skyBand
        let flights = [slot - 1, slot].flatMap {
            BirdFlight.make(seed: seed, slot: $0, sky: sky, sceneWidth: size.width, scale: scale)
        }
        return ForEach(flights) { flight in
            if let pose = flight.pose(at: t) {
                BirdGlyph(pose: pose)
            }
        }
    }

    // MARK: - Grasshoppers

    /// One crossing starts in each window of this many seconds, a few
    /// seconds in, and is over well before the next window: never two at
    /// once, and a quiet stretch of grass between them.
    fileprivate static let hopperSlot: Double = 45

    /// The grass with the flowers in it, as a band of feet lines. The
    /// field starts 66% of the way down the scene and the farthest flowers
    /// stand at 69%, so the top of the band is just below them: the old
    /// band started at 58%, on the ridge, which is why a grasshopper could
    /// be seen hopping in the air above the grass (Melvin, 2026-09-23). The
    /// bottom stays clear of the cards that rise over the near meadow on
    /// Home (the lowest 17% of the scene).
    private var grassBand: ClosedRange<CGFloat> {
        let top = size.height * 0.71
        let bottom = size.height * 0.82
        return min(top, bottom)...max(top, bottom)
    }

    private func hoppers(at t: Double, behind: Bool) -> some View {
        let slot = Int((t / Self.hopperSlot).rounded(.down))
        let band = grassBand
        // The previous window too: a crossing that started late in it can
        // still be on its way across.
        let crossings = [slot - 1, slot].compactMap {
            HopperCrossing.make(seed: seed, slot: $0, sceneWidth: size.width, band: band, scale: scale)
        }.filter { crossing in
            guard let split = depthSplit else { return !behind }
            return (crossing.feetY < split) == behind
        }
        return ForEach(crossings) { crossing in
            if let pose = crossing.pose(at: t) {
                // Nearer flowers in front of it, not under its feet
                // (`standsInMeadow`, Aziz: it looked like landing on petals).
                HopperGlyph(pose: pose)
                    .standsInMeadow(feetY: pose.groundY, scale: scale, sceneSize: size)
            }
        }
    }

    // MARK: - Sprites, checked once

    /// Species 0/1/2 draw `BirdA*` / `BirdB*` / `BirdC*`. All four frames
    /// of a set must exist for that set to be used.
    private static let birdSpriteLetters = ["A", "B", "C"]
    private static let birdSpritesExist: [Bool] = birdSpriteLetters.map { letter in
        (1...4).allSatisfy { UIImage(named: "Bird\(letter)\($0)") != nil }
    }
    private static let hopperSpritesExist: Bool =
        (1...4).allSatisfy { UIImage(named: "Hopper\($0)") != nil }

    fileprivate static func birdSpriteName(species: Int, frame: Int) -> String? {
        let i = ((species % birdSpritesExist.count) + birdSpritesExist.count) % birdSpritesExist.count
        guard birdSpritesExist[i] else { return nil }
        return "Bird\(birdSpriteLetters[i])\(max(1, min(4, frame)))"
    }

    fileprivate static func hopperSpriteName(frame: Int) -> String? {
        guard hopperSpritesExist else { return nil }
        return "Hopper\(max(1, min(4, frame)))"
    }
}

// MARK: - A tiny deterministic random source

/// A flight's whole shape is a pure function of `(seed, slot, salt)`, so a
/// redraw (the clock ticks once a second elsewhere on the same screen) can
/// never desync a bird from where it was a moment ago — it just recomputes
/// the same answer. Splitmix64-shaped; not cryptographic, just well mixed.
private func valleyLifeHash(_ seed: UInt64, _ slot: Int, _ salt: UInt64) -> UInt64 {
    var z = seed &+ UInt64(bitPattern: Int64(slot)) &* 0x9E3779B97F4A7C15 &+ salt &* 0xD1B54A32D192ED03
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
}

private func valleyLifeUnit(_ seed: UInt64, _ slot: Int, _ salt: UInt64) -> Double {
    Double(valleyLifeHash(seed, slot, salt) >> 11) / Double(1 << 53)
}

private func valleyLifeRange(_ seed: UInt64, _ slot: Int, _ salt: UInt64, _ lo: Double, _ hi: Double) -> Double {
    lo + valleyLifeUnit(seed, slot, salt) * (hi - lo)
}

private func valleyLifeInt(_ seed: UInt64, _ slot: Int, _ salt: UInt64, _ count: Int) -> Int {
    guard count > 0 else { return 0 }
    return Int(valleyLifeHash(seed, slot, salt) % UInt64(count))
}

/// Wings beat in a short burst, then hold level to glide, then beat again —
/// "flapping with a 2 to 4 frame wing cycle and gliding between flaps".
/// A burst sweeps frames 1 (up) → 2 (level) → 3 (down) → back toward level;
/// the hold between bursts sits on frame 4, the sprite sheet's own glide
/// frame (also level, but the resting one, not mid-stroke).
private func flapState(elapsed: Double, rate: Double) -> (wingLift: Double, frame: Int) {
    // Slow and peaceful (Melvin, 2026-09-23: "the wing flapping for the birds
    // is wayyyy too fast"). `rate` is now wingbeats per second WITHIN a burst:
    // two unhurried beats, then a long glide, so a crossing reads as a few
    // lazy strokes and a drift rather than a flutter.
    guard rate > 0 else { return (0, 4) }
    let beat = 1 / rate
    let burst = beat * 2
    let full = burst + 1.6 + beat
    var phase = elapsed.truncatingRemainder(dividingBy: full)
    if phase < 0 { phase += full }
    guard phase < burst else { return (0, 4) }
    let u = (phase / beat).truncatingRemainder(dividingBy: 1)
    return (sin(u * 2 * .pi), 1 + min(3, Int(u * 4)))
}

// MARK: - Birds: ten flight patterns

/// About ten flight patterns, chosen per flight: a straight glide, a gentle
/// wave, a swoop down and up, a high slow arc, a zigzag, a V of three, a
/// pair at two heights, a gentle lift, a quick dart, and a glide that fades
/// out as if landing beyond the ridge.
///
/// **No bird ever turns over.** The eighth pattern was a loop-the-loop whose
/// tilt ran a full turn and snapped to upside down the frame the loop began,
/// which read as a glitch (Melvin, 2026-09-23: birds "do a full spin"). It is
/// a lift now, and every tilt stays within a few tens of degrees of level.
private enum BirdPattern: Int, CaseIterable {
    case straightGlide, gentleWave, swoopDownUp, highSlowArc, zigzag
    case vOfThree, pairAtTwoHeights, gentleLift, quickDart, glideAndLand

    /// `vOfThree` and `pairAtTwoHeights` name their own flock size; every
    /// other pattern gets one to three birds, chosen by the caller.
    var fixedCount: Int? {
        switch self {
        case .vOfThree: return 3
        case .pairAtTwoHeights: return 2
        default: return nil
        }
    }

    /// Vertical separation between birds in a multi-bird pattern.
    var laneSpacing: CGFloat {
        // Wide enough that two birds never read as one stacked shape.
        switch self {
        case .vOfThree: return 24
        case .pairAtTwoHeights: return 36
        default: return 28
        }
    }

    /// Only the V staggers its wingmen behind the leader in time; a pair
    /// flies level, side by side.
    var staggered: Bool { self == .vOfThree }

    func duration(unit: Double) -> Double {
        switch self {
        case .straightGlide: return 4.2 + unit * 1.0
        case .gentleWave: return 4.6 + unit * 1.2
        case .swoopDownUp: return 3.8 + unit * 1.0
        case .highSlowArc: return 6.6 + unit * 1.4
        case .zigzag: return 3.6 + unit * 1.0
        case .vOfThree: return 4.6 + unit * 0.8
        case .pairAtTwoHeights: return 4.2 + unit * 1.0
        case .gentleLift: return 4.8 + unit * 0.8
        case .quickDart: return 1.6 + unit * 0.5
        case .glideAndLand: return 5.2 + unit * 1.0
        }
    }

    /// Vertical offset from the flight's lane, in units of a shared
    /// amplitude the caller scales; horizontal position is always a plain
    /// lerp between two off-screen points, so only height and fade vary.
    func yOffset(at p: Double) -> Double {
        switch self {
        case .straightGlide, .quickDart:
            return 0
        case .gentleWave:
            return sin(p * .pi * 2.2) * 0.5
        case .swoopDownUp:
            return sin(p * .pi) * 0.95
        case .highSlowArc:
            return -sin(p * .pi) * 0.95
        case .zigzag:
            let x = (p * 3).truncatingRemainder(dividingBy: 1)
            return (x < 0.5 ? (x * 4 - 1) : (3 - x * 4)) * 0.55
        case .vOfThree, .pairAtTwoHeights:
            return sin(p * .pi * 1.3) * 0.16
        case .gentleLift:
            // Rises a little through the middle of the crossing and settles.
            return -sin(p * .pi) * 0.45
        case .glideAndLand:
            // Flat, then a committed descent for the back third of the
            // flight — landing, rather than crossing the far edge.
            guard p > 0.55 else { return 0 }
            let q = (p - 0.55) / 0.45
            return q * q * 2.1
        }
    }

    /// Authored to roughly track `yOffset`'s slope rather than computed
    /// from it, which keeps a bird's tilt readable at 16pt without needing
    /// a velocity estimate.
    func tiltDegrees(at p: Double) -> Double {
        switch self {
        case .straightGlide, .quickDart:
            return 0
        case .gentleWave:
            return cos(p * .pi * 2.2) * 14
        case .swoopDownUp:
            return -cos(p * .pi) * 20
        case .highSlowArc:
            return cos(p * .pi) * 15
        case .zigzag:
            let x = (p * 3).truncatingRemainder(dividingBy: 1)
            return (x < 0.5 ? 1.0 : -1.0) * 22
        case .vOfThree, .pairAtTwoHeights:
            return cos(p * .pi * 1.3) * 6
        case .gentleLift:
            return -cos(p * .pi) * 10
        case .glideAndLand:
            guard p > 0.55 else { return 0 }
            return min(30, (p - 0.55) / 0.45 * 30)
        }
    }

    /// Fades a bird out near the end of a flight that lands, rather than
    /// letting it cross the far edge of the sky band mid-descent.
    func opacity(at p: Double) -> Double {
        guard self == .glideAndLand, p > 0.86 else { return 1 }
        return max(0, (1 - p) / 0.14)
    }

    /// Wingbeats per second inside a burst: a dart beats a little quicker,
    /// the long high arc slowest of all.
    var flapRate: Double {
        switch self {
        case .quickDart: return 2.4
        case .highSlowArc: return 1.1
        default: return 1.5
        }
    }
}

private struct BirdPose {
    var x: CGFloat
    var y: CGFloat
    var tiltDegrees: Double
    var wingLift: Double
    var frame: Int
    var facingRight: Bool
    var opacity: Double
    var species: Int
    var width: CGFloat
}

private struct BirdFlight: Identifiable {
    let id: Int
    let pattern: BirdPattern
    let startTime: Double
    let duration: Double
    let direction: CGFloat
    let baseY: CGFloat
    let laneY: CGFloat
    let indexDelay: Double
    let flapSeed: Double
    let species: Int
    let width: CGFloat
    let sceneWidth: CGFloat
    let sceneScale: CGFloat

    static func make(seed: UInt64, slot: Int, sky: ClosedRange<CGFloat>,
                      sceneWidth: CGFloat, scale: CGFloat) -> [BirdFlight] {
        guard sceneWidth > 1, sky.upperBound > sky.lowerBound else { return [] }
        let pattern = BirdPattern.allCases[valleyLifeInt(seed, slot, 1, BirdPattern.allCases.count)]
        let jitter = valleyLifeRange(seed, slot, 0, -2, 2)
        let start = Double(slot) * ValleyLife.birdSlot + jitter
        let duration = pattern.duration(unit: valleyLifeUnit(seed, slot, 9))
        let direction: CGFloat = valleyLifeUnit(seed, slot, 2) > 0.5 ? 1 : -1
        let baseY = sky.lowerBound + CGFloat(valleyLifeUnit(seed, slot, 3)) * (sky.upperBound - sky.lowerBound)
        let width = CGFloat(valleyLifeRange(seed, slot, 5, 16, 24)) * scale
        let count = pattern.fixedCount ?? (1 + valleyLifeInt(seed, slot, 6, 3))

        return (0..<count).map { i in
            let centered = Double(i) - Double(count - 1) / 2
            // Never stacked: every bird after the first follows a random
            // beat behind and a random step above or below, so a flock comes
            // out as a loose V one time and a scattered pair the next.
            // Salted per index (not just per flight), so a flock — a V of
            // three especially — can land on three different species
            // rather than all matching the flight's one draw.
            let species = valleyLifeInt(seed, slot, 4 &+ UInt64(i) &* 37, 3)
            let flapSeed = valleyLifeRange(seed, slot, 10 &+ UInt64(i), 0, 2)
            return BirdFlight(id: slot &* 8 &+ i, pattern: pattern, startTime: start, duration: duration,
                               direction: direction, baseY: baseY,
                               laneY: CGFloat(centered) * pattern.laneSpacing
                                   + CGFloat(valleyLifeRange(seed, slot, 20 &+ UInt64(i), -8, 8)),
                               indexDelay: pattern.staggered
                                   ? abs(centered) * 0.55 + valleyLifeRange(seed, slot, 30 &+ UInt64(i), 0, 0.25)
                                   : (i == 0 ? 0 : valleyLifeRange(seed, slot, 30 &+ UInt64(i), 0.35, 1.4)),
                               flapSeed: flapSeed, species: species, width: width,
                               sceneWidth: sceneWidth, sceneScale: scale)
        }
    }

    func pose(at t: Double) -> BirdPose? {
        let local = t - (startTime + indexDelay)
        guard local >= 0, local <= duration else { return nil }
        let p = local / duration

        let travel = sceneWidth + width * 3
        let startX: CGFloat = direction > 0 ? -width * 1.5 : sceneWidth + width * 1.5
        let x = startX + CGFloat(p) * travel * direction

        let amp = 22 * sceneScale
        let dy = pattern.yOffset(at: p) * Double(amp)

        let flap = flapState(elapsed: t + flapSeed, rate: pattern.flapRate)
        return BirdPose(x: x, y: baseY + laneY + CGFloat(dy),
                         tiltDegrees: pattern.tiltDegrees(at: p),
                         wingLift: flap.wingLift, frame: flap.frame,
                         facingRight: direction > 0, opacity: pattern.opacity(at: p),
                         species: species, width: width)
    }
}

/// A small brown sparrow with a cream belly, flapping.
private struct BirdGlyph: View {
    var pose: BirdPose

    private static let brown = Color(red: 0.47, green: 0.33, blue: 0.22)
    private static let brownDark = Color(red: 0.35, green: 0.23, blue: 0.15)
    private static let cream = Color(red: 0.98, green: 0.92, blue: 0.80)
    private static let beak = Color(red: 0.87, green: 0.58, blue: 0.22)

    var body: some View {
        let w = pose.width
        Group {
            if let sprite = ValleyLife.birdSpriteName(species: pose.species, frame: pose.frame) {
                // The four frames of one bird share a box already, so a
                // plain resizable fit never lets one frame jump relative
                // to the next.
                Image(sprite)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: w, height: w * 1.1)
            } else {
                placeholder(w: w, h: w * 0.6)
            }
        }
        .rotationEffect(.degrees(pose.tiltDegrees))
        .scaleEffect(x: pose.facingRight ? 1 : -1, y: 1)
        .opacity(pose.opacity)
        .position(x: pose.x, y: pose.y)
    }

    private func placeholder(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            WingShape()
                .fill(Self.brownDark)
                .frame(width: w * 0.66, height: h * 0.86)
                .rotationEffect(.degrees(pose.wingLift * 40))
                .offset(x: -w * 0.02, y: -h * 0.06)
            Ellipse()
                .fill(Self.brown)
                .frame(width: w * 0.86, height: h * 0.68)
                .offset(x: -w * 0.05)
            Circle()
                .fill(Self.brown)
                .frame(width: h * 0.56, height: h * 0.56)
                .offset(x: w * 0.34, y: -h * 0.08)
            Ellipse()
                .fill(Self.cream)
                .frame(width: w * 0.38, height: h * 0.32)
                .offset(x: -w * 0.02, y: h * 0.16)
            ValleyTriangle()
                .fill(Self.beak)
                .frame(width: w * 0.16, height: h * 0.14)
                .rotationEffect(.degrees(90))
                .offset(x: w * 0.52, y: -h * 0.06)
            ValleyTriangle()
                .fill(Self.brownDark)
                .frame(width: w * 0.22, height: h * 0.24)
                .rotationEffect(.degrees(-90))
                .offset(x: -w * 0.46, y: -h * 0.02)
        }
        .frame(width: w, height: h)
    }
}

/// A simple curved leaf, the cheapest shape that reads as a wing at 14pt.
private struct WingShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.15),
                        control: CGPoint(x: rect.minX + w * 0.55, y: rect.minY - h * 0.25))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                        control: CGPoint(x: rect.minX + w * 0.45, y: rect.maxY + h * 0.05))
        p.closeSubpath()
        return p
    }
}

private struct ValleyTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Grasshoppers

private struct HopperPose {
    var x: CGFloat
    var y: CGFloat
    /// Drives the drawn placeholder's leg, continuously: 0 tucked (mid-air)
    /// ... 1 extended (on the ground).
    var legExtend: Double
    /// Drives the real sprite, discretely: 1 sitting, 2 crouched, 3
    /// mid-jump (shown for the whole airborne stretch), 4 landing.
    var spriteFrame: Int
    var facingRight: Bool
    var opacity: Double
    var bodyLength: CGFloat
    /// Where its feet meet the grass, which the shadow stays on while it
    /// jumps. The shadow is what says how far off the ground it is, and so
    /// how far into the meadow (Aziz, 2026-09-23: the hopping made the lack
    /// of depth "really apparent").
    var groundY: CGFloat = 0
    var lift: CGFloat = 0
}

/// One grasshopper crossing the grass: it comes in from beyond the left
/// edge, hops slowly across with a rest after every hop, and leaves beyond
/// the right edge (Melvin, 2026-09-23: "it should come in on screen from the
/// left and slowly hop across periodically, until it disappears on the
/// right"). It is never faded: it starts and ends off screen, so there is
/// nothing to fade, and nothing can pop.
///
/// It keeps one feet line the whole way (every hop lands where the last one
/// took off), picked inside the grass band, and is drawn a little larger the
/// nearer that line is, the way the flowers are.
private struct HopperCrossing: Identifiable {
    struct Hop {
        let start: Double        // seconds into the crossing
        let duration: Double
        let fromX: CGFloat
        let toX: CGFloat
        let height: CGFloat
    }

    let id: Int
    let startTime: Double
    let feetY: CGFloat
    let bodyLength: CGFloat
    let startX: CGFloat
    let hops: [Hop]

    var totalDuration: Double { (hops.last.map { $0.start + $0.duration } ?? 0) + 0.2 }

    static func make(seed: UInt64, slot: Int, sceneWidth: CGFloat,
                      band: ClosedRange<CGFloat>, scale: CGFloat) -> HopperCrossing? {
        guard sceneWidth > 30, band.upperBound >= band.lowerBound else { return nil }
        let depth = valleyLifeUnit(seed, slot, 28)
        let feetY = band.lowerBound + CGFloat(depth) * (band.upperBound - band.lowerBound)
        // Nearer is bigger, from 85% at the back of the band to 115% at the front.
        let near = 0.85 + 0.30 * CGFloat(depth)
        let bodyLength = CGFloat(valleyLifeRange(seed, slot, 29, 12, 15)) * scale * near
        // Its drawn box is 1.7 body lengths wide; start and finish a whole
        // box beyond each edge so it is fully off screen at both ends.
        let box = bodyLength * 1.7
        let startX = -box
        let endX = sceneWidth + box

        var hops: [Hop] = []
        var x = startX
        var time = valleyLifeRange(seed, slot, 21, 0.2, 0.8)
        var i: UInt64 = 0
        while x < endX, hops.count < 80 {
            let length = CGFloat(valleyLifeRange(seed, slot, 100 &+ i, 16, 24)) * scale * near
            let duration = valleyLifeRange(seed, slot, 200 &+ i, 0.34, 0.46)
            let height = CGFloat(valleyLifeRange(seed, slot, 300 &+ i, 8, 14)) * scale * near
            hops.append(Hop(start: time, duration: duration, fromX: x, toX: x + length, height: height))
            x += length
            // A rest after every hop, now and then a longer one, so it reads
            // as an animal crossing in its own time rather than a metronome.
            let long = valleyLifeUnit(seed, slot, 400 &+ i) < 0.15
            time += duration + (long ? valleyLifeRange(seed, slot, 500 &+ i, 1.8, 2.8)
                                     : valleyLifeRange(seed, slot, 600 &+ i, 0.5, 1.2))
            i += 1
        }
        let start = Double(slot) * ValleyLife.hopperSlot + valleyLifeRange(seed, slot, 22, 2, 9)
        return HopperCrossing(id: slot, startTime: start, feetY: feetY, bodyLength: bodyLength,
                              startX: startX, hops: hops)
    }

    func pose(at t: Double) -> HopperPose? {
        let local = t - startTime
        guard local >= 0, local <= totalDuration, let first = hops.first else { return nil }
        // Sitting before its first hop (off screen), or resting after one.
        var x = startX
        var frame = 1
        var lift: CGFloat = 0
        var legs = 1.0
        if local >= first.start {
            for hop in hops where local >= hop.start {
                let into = local - hop.start
                if into <= hop.duration {
                    let u = into / hop.duration
                    let arc = 4 * u * (1 - u)
                    x = hop.fromX + (hop.toX - hop.fromX) * CGFloat(u)
                    lift = hop.height * CGFloat(arc)
                    legs = max(0, 1 - arc * 1.15)
                    // Crouched right at takeoff, landing right at touchdown,
                    // mid-jump for the whole stretch between.
                    frame = u < 0.12 ? 2 : (u > 0.85 ? 4 : 3)
                } else {
                    x = hop.toX
                    lift = 0
                    legs = 1
                    frame = 1
                }
            }
        }
        return HopperPose(x: x, y: feetY - lift, legExtend: legs, spriteFrame: frame,
                          facingRight: true, opacity: 1, bodyLength: bodyLength,
                          groundY: feetY, lift: lift)
    }
}

/// A small green grasshopper whose legs tuck mid-air and extend to land.
private struct HopperGlyph: View {
    var pose: HopperPose

    private static let green = Color(red: 0.44, green: 0.62, blue: 0.33)
    private static let greenDark = Color(red: 0.30, green: 0.47, blue: 0.24)

    var body: some View {
        ZStack {
            shadow
            glyph
        }
    }

    /// A soft oval on the grass under it, smaller and fainter the higher it
    /// jumps.
    private var shadow: some View {
        let l = pose.bodyLength
        let up = min(1, pose.lift / max(1, l * 0.9))
        return Ellipse()
            .fill(Color.black.opacity(0.20 * (1 - 0.55 * Double(up))))
            .frame(width: l * 1.15 * (1 - 0.35 * up), height: l * 0.26 * (1 - 0.35 * up))
            .blur(radius: l * 0.05)
            .opacity(pose.opacity)
            .position(x: pose.x, y: pose.groundY)
    }

    @ViewBuilder private var glyph: some View {
        let l = pose.bodyLength
        if let sprite = ValleyLife.hopperSpriteName(frame: pose.spriteFrame) {
            // Frames are cropped tight and differ in height (sitting vs.
            // mid-jump), so they sit in a fixed box bottom-aligned rather
            // than centred, or a short frame would appear to hop on its
            // own between frame swaps instead of just changing shape.
            let box = l * 1.7
            Image(sprite)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: box, height: box, alignment: .bottom)
                .scaleEffect(x: pose.facingRight ? 1 : -1, y: 1)
                .opacity(pose.opacity)
                .position(x: pose.x, y: pose.y - box / 2)
        } else {
            placeholder(l: l)
                .scaleEffect(x: pose.facingRight ? 1 : -1, y: 1)
                .opacity(pose.opacity)
                .position(x: pose.x, y: pose.y - l * 0.3)
        }
    }

    private func placeholder(l: CGFloat) -> some View {
        ZStack {
            HopperLeg(extend: pose.legExtend)
                .stroke(Self.greenDark, style: StrokeStyle(lineWidth: max(1, l * 0.09), lineCap: .round))
                .frame(width: l * 0.6, height: l * 0.5)
                .offset(x: -l * 0.14, y: l * 0.16)
            Capsule()
                .fill(Self.green)
                .frame(width: l, height: l * 0.42)
            Circle()
                .fill(Self.greenDark)
                .frame(width: l * 0.34, height: l * 0.34)
                .offset(x: l * 0.4, y: -l * 0.04)
            AntennaShape()
                .stroke(Self.greenDark, lineWidth: max(0.8, l * 0.045))
                .frame(width: l * 0.3, height: l * 0.24)
                .offset(x: l * 0.56, y: -l * 0.24)
        }
        .frame(width: l * 1.6, height: l * 1.2)
    }
}

/// A two-segment jumping leg: tucked under the body at `extend == 0`
/// (mid-hop), splayed back and down at `extend == 1` (take-off / landing).
private struct HopperLeg: Shape {
    var extend: Double

    func path(in rect: CGRect) -> Path {
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let t = CGFloat(max(0, min(1, extend)))
        let hip = CGPoint(x: rect.midX + rect.width * 0.2, y: rect.minY)
        let knee = lerp(CGPoint(x: rect.midX - rect.width * 0.05, y: rect.minY + rect.height * 0.25),
                         CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.35), t)
        let foot = lerp(CGPoint(x: rect.midX + rect.width * 0.05, y: rect.minY + rect.height * 0.45),
                         CGPoint(x: rect.minX - rect.width * 0.1, y: rect.maxY), t)
        var p = Path()
        p.move(to: hip)
        p.addLine(to: knee)
        p.addLine(to: foot)
        return p
    }
}

private struct AntennaShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.minY))
        return p
    }
}
