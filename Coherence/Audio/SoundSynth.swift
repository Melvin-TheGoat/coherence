import Foundation

/// Every sound effect 808 makes outside a session (Melvin, 2026-10-09:
/// "when you get points there should be sound effects too. When you tap
/// there should be sound effects", and the birds chirping as they fly by).
///
/// **Synthesized, like the session bell (`SessionBell`) and the tones
/// (`ToneEngine`): no file, no licence, nothing to buy or credit.** Every
/// sound is a pure function of time, so it is the same on every phone and
/// can be checked by a test (`SoundSynthTests`: none clips, all end in
/// silence).
///
/// **Pure Foundation on purpose.** `tools/render_sounds.swift` compiles this
/// same file on a Mac and writes every sound to a WAV, which is how they are
/// auditioned without building the app; nothing here may import UIKit or
/// AVFoundation.
///
/// **Tuned to C major pentatonic** (C, D, E, G, A), the key of the home
/// music (`AppAudio.musicResource`, in C), so a coin or a chime can never
/// sound out of tune against it. A pentatonic scale has
/// no two notes a semitone apart, which is why any run of coins sounds like
/// a tune rather than a mistake. Change the music to a bed in another key
/// and `root` moves with it.
enum SoundEffect: Hashable {
    /// A press: a small water droplet. Every press is the same sound (Melvin,
    /// 2026-10-12: "i want it all to be the same sound, not randomized between
    /// 3"); a `main` button, the one a screen exists for (the green and gold
    /// buttons, the plus), lands a few notes higher.
    case tap(main: Bool)
    /// A reward card arriving: a bubble that pops upward.
    case pop
    /// One coin landing in the bank, `step` notes up the scale, so a run of
    /// coins climbs.
    case coin(Int)
    /// The glow bar filling: a quick run of small bells.
    case shimmer
    /// Something earned: a new look for Otto, a new stage, an award.
    case chime
    /// Otto landing at the start of the reward.
    case land
    /// A bird crossing the sky. `species` matches the sprite (0 the sparrow,
    /// 1 the cardinal, 2 the blue bird); `call` is one of its two calls.
    case chirp(species: Int, call: Int)

    static let coinSteps = 9

    /// Every sound there is, for rendering ahead of time and for the tests.
    static let all: [SoundEffect] =
        [.tap(main: false), .tap(main: true), .pop]
        + (0..<coinSteps).map { .coin($0) }
        + [.shimmer, .chime, .land]
        + (0..<3).flatMap { s in (0..<2).map { .chirp(species: s, call: $0) } }

    /// A file-safe name, for the render tool.
    var name: String {
        switch self {
        case .tap(let main): return main ? "tap-main" : "tap"
        case .pop: return "pop"
        case .coin(let s): return "coin-\(s)"
        case .shimmer: return "shimmer"
        case .chime: return "chime"
        case .land: return "land"
        case .chirp(let s, let c): return "chirp-\(["sparrow", "cardinal", "bluebird"][s % 3])-\(c)"
        }
    }
}

enum SoundSynth {
    static let rate: Double = 44_100

    /// Every sound is normalized to this peak, and given its loudness by
    /// `AppAudio.volume(for:)`, so the level of each lives in one place.
    static let peak: Float = 0.8

    /// C4 at A440, the key note of the music (`AppAudio.musicTonic`), which
    /// everything pitched is tuned from. It has moved with the music twice
    /// (E4 under Deep Meditation, C at 528 Hz under Manifest); moving it
    /// moves every pitched sound the same distance, so their shapes hold.
    static let root: Double = 261.63

    /// C major pentatonic, from `root`, `degree` steps up (5 steps an octave).
    static func pentatonic(_ degree: Int) -> Double {
        let steps = [0, 2, 4, 7, 9]   // C D E G A
        let octave = degree >= 0 ? degree / 5 : (degree - 4) / 5
        let index = degree - octave * 5
        return root * pow(2, Double(octave) + Double(steps[index]) / 12)
    }

    /// The coins climb from C5 to G6 and stop there, so a long session's
    /// run of coins never climbs into a whistle.
    static func coinPitch(_ step: Int) -> Double {
        pentatonic(5 + max(0, min(step, SoundEffect.coinSteps - 1)))
    }

    static func duration(_ e: SoundEffect) -> Double {
        switch e {
        case .tap: return 0.085
        case .pop: return 0.16
        case .coin: return 0.6
        case .shimmer: return 1.7
        case .chime: return 2.3
        case .land: return 0.55
        case .chirp(let s, let c): return chirpLength(species: s, call: c)
        }
    }

