import SwiftUI

/// Small wildlife drifting through the valley while nobody is meditating:
/// birds crossing the sky, grasshoppers hopping through the meadow.
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
    enum Layer { case sky, meadow }

    /// Sky draws birds; meadow draws grasshoppers. Two instances, two
    /// places in `ValleyScene`'s z-order, so birds sit in front of the
    /// clouds and ridges while grasshoppers sit in front of the meadow.
    var layer: Layer
    var size: CGSize
    var scale: CGFloat
    var seed: UInt64
    /// Otto and his cushion, in this view's local space. Nothing is ever
    /// drawn inside it. `nil` when there is nothing to avoid: no figure on
    /// screen, or Otto tucked in a corner well clear of the meadow.
    var avoid: CGRect?

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
                        case .meadow: hoppers(at: context.date.timeIntervalSinceReferenceDate)
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

    /// One grasshopper appears roughly every 8s, jittered ±2s (6 to 10s).
    fileprivate static let hopperSlot: Double = 8

    /// Two lanes in the meadow, one either side of Otto and his cushion,
    /// clear of the very bottom of the frame where a card can rise over
    /// the scene on Home. `nil` avoid (no figure) leaves one full-width lane.
    private var meadowLanes: [ClosedRange<CGFloat>] {
        let marginX = max(10, size.width * 0.05)
        guard let avoid, avoid.width > 0, avoid.height > 0 else {
            return marginX < size.width - marginX ? [marginX...(size.width - marginX)] : []
        }
        var lanes: [ClosedRange<CGFloat>] = []
        let leftHi = avoid.minX - 16
        if leftHi - marginX > 44 { lanes.append(marginX...leftHi) }
        let rightLo = avoid.maxX + 16
        if (size.width - marginX) - rightLo > 44 { lanes.append(rightLo...(size.width - marginX)) }
        return lanes
    }

    /// Within the meadow, but above the lowest sliver of the frame.
    private var meadowYRange: ClosedRange<CGFloat> {
        let top = size.height * 0.58
        let bottom = size.height * 0.87
        return min(top, bottom)...max(top, bottom)
    }

    private func hoppers(at t: Double) -> some View {
        let slot = Int((t / Self.hopperSlot).rounded(.down))
        let lanes = meadowLanes
        let yr = meadowYRange
        let flights = [slot - 1, slot].compactMap {
            HopperFlight.make(seed: seed, slot: $0, lanes: lanes, yRange: yr, scale: scale)
        }
        return ForEach(flights) { flight in
            if let pose = flight.pose(at: t) {
                HopperGlyph(pose: pose)
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
    guard rate > 0 else { return (0, 4) }
    let cycle = 1 / rate
    let burst = cycle * 0.5
    let full = cycle * 1.6
    var phase = elapsed.truncatingRemainder(dividingBy: full)
    if phase < 0 { phase += full }
    guard phase < burst else { return (0, 4) }
    let u = phase / burst
    return (sin(u * 2 * .pi), 1 + min(3, Int(u * 4)))
}

// MARK: - Birds: ten flight patterns

/// About ten flight patterns, chosen per flight: a straight glide, a gentle
/// wave, a swoop down and up, a high slow arc, a zigzag, a V of three, a
/// pair at two heights, a loop once, a quick dart, and a glide that fades
/// out as if landing beyond the ridge.
private enum BirdPattern: Int, CaseIterable {
    case straightGlide, gentleWave, swoopDownUp, highSlowArc, zigzag
    case vOfThree, pairAtTwoHeights, loopOnce, quickDart, glideAndLand

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
        switch self {
        case .vOfThree: return 9
        case .pairAtTwoHeights: return 15
        default: return 5
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
        case .loopOnce: return 4.8 + unit * 0.8
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
        case .loopOnce:
            return sin(p * .pi * 1.05) * 0.3
        case .glideAndLand:
            // Flat, then a committed descent for the back third of the
            // flight — landing, rather than crossing the far edge.
            guard p > 0.55 else { return 0 }
            let q = (p - 0.55) / 0.45
            return q * q * 2.1
        }
    }

    /// A small loop layered on top of `yOffset`, only for `.loopOnce`, eased
    /// in and out so it never kinks the surrounding glide.
    func loopOffset(at p: Double) -> (dx: Double, dy: Double) {
        guard self == .loopOnce else { return (0, 0) }
        let window = 0.42...0.62
        guard window.contains(p) else { return (0, 0) }
        let local = (p - window.lowerBound) / (window.upperBound - window.lowerBound)
        let ease = sin(local * .pi)
        let angle = local * 2 * .pi
        return (cos(angle - .pi / 2) * 0.4 * ease, (sin(angle - .pi / 2) + 1) * 0.4 * ease)
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
        case .loopOnce:
            let window = 0.42...0.62
            guard window.contains(p) else { return 0 }
            let local = (p - window.lowerBound) / (window.upperBound - window.lowerBound)
            return local * 360 - 180
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

    /// Flaps a second faster for a dart, slower for a long high arc.
    var flapRate: Double {
        switch self {
        case .quickDart: return 6.5
        case .highSlowArc: return 2.4
        default: return 4.2
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
            // Salted per index (not just per flight), so a flock — a V of
            // three especially — can land on three different species
            // rather than all matching the flight's one draw.
            let species = valleyLifeInt(seed, slot, 4 &+ UInt64(i) &* 37, 3)
            let flapSeed = valleyLifeRange(seed, slot, 10 &+ UInt64(i), 0, 2)
            return BirdFlight(id: slot &* 8 &+ i, pattern: pattern, startTime: start, duration: duration,
                               direction: direction, baseY: baseY,
                               laneY: CGFloat(centered) * pattern.laneSpacing,
                               indexDelay: pattern.staggered ? abs(centered) * 0.18 : 0,
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
        var x = startX + CGFloat(p) * travel * direction

        let amp = 22 * sceneScale
        let loop = pattern.loopOffset(at: p)
        let dy = (pattern.yOffset(at: p) + loop.dy) * Double(amp)
        x += CGFloat(loop.dx * Double(amp))

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
}

/// One grasshopper: two to four hops in parabolic arcs, then gone.
private struct HopperFlight: Identifiable {
    let id: Int
    let startTime: Double
    let hops: Int
    let hopLength: CGFloat
    let hopHeight: CGFloat
    let hopDuration: Double
    let pauseDuration: Double
    let fadeOut: Double
    let startX: CGFloat
    let baseY: CGFloat
    let direction: CGFloat
    let bodyLength: CGFloat

    var totalDuration: Double {
        Double(hops) * (hopDuration + pauseDuration) - pauseDuration + fadeOut
    }

    static func make(seed: UInt64, slot: Int, lanes: [ClosedRange<CGFloat>],
                      yRange: ClosedRange<CGFloat>, scale: CGFloat) -> HopperFlight? {
        guard !lanes.isEmpty else { return nil }
        let lane = lanes[valleyLifeInt(seed, slot, 20, lanes.count)]
        let laneWidth = lane.upperBound - lane.lowerBound
        guard laneWidth > 30 else { return nil }

        let jitter = valleyLifeRange(seed, slot, 21, -2, 2)
        let start = Double(slot) * ValleyLife.hopperSlot + jitter
        let hops = 2 + valleyLifeInt(seed, slot, 22, 3)
        let hopLength = min(CGFloat(valleyLifeRange(seed, slot, 23, 14, 24)) * scale, laneWidth / CGFloat(hops))
        let hopHeight = CGFloat(valleyLifeRange(seed, slot, 24, 8, 14)) * scale
        let hopDuration = valleyLifeRange(seed, slot, 25, 0.32, 0.46)
        let direction: CGFloat = valleyLifeUnit(seed, slot, 26) > 0.5 ? 1 : -1

        let travel = hopLength * CGFloat(hops)
        let boxLo = lane.lowerBound
        let boxHiMax = max(boxLo, lane.upperBound - travel)
        let boxStart = boxLo + CGFloat(valleyLifeUnit(seed, slot, 27)) * (boxHiMax - boxLo)
        let startX = direction > 0 ? boxStart : boxStart + travel
        let baseY = yRange.lowerBound + CGFloat(valleyLifeUnit(seed, slot, 28)) * (yRange.upperBound - yRange.lowerBound)
        let bodyLength = CGFloat(valleyLifeRange(seed, slot, 29, 12, 16)) * scale

        return HopperFlight(id: slot, startTime: start, hops: hops, hopLength: hopLength,
                             hopHeight: hopHeight, hopDuration: hopDuration, pauseDuration: 0.14,
                             fadeOut: 0.18, startX: startX, baseY: baseY, direction: direction,
                             bodyLength: bodyLength)
    }

    func pose(at t: Double) -> HopperPose? {
        let local = t - startTime
        guard local >= 0, local <= totalDuration else { return nil }
        let cycle = hopDuration + pauseDuration
        let hopIndex = min(hops - 1, Int(local / cycle))
        let intoCycle = local - Double(hopIndex) * cycle
        let inHop = intoCycle <= hopDuration
        let u = inHop ? intoCycle / hopDuration : 1
        let arc = 4 * u * (1 - u)
        let hopsDone = CGFloat(hopIndex) + (inHop ? CGFloat(u) : 1)

        let fadeStart = totalDuration - fadeOut
        let opacity = local >= fadeStart ? max(0, (totalDuration - local) / fadeOut) : 1

        // Sitting between hops (and while fading out, once the clamped
        // hop index has nothing left to play); crouched right at takeoff;
        // landing right at touchdown; mid-jump for the whole stretch
        // between, which is deliberately the widest window — "show frame
        // 3 while airborne".
        let spriteFrame: Int
        if !inHop {
            spriteFrame = 1
        } else if u < 0.12 {
            spriteFrame = 2
        } else if u > 0.85 {
            spriteFrame = 4
        } else {
            spriteFrame = 3
        }

        return HopperPose(x: startX + direction * hopLength * hopsDone,
                           y: baseY - hopHeight * CGFloat(arc),
                           legExtend: inHop ? max(0, 1 - arc * 1.15) : 1,
                           spriteFrame: spriteFrame,
                           facingRight: direction > 0, opacity: opacity, bodyLength: bodyLength)
    }
}

/// A small green grasshopper whose legs tuck mid-air and extend to land.
private struct HopperGlyph: View {
    var pose: HopperPose

    private static let green = Color(red: 0.44, green: 0.62, blue: 0.33)
    private static let greenDark = Color(red: 0.30, green: 0.47, blue: 0.24)

    var body: some View {
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
