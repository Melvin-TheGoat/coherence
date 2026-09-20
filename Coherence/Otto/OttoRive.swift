import SwiftUI
import CoreHaptics
import RiveRuntime

// Otto animated with Rive (Melvin, 2026-09-20: "ok lets go with rive").
//
// The rig lives in `Otto.riv`, built in the Rive editor through its MCP from
// the same PNG poses the rest of the app draws. One artboard, "Otto"; one
// state machine, "Otto"; a view model, also "Otto", with two properties the
// app writes: `wave` (trigger) and `talking` (boolean). The machine breathes
// on its own; the app never drives frames.
//
// If the .riv is missing from the bundle (a branch without the asset, or a
// bad export), `OttoRiveView` falls back to the PNG with the SwiftUI pulse,
// so a broken rig costs motion, never a screen.

/// One rig instance: owns the Rive view model and the bound data-binding
/// instance, and exposes the two things the app is allowed to say to Otto.
@MainActor
final class OttoRig: ObservableObject {
    static let fileName = "Otto"
    /// The names we PREFER. If the export does not carry them, the rig uses
    /// whatever the file actually contains (see `make`).
    static let artboard = "Otto"
    static let stateMachine = "Otto"

    let viewModel: RiveViewModel
    private var instance: RiveDataBindingViewModel.Instance?

    /// Nil when the rig is not in the bundle or will not load. A rig that
    /// fails to load is logged and costs the animation, never the screen.
    ///
    /// **The rig must be the artboard we asked for, and nothing else.**
    ///
    /// The bug, 2026-09-20: `Otto.riv` ships the Rive editor's DEFAULTS,
    /// `iPhone 16 - 1` / `State Machine 1`, while this code asked for "Otto"
    /// for both. So `setArtboard` threw on every launch since the rig landed
    /// and every screen quietly drew the still PNG. Nobody noticed for a day,
    /// because the fallback is silent and the PNG looks correct. That is the
    /// hazard of a silent fallback and the reason the log line below is NSLog
    /// and not `print`: a `print` from an app launched by simctl never reaches
    /// `log show`, so the original message existed and was unreadable.
    ///
    /// **Accepting whatever artboard the file happens to have was tried and
    /// is worse.** `iPhone 16 - 1` is a phone-screen-sized frame with a dark
    /// ground, so the app rendered a BLACK RECTANGLE where Otto belongs: a
    /// broken animation beats a broken picture every time. An arbitrary
    /// artboard is not Otto, so an export without our names falls back, loudly.
    static func make() -> OttoRig? {
        guard Bundle.main.url(forResource: fileName, withExtension: "riv") != nil else { return nil }
        do {
            let model = try RiveModel(fileName: fileName, extension: ".riv", in: .main, loadCdn: false)
            try model.setArtboard(artboard)
            try model.setStateMachine(stateMachine)
            return OttoRig(model: model, artboard: artboard, stateMachine: stateMachine)
        } catch {
            // NSLog, not print: a `print` from an app launched by simctl does
            // not reach `log show`, so the original failure message existed and
            // was invisible for a day. Anything that explains a silent fallback
            // has to be readable without a debugger attached.
            NSLog("Otto rig failed to load: %@", String(describing: error))
            if let file = try? RiveFile(name: fileName, extension: ".riv", in: .main, loadCdn: false) {
                // Says exactly what the export would need renaming to, so the
                // next person does not have to take the file apart to find out.
                NSLog("Otto rig: the file offers artboards [%@]; this app needs one called '%@' with a state machine called '%@'",
                      file.artboardNames().joined(separator: ", "), artboard, stateMachine)
            }
            return nil
        }
    }

    private init(model: RiveModel, artboard: String, stateMachine: String) {
        viewModel = RiveViewModel(
            model,
            stateMachineName: stateMachine,
            fit: .contain,
            alignment: .bottomLeft,
            autoPlay: true,
            artboardName: artboard
        )
        viewModel.riveModel?.enableAutoBind { [weak self] instance in
            self?.instance = instance
            // `wave()` and `talking` write through this instance and fail
            // quietly when it never arrives, which is the same class of silence
            // that hid the artboard-name bug. One line, once, so a rig that
            // animates but ignores the app is distinguishable from one that
            // works.
            NSLog("Otto rig: bound")
        }
    }

    /// The wave, once. Safe to call before binding finishes: it is dropped.
    func wave() {
        instance?.triggerProperty(fromPath: "wave")?.trigger()
    }

    /// Mid-sentence head movement while `true`.
    var talking: Bool = false {
        didSet {
            instance?.booleanProperty(fromPath: "talking")?.value = talking
        }
    }
}

/// Otto at `size` points, animated when the rig is present, the still pose
/// with the pulse when it is not. Tapping is the caller's business.
struct OttoRiveView: View {
    var size: CGFloat
    var pose: OttoPose = .talking
    /// Set once from the owner so the same rig survives re-renders.
    @ObservedObject var rig: OttoRigHolder

    var body: some View {
        if let rig = rig.rig {
            rig.viewModel.view()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            OttoMark(size: size, pose: pose)
                .ottoBreathing()
        }
    }
}

/// Holds the rig for a screen. `@StateObject` this where Otto lives so the
/// Rive view model is created once per screen, not per body evaluation.
@MainActor
final class OttoRigHolder: ObservableObject {
    let rig: OttoRig?
    init() { rig = OttoRig.make() }
    func wave() { rig?.wave() }
    func setTalking(_ on: Bool) { rig?.talking = on }
}

// MARK: - Breathing haptics

/// A slow breath on the Taptic Engine: a rising swell on the inhale, a
/// softer fall on the exhale, on the rig's own 5 second period. Built for the
/// onboarding "breathe with Otto" screens (Melvin's ask), OFF everywhere by
/// default. Home never buzzes: a phone that pulses in your pocket is the
/// opposite of what 808 sells. Respects the Settings haptics toggle through
/// the caller, which decides whether to start it at all.
@MainActor
final class BreathHaptics {
    /// Matches the Breathe timeline in Otto.riv: 2.5 s in, 2.5 s out.
    static let period: TimeInterval = 5

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    func start() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak self] in
                // The system reclaimed the engine (a call, a lock); bring the
                // breath back on the next start rather than fighting it here.
                self?.player = nil
            }
            try engine.start()
            let pattern = try Self.breathPattern()
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = Self.period
            try player.start(atTime: CHHapticTimeImmediate)
            self.engine = engine
            self.player = player
        } catch {
            player = nil
            engine = nil
        }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        engine?.stop(completionHandler: nil)
        player = nil
        engine = nil
    }

    /// Inhale: intensity rises 0 to 0.6 over 2.5 s on a soft, low sharpness.
    /// Exhale: falls back over 2.5 s, softer still. No transients: a tick
    /// reads as a notification, a swell reads as breath.
    static func breathPattern() throws -> CHHapticPattern {
        let half = period / 2
        let inhale = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
            ],
            relativeTime: 0,
            duration: half
        )
        let exhale = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
            ],
            relativeTime: half,
            duration: half
        )
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.05),
                .init(relativeTime: half * 0.85, value: 1.0),
                .init(relativeTime: half, value: 0.9),
                .init(relativeTime: period - 0.15, value: 0.05),
                .init(relativeTime: period, value: 0.05)
            ],
            relativeTime: 0
        )
        return try CHHapticPattern(events: [inhale, exhale], parameterCurves: [curve])
    }
}
