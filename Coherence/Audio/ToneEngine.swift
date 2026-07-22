import Foundation
import AVFoundation

/// A synthesized meditation tone. Entrainment presets carry a `beatHz` (the target
/// brainwave rate); a pure tone (e.g. 528 Hz) leaves it nil. `carrierHz` is the
/// audible base tone. All tones are generated at runtime — no audio files, no
/// licensing.
struct FrequencyPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let carrierHz: Double
    let beatHz: Double?          // nil = pure tone; the Speaker/Headphones method only matters when set
    var bedResource: String? = nil   // bundled ambient bed (ElevenLabs) mixed UNDER the exact tone

    /// The Speaker (isochronic) vs Headphones (binaural) choice only changes a beat preset.
    var hasBeat: Bool { beatHz != nil }
}

enum FrequencyCatalog {
    /// MVP set: three brainwave-entrainment states + one solfeggio brand tone.
    static let all: [FrequencyPreset] = [
        // Entrainment presets — beatHz is the pulse rate (must sit in the target
        // band); carrierHz is the audible pitch and is purely aesthetic.
        FrequencyPreset(id: "theta", title: "Deep Meditation", subtitle: "Theta · ~6 Hz", carrierHz: 329.63, beatHz: 6, bedResource: "bed-deep-meditation"),
        FrequencyPreset(id: "alpha", title: "Calm",            subtitle: "Alpha · ~8 Hz", carrierHz: 369.99, beatHz: 8, bedResource: "bed-calm"),
        FrequencyPreset(id: "delta", title: "Deep Rest",       subtitle: "Delta · ~2.5 Hz", carrierHz: 277.18, beatHz: 2.5),
        // Pure "frequency" tones — the carrier IS the point. Traditional/cultural
        // associations (not lab-proven — the real, consistent effect is relaxation).
        FrequencyPreset(id: "harmony",   title: "Harmony",   subtitle: "432 Hz · natural tuning", carrierHz: 432, beatHz: nil),
        FrequencyPreset(id: "manifest",  title: "Manifest",  subtitle: "528 Hz · transformation", carrierHz: 528, beatHz: nil),
        FrequencyPreset(id: "visualize", title: "Visualize", subtitle: "852 Hz · intuition", carrierHz: 852, beatHz: nil),
        FrequencyPreset(id: "awaken",    title: "Awaken",    subtitle: "963 Hz · higher self", carrierHz: 963, beatHz: nil),
    ]

    static func preset(id: String?) -> FrequencyPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

/// Real-time tone synthesizer (phone-side — audio is a phone concern; the Watch only
/// measures). Builds a warm detuned pad (fundamental + sub-octave + octave + unison
/// chorus voices, each drifting on its own slow LFO), then runs it through a
/// low-pass → delay → hall reverb chain for a lush, spacious "frequency track" sound.
///
/// Entrainment methods:
///  - **isochronic** (Speaker): the pad is amplitude-pulsed at the beat rate. Works
///    on the speaker, no headphones.
///  - **binaural** (Headphones): a clean tone pair offset by the beat, panned L/R.
///  A pure tone (no beat) plays steady regardless of method.
final class ToneEngine: ObservableObject {
    enum Method { case isochronic, binaural }

    /// ID of the preset currently sounding (nil = stopped) — drives Preview UI.
    @Published private(set) var playingID: String?

    private let engine = AVAudioEngine()
    private var nodes: [AVAudioNode] = []
    /// The ambient bed (pre-produced audio) looping under the synthesized tone.
    /// Played via AVAudioPlayer (streams from disk, low memory) alongside the engine;
    /// both mix at the hardware output.
    private var bedPlayer: AVAudioPlayer?
    // Mix balance when a bed is present (tune by ear): bed up, tone down so the
    // ambient bed leads and the entrainment tone sits softly underneath.
    private static let bedVolume: Float = 0.85
    private static let toneVolumeWithBed: Float = 0.6          // isochronic (speaker), washed in reverb
    private static let toneVolumeWithBedBinaural: Float = 0.3  // binaural is drier/louder → sits lower

    // MARK: Audio-thread oscillator bank (a plain reference type captured by the
    // render block, so nothing touches the main-actor object on the audio thread).
    private final class Osc {
        static let twoPi = 2 * Double.pi

        /// One detuned voice: independent L/R frequency (for binaural), stereo gains
        /// (for width), and a slow amplitude LFO (for evolving movement).
        struct Voice {
            let incL, incR, gainL, gainR, lfoInc, lfoDepth: Double
            var pL: Double
            var pR: Double
            var lfo: Double
        }

