// Renders every sound in `SoundSynth` to a WAV, plus a few short mixes that
// play them the way the app does, so they can be heard without building the
// app.
//
//   swiftc -parse-as-library -O -o /tmp/render_sounds \
//       Coherence/Audio/SoundSynth.swift tools/render_sounds.swift
//   /tmp/render_sounds <out-dir>
//
// The mixes:
//   coins.wav      eighteen coins 105 ms apart, the reward screen's run
//   reward.wav     land, three cards, the coins, the glow, a new look
//   taps.wav       seven presses, quick then slow, then a main button
//   birds.wav      each bird's two calls, spaced out
import Foundation

@main
struct RenderSounds {
    static func main() throws {
        let args = CommandLine.arguments
        let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        for e in SoundEffect.all {
            let s = SoundSynth.samples(e)
            try SoundSynth.wav(s).write(to: out.appendingPathComponent(e.name + ".wav"))
            let top = s.reduce(0) { max($0, abs($1)) }
            print(String(format: "%-22@ %5.2fs  peak %.2f", e.name as NSString, Double(s.count) / SoundSynth.rate, top))
        }

        // Levels here follow `AppAudio.volume(for:)`.
        func mix(_ name: String, seconds: Double, _ events: [(SoundEffect, Double, Float)]) throws {
            var buf = [Float](repeating: 0, count: Int(seconds * SoundSynth.rate))
            for (e, at, gain) in events {
                let s = SoundSynth.samples(e)
                let start = Int(at * SoundSynth.rate)
                for i in 0..<s.count where start + i < buf.count { buf[start + i] += s[i] * gain }
            }
            let top = buf.reduce(0) { max($0, abs($1)) }
            if top > 0.98 { for i in buf.indices { buf[i] *= 0.98 / top } }
            try SoundSynth.wav(buf).write(to: out.appendingPathComponent(name + ".wav"))
            print("mix \(name).wav  peak \(String(format: "%.2f", top))")
        }

        let coin: Float = 0.45
        // The run climbs the whole scale whatever its length, as the reward
        // screen plays it.
        func run(_ n: Int, from start: Double) -> [(SoundEffect, Double, Float)] {
            (0..<n).map { i in (.coin((SoundEffect.coinSteps - 1) * i / max(n - 1, 1)), start + Double(i) * 0.105, coin) }
        }
        try mix("coins", seconds: 3.0, run(18, from: 0.62))

        var reward: [(SoundEffect, Double, Float)] = [(.land, 0.15, 0.4)]
        reward += [(.pop, 1.35, 0.4), (.pop, 2.6, 0.4), (.pop, 3.4, 0.4)]
        reward += run(12, from: 4.4)
        reward += [(.shimmer, 6.6, 0.35), (.chime, 8.0, 0.5)]
        try mix("reward", seconds: 10.5, reward)

        // Five quick presses, two slow ones, then a main button.
        let quick = (0..<5).map { i in (SoundEffect.tap(main: false), 0.2 + Double(i) * 0.18, Float(0.23)) }
        let slow = (0..<2).map { i in (SoundEffect.tap(main: false), 1.6 + Double(i) * 0.7, Float(0.23)) }
        try mix("taps", seconds: 3.6, quick + slow + [(SoundEffect.tap(main: true), 3.0, Float(0.23))])

        var birds: [(SoundEffect, Double, Float)] = []
        var at = 0.3
        for s in 0..<3 {
            for c in 0..<2 {
                birds.append((.chirp(species: s, call: c), at, 0.22))
                at += 1.1
            }
        }
        try mix("birds", seconds: at + 0.5, birds)
    }
}