    /// The whole sound, normalized to `peak`, with its last 8 ms faded so the
    /// cut at the end is never heard.
    static func samples(_ e: SoundEffect, rate: Double = rate) -> [Float] {
        let n = max(1, Int(duration(e) * rate))
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = Float(raw(e, t: Double(i) / rate))
        }
        let top = out.reduce(0) { max($0, abs($1)) }
        if top > 0 {
            let gain = peak / top
            for i in 0..<n { out[i] *= gain }
        }
        let fade = min(n, Int(0.008 * rate))
        for k in 0..<fade {
            out[n - 1 - k] *= Float(k) / Float(fade)
        }
        return out
    }

    // MARK: - The sounds

    static func raw(_ e: SoundEffect, t: Double) -> Double {
        switch e {
        case .tap(let main): return tap(t, pitch: tapPitch(main: main))
        case .pop: return pop(t)
        case .coin(let s): return coin(t, pitch: coinPitch(s))
        case .shimmer: return shimmer(t)
        case .chime: return chime(t)
        case .land: return land(t)
        case .chirp(let s, let c): return chirp(t, species: s, call: c)
        }
    }

    /// Where a droplet lands: G5 for a press and C6 for a main button, a
    /// fourth up, enough to hear across a sweep. Both are notes of the
    /// music's key, so they move with `root`.
    static func tapPitch(main: Bool) -> Double {
        pentatonic(main ? 10 : 8)
    }

    /// A press is a small droplet falling into still water: the pitch sweeps
    /// up from 62% to its note in about 20 ms and the sound is gone almost as
    /// it arrives (Melvin, 2026-10-12, third round). The first press was a
    /// wood block ("a bird pecker pecking on wood, or xylophone"); the second
    /// was one soft steady note, which he liked for the softness and heard
    /// as "a piano key ... it doesnt go up and down or swipes ... its not
    /// dynamic". A steady pitch with a decay is what a struck string does;
    /// a sweep is what a bubble does, and moving pitch is what UI sound
    /// designers reach for (Facebook's Will Littlejohn builds from "the
    /// movement, the action, the frequency sweeps", and a simple harmonic
    /// sound tolerates the most repetition). It is a smaller cousin of
    /// `pop`, so the reward's cards and the presses are one family, and it
    /// suits a valley with water in it. A sine, a 3 ms ease in, a breath of
    /// octave at the start: soft, and over before the next press.
    private static func tap(_ t: Double, pitch f: Double) -> Double {
        let attack = 0.5 - 0.5 * cos(.pi * min(1, t / 0.003))
        let tau = 0.011, rise = 0.38
        // f(t) = f * (1 - rise * e^(-t/tau)); this is its integral.
        let phase = 2 * .pi * f * (t - rise * tau * (1 - exp(-t / tau)))
        let body = sin(phase) + 0.08 * sin(2 * phase) * exp(-t / 0.01)
        return attack * body * exp(-t / 0.024)
    }

    /// A bubble: the pitch rises fast and the sound is gone before it
    /// settles.
    private static func pop(_ t: Double) -> Double {
        let from = 420.0, to = 980.0, tau = 0.028
        // f(t) runs from `from` up to `to`; this is its integral.
        let phase = 2 * .pi * (to * t + (from - to) * tau * (1 - exp(-t / tau)))
        let env = min(1, t / 0.003) * exp(-t / 0.045)
        return env * (sin(phase) + 0.22 * sin(2 * phase) * exp(-t / 0.02))
    }

    /// A small bell. Partials a metal bar would have, the high ones quieter
    /// and quicker to die, the fundamental doubled a hair sharp so it
    /// shimmers as it fades, like the session bell.
    static func bell(_ f: Double, _ t: Double, decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        let partials: [(ratio: Double, gain: Double, life: Double)] = [
            (1.0, 1.0, 1.0),
            (1.0035, 0.35, 1.1),
            (2.0, 0.28, 0.45),
            (3.0, 0.12, 0.25),
            (4.17, 0.07, 0.12),
        ]
        var v = 0.0
        for p in partials where f * p.ratio < 16_000 {
            v += p.gain * exp(-t / (decay * p.life)) * sin(2 * .pi * f * p.ratio * t)
        }
        return min(1, t / 0.002) * v
    }

    /// A coin: a bright bell with a short metal clink on top.
    private static func coin(_ t: Double, pitch f: Double) -> Double {
        let clink = 0.18 * sin(2 * .pi * f * 6.2 * t) * exp(-t / 0.008)
        return bell(f, t, decay: 0.28) + clink * min(1, t / 0.001)
    }

    /// Ten small bells running up two octaves, quick enough to read as one
    /// gesture: the bar filling.
    private static func shimmer(_ t: Double) -> Double {
        var v = 0.0
        for k in 0..<10 {
            let at = Double(k) * 0.085
            // Swells toward the middle of the run and eases off at the top,
            // so the highest notes are the gentlest.
            let gain = 0.55 + 0.45 * sin(Double(k) / 9 * .pi)
            v += gain * bell(pentatonic(5 + k), t - at, decay: 0.22)
        }
        return v * min(1, t / 0.15)
    }

    /// C, E, G, C struck in turn, then two high sparkles: the sound of
    /// something earned.
    private static func chime(_ t: Double) -> Double {
        let notes: [(degree: Int, at: Double, gain: Double, decay: Double)] = [
            (5, 0.0, 1.0, 0.85),     // C5
            (7, 0.075, 0.92, 0.85),  // E5
            (8, 0.15, 0.86, 0.85),   // G5
            (10, 0.225, 0.8, 0.95),  // C6
            (13, 0.33, 0.34, 0.45),  // G6
            (15, 0.40, 0.24, 0.35),  // C7
        ]
        return notes.reduce(0) { $0 + $1.gain * bell(pentatonic($1.degree), t - $1.at, decay: $1.decay) }
    }

    /// A soft mallet on a low bell, with a little weight under it.
    private static func land(_ t: Double) -> Double {
        let soft = min(1, t / 0.006)
        let low = bell(pentatonic(0), t, decay: 0.32)            // C4
        let under = 0.45 * sin(2 * .pi * pentatonic(-5) * t) * exp(-t / 0.18)   // C3
        return soft * (low + under)
    }

    // MARK: - Birds

    /// The three birds that fly over the valley, each with two calls. Real
    /// songbirds sing mostly between 2 and 7 kHz, which is also where a
    /// phone speaker is clearest. Their syllables are sweeps: the sparrow
    /// chips quickly downward, the cardinal whistles long slurs, the blue
    /// bird warbles.
    private static func chirpLength(species: Int, call: Int) -> Double {
        let last = syllables(species: species, call: call).map { $0.at + $0.length }.max() ?? 0.2
        return last + 0.03
    }

    private struct Syllable {
        let at: Double
        let length: Double
        let from: Double
        let to: Double
        /// Warble: how far and how fast the pitch wobbles around the sweep.
        var wobble: Double = 0
        var wobbleRate: Double = 0
    }

    private static func syllables(species: Int, call: Int) -> [Syllable] {
        switch ((species % 3) + 3) % 3 {
        case 0:
            // The sparrow: two or three quick chips, falling.
            let lower = call == 0 ? 1.0 : 0.9
            let count = call == 0 ? 2 : 3
            return (0..<count).map { k in
                Syllable(at: Double(k) * (call == 0 ? 0.11 : 0.09), length: 0.04,
                         from: 6400 * lower, to: 4200 * lower)
            }
        case 1:
            // The cardinal: clear whistled slurs. "Cheer cheer", or a rising
            // "wheet" answered by a falling one.
            if call == 0 {
                return [Syllable(at: 0, length: 0.16, from: 3900, to: 2300),
                        Syllable(at: 0.22, length: 0.16, from: 3800, to: 2250)]
            }
            return [Syllable(at: 0, length: 0.13, from: 2100, to: 3700),
                    Syllable(at: 0.2, length: 0.15, from: 3600, to: 2400)]
        default:
            // The blue bird: a soft warble, once or twice.
            if call == 0 {
                return [Syllable(at: 0, length: 0.32, from: 3100, to: 2900, wobble: 300, wobbleRate: 18)]
            }
            return [Syllable(at: 0, length: 0.26, from: 3200, to: 3000, wobble: 280, wobbleRate: 20),
                    Syllable(at: 0.36, length: 0.24, from: 2800, to: 2600, wobble: 260, wobbleRate: 17)]
        }
    }

    private static func chirp(_ t: Double, species: Int, call: Int) -> Double {
        var v = 0.0
        for s in syllables(species: species, call: call) {
            let local = t - s.at
            guard local >= 0, local <= s.length else { continue }
            let u = local / s.length
            // A linear sweep's phase is the integral of its frequency.
            var phase = 2 * .pi * (s.from * local + (s.to - s.from) * local * local / (2 * s.length))
            if s.wobble > 0 {
                phase += (s.wobble / s.wobbleRate) * (1 - cos(2 * .pi * s.wobbleRate * local))
            }
            // A rounded swell in and out: a bird's syllable has no edges.
            let env = pow(sin(.pi * u), 1.4)
            v += env * (sin(phase) + 0.08 * sin(2 * phase))
        }
        return v
    }

    // MARK: - Helpers

    /// 16-bit mono PCM in a WAV container, which `AVAudioPlayer(data:)`
    /// opens directly and the render tool writes to disk.
    static func wav(_ samples: [Float], rate: Double = rate) -> Data {
        var d = Data()
        func ascii(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        let sr = UInt32(rate)
        ascii("RIFF"); u32(UInt32(36 + bytes)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1); u32(sr); u32(sr * 2); u16(2); u16(16)
        ascii("data"); u32(UInt32(bytes))
        d.reserveCapacity(d.count + bytes)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * Float(Int16.max))
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        return d
    }
}