        var voices: [Voice]
        let norm: Double
        let modulated: Bool          // isochronic amplitude pulsing
        let modDepth: Double
        let amp: Double
        let attackSamples: Double
        let dGate: Double
        var gate = 0.0, t = 0.0

        init(preset: FrequencyPreset, method: Method, sampleRate: Double, amp: Double) {
            let twoPi = Osc.twoPi
            func inc(_ f: Double) -> Double { twoPi * f / sampleRate }
            let f = preset.carrierHz
            let beat = preset.beatHz
            let binaural = method == .binaural && beat != nil

            var vs: [Voice] = []
            func add(_ fL: Double, _ fR: Double, _ gL: Double, _ gR: Double, _ lfoRate: Double, _ lfoDepth: Double, _ lfoPhase: Double) {
                vs.append(Voice(incL: inc(fL), incR: inc(fR), gainL: gL, gainR: gR,
                                lfoInc: inc(lfoRate), lfoDepth: lfoDepth, pL: 0, pR: 0, lfo: lfoPhase))
            }

            if binaural, let b = beat {
                // Clean binaural pair (keeps the beat crisp) + a warm centred sub.
                add(f - b / 2, f + b / 2, 1.0, 1.0, 0.05, 0.12, 0.0)
                add(f / 2,     f / 2,     0.5, 0.5, 0.06, 0.12, 1.5)
            } else if beat == nil {
                // Pure "frequency" tone — CLEAN and STEADY. No detuned voices (they beat
                // → slow "in and out" phasing) and NO octave-up layer (for 852 that octave
                // sits ~1.7 kHz and reads as a thin ring behind the tone). Just the
                // fundamental + a warm sub-octave (+ a deep anchor for high tones). The
                // chain also drops the delay for pure tones — see play() — because a
                // feedback delay rings on whichever fundamental aligns with its comb.
                let high = f >= 600
                add(f,     f,     1.00, 1.00, 0, 0, 0)                              // fundamental
                add(f / 2, f / 2, high ? 0.55 : 0.40, high ? 0.55 : 0.40, 0, 0, 0)  // sub — warmth/body
                if high {
                    add(f / 4, f / 4, 0.30, 0.30, 0, 0, 0)                          // deep anchor for high tones
                }
            } else {
                // Isochronic entrainment pad — a detuned chorus is fine here: the beat
                // pulse masks any beating and the stereo width is pleasant.
                add(f,        f,        1.00, 1.00, 0.040, 0.15, 0.0)   // centre
                add(f - 0.5,  f - 0.5,  0.90, 0.45, 0.050, 0.15, 0.7)   // detune, leans left
                add(f + 0.5,  f + 0.5,  0.45, 0.90, 0.045, 0.15, 1.4)   // detune, leans right
                add(f - 0.18, f - 0.18, 0.60, 0.50, 0.037, 0.15, 2.1)   // subtle
                add(f + 0.18, f + 0.18, 0.50, 0.60, 0.053, 0.15, 2.8)
                add(f / 2,    f / 2,    0.30, 0.30, 0.030, 0.12, 3.5)   // sub-octave — warmth/body
                add(f * 2,    f * 2,    0.22, 0.16, 0.070, 0.18, 4.2)   // octave — air, wide
                add(f * 2,    f * 2,    0.16, 0.22, 0.065, 0.18, 5.0)
            }

            self.voices = vs
            let sumL = vs.reduce(0) { $0 + $1.gainL }
            let sumR = vs.reduce(0) { $0 + $1.gainR }
            self.norm = 1.0 / max(sumL, sumR, 1)
            self.modulated = beat != nil && !binaural
            self.modDepth = 0.22                     // gentle tremolo
            self.amp = amp
            self.attackSamples = sampleRate * 1.2    // slow fade-in
            self.dGate = (beat.map { inc($0) }) ?? 0
        }

        func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) {
            let twoPi = Osc.twoPi
            for i in 0..<n {
                let attack = min(1.0, t / attackSamples)
                let env = modulated ? (1 - modDepth * 0.5 * (1 - cos(gate))) : 1.0
                var accL = 0.0, accR = 0.0
                for v in 0..<voices.count {
                    let swell = 1 - voices[v].lfoDepth * 0.5 * (1 - cos(voices[v].lfo))
                    accL += sin(voices[v].pL) * voices[v].gainL * swell
                    accR += sin(voices[v].pR) * voices[v].gainR * swell
                    voices[v].pL += voices[v].incL; if voices[v].pL > twoPi { voices[v].pL -= twoPi }
                    voices[v].pR += voices[v].incR; if voices[v].pR > twoPi { voices[v].pR -= twoPi }
                    voices[v].lfo += voices[v].lfoInc; if voices[v].lfo > twoPi { voices[v].lfo -= twoPi }
                }
                let g = amp * attack * env * norm
                l[i] = Float(g * accL)
                r[i] = Float(g * accR)
                gate += dGate; if gate > twoPi { gate -= twoPi }
                t += 1
            }
        }
    }

