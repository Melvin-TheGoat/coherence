import AVFoundation
import UIKit
import os

/// The bell that ends a timed session (Aziz, 2026-10-04: "add the bell").
///
/// The end notification (`SessionEndNotice`) is Time Sensitive, so it gets
/// through Do Not Disturb, but a notification's sound obeys the ring switch:
/// on silent it only vibrates. A sit is done with 808 open (the idle timer is
/// off and leaving the app pauses it), so the app rings this itself at the
/// end, on the media channel, which the ring switch does not silence. It
/// follows the media volume instead.
///
/// Synthesized, like the tones (`ToneEngine`): no file, no licence. A
/// singing bowl struck once: an inharmonic set of partials, each decaying at
/// its own rate, the fundamental doubled a hair apart so it shimmers as it
/// fades. About six seconds long.
///
/// It mixes with other audio rather than stopping it, so someone meditating
/// to their own track in another app hears the bell over it, not instead.
@MainActor
enum SessionBell {
    private static let log = Logger(subsystem: "com.lockout.meditate808", category: "bell")
    /// Held while it rings, and released after.
    private static var engine: AVAudioEngine?
    private static var stopTask: Task<Void, Never>?

    /// Seconds the bell sounds for, and the engine is kept for.
    static let length: Double = 6.5

    /// Rings now, if 808 is the app on screen. A second ring while one is
    /// sounding restarts it rather than stacking two.
    static func ringIfOnScreen() {
        guard UIApplication.shared.applicationState == .active else { return }
        ring()
    }

    static func ring() {
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            log.error("bell: audio session refused: \(error.localizedDescription)")
            return
        }

        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        let rate = format.sampleRate > 0 ? format.sampleRate : 48_000
        let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        var n: Double = 0
        let source = AVAudioSourceNode(format: mono) { _, _, frameCount, buffers -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard let out = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for i in 0..<Int(frameCount) {
                out[i] = Float(sample(at: n / rate))
                n += 1
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = 0.9
        do {
            try engine.start()
        } catch {
            log.error("bell: engine refused: \(error.localizedDescription)")
            return
        }
        self.engine = engine
        stopTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(length))
            // A cancelled sleep throws and `try?` swallows it; a newer ring
            // owns the engine then, so this one must not stop it.
            guard !Task.isCancelled else { return }
            stop()
        }
    }

    static func stop() {
        stopTask?.cancel()
        stopTask = nil
        guard let engine else { return }
        engine.stop()
        self.engine = nil
        // Hand the audio back to whatever the person was playing.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// One sample of the strike at `t` seconds. Partial ratios are a singing
    /// bowl's (inharmonic, so it reads as a bowl and not as a beep); higher
    /// partials are quieter and die faster, as they do in metal.
    nonisolated static func sample(at t: Double) -> Double {
        guard t >= 0, t < length else { return 0 }
        let f = 392.0   // G4: warm, and clear of the nature and tone beds' low end
        let partials: [(ratio: Double, gain: Double, decay: Double)] = [
            (1.0, 0.50, 2.4),
            (1.003, 0.30, 2.6),     // the shimmer: a hair sharp of the fundamental
            (2.71, 0.22, 1.3),
            (5.15, 0.10, 0.7),
            (8.4, 0.05, 0.35),
        ]
        // A soft mallet: 8 ms to full, so the strike has no click.
        let attack = min(1, t / 0.008)
        var v = 0.0
        for p in partials {
            v += p.gain * exp(-t / p.decay) * sin(2 * .pi * f * p.ratio * t)
        }
        // Let the last half second fall to silence, so the cut at `length`
        // is never heard.
        let tail = min(1, (length - t) / 0.5)
        return 0.5 * attack * tail * v
    }
}