    private static let sampleRate = 44_100.0
    private static let amplitude = 0.5    // headroom; the voice bank is normalized to ~1

    /// Starts the preset (replacing anything already playing).
    func play(_ preset: FrequencyPreset, method: Method) {
        stop()
        configureSession()

        let osc = Osc(preset: preset, method: method, sampleRate: Self.sampleRate, amp: Self.amplitude)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2) else { return }
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, ablPtr in
            let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
            guard let lRaw = abl[0].mData, let rRaw = abl[1].mData else { return noErr }
            osc.render(lRaw.assumingMemoryBound(to: Float.self),
                       rRaw.assumingMemoryBound(to: Float.self),
                       Int(frameCount))
            return noErr
        }

        var chain: [AVAudioNode] = [source]

        if !preset.hasBeat {
            // Pure tone: a lighter hall, then a low-pass tuned JUST above the tone to
            // strip the reverb's metallic high shimmer (the "ringing behind 852") while
            // leaving the fundamental untouched. A sustained pure tone has no legitimate
            // content above its fundamental, so this is safe.
            let verb = AVAudioUnitReverb()
            verb.loadFactoryPreset(.largeHall2)
            verb.wetDryMix = 40

            let postLP = AVAudioUnitEQ(numberOfBands: 1)
            postLP.bands[0].filterType = .lowPass
            postLP.bands[0].frequency = Float(max(600, preset.carrierHz * 1.2))
            postLP.bands[0].bypass = false

            chain += [verb, postLP]
        } else if method == .binaural {
            // Binaural (headphones): headphones expose every artifact, and heavy
            // delay/reverb also muddies the two-ear beat. So keep it clean — NO delay,
            // light reverb, and a low-pass just above the tone to kill the metallic ring.
            let verb = AVAudioUnitReverb()
            verb.loadFactoryPreset(.largeHall2)
            verb.wetDryMix = 28

            let postLP = AVAudioUnitEQ(numberOfBands: 1)
            postLP.bands[0].filterType = .lowPass
            postLP.bands[0].frequency = Float(max(650, preset.carrierHz * 1.6))
            postLP.bands[0].bypass = false

            chain += [verb, postLP]
        } else {
            // Isochronic (speaker): soften top → delay tail → lush hall. The pulse masks
            // the coloration and the floating tail sounds good through a speaker.
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .lowPass
            eq.bands[0].frequency = 1600
            eq.bands[0].bypass = false

            let delay = AVAudioUnitDelay()
            delay.delayTime = 0.42
            delay.feedback = 32
            delay.lowPassCutoff = 1800
            delay.wetDryMix = 20

            let verb = AVAudioUnitReverb()
            verb.loadFactoryPreset(.largeHall2)
            verb.wetDryMix = 60

            chain += [eq, delay, verb]
        }

        chain.forEach { engine.attach($0) }
        for i in 0..<(chain.count - 1) {
            engine.connect(chain[i], to: chain[i + 1], format: format)
        }
        engine.connect(chain.last!, to: engine.mainMixerNode, format: format)

        // Soften the synthesized tone when it's riding under a bed (the bed leads).
        // Binaural is drier (less reverb → louder/more direct), so it needs a lower level
        // than the reverb-washed isochronic tone to sit at the same spot under the bed.
        if preset.bedResource != nil {
            engine.mainMixerNode.outputVolume = (method == .binaural)
                ? Self.toneVolumeWithBedBinaural : Self.toneVolumeWithBed
        } else {
            engine.mainMixerNode.outputVolume = 1.0
        }

        do {
            try engine.start()
            nodes = chain
            playingID = preset.id
            startBed(for: preset)
        } catch {
            chain.forEach { engine.detach($0) }
        }
    }

    /// Loads and loops the preset's ambient bed under the tone, if it has one.
    private func startBed(for preset: FrequencyPreset) {
        guard let name = preset.bedResource,
              let url = Bundle.main.url(forResource: name, withExtension: "m4a")
                    ?? Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1          // loop forever (any session length)
            player.volume = Self.bedVolume
            player.prepareToPlay()
            player.play()
            bedPlayer = player
        } catch {
            // No bed is fine — the tone plays on its own.
        }
    }

    /// Stops any tone + bed and tears the graph down.
    func stop() {
        bedPlayer?.stop()
        bedPlayer = nil
        nodes.forEach { engine.detach($0) }
        nodes = []
        if engine.isRunning { engine.stop() }
        playingID = nil
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
