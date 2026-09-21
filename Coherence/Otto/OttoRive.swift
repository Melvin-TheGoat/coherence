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

    /// The artboard's own proportions (425 x 522). The view frames itself to
    /// this, so `.contain` fits exactly and Otto is never letterboxed inside a
    /// square frame with his own art pushed to one side. He was, on the
    /// breathing screen, which is what Melvin saw as "off center".
    static let aspect: CGFloat = 425.0 / 522.0

    let viewModel: RiveViewModel
    private var instance: RiveDataBindingViewModel.Instance?
    /// A wave asked for before the data binding landed. `enableAutoBind` is
    /// asynchronous, and the welcome screen fires its wave 0.45 s after the
    /// screen appears, which on a cold launch is routinely too early: the
    /// trigger went to a nil instance and Otto simply never waved (Melvin,
    /// 2026-09-20: "Hes also not waving. in the start"). Anything the app says
    /// to a rig that has not bound yet is remembered and said again on bind.
    private var pendingWave = false

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
            guard let self else { return }
            self.instance = instance
            // Re-say everything the app said while this was nil. `sitting` is
            // set from `onAppear`, which routinely beats the binding, so
            // without this the breathing screen could open on the wrong pose.
            instance.booleanProperty(fromPath: "talking")?.value = self.talking
            instance.booleanProperty(fromPath: "sitting")?.value = self.sitting
            instance.booleanProperty(fromPath: "branch")?.value = self.branch
            if self.pendingWave {
                self.pendingWave = false
                instance.triggerProperty(fromPath: "wave")?.trigger()
            }
            // `wave()` and `talking` write through this instance and fail
            // quietly when it never arrives, which is the same class of silence
            // that hid the artboard-name bug. One line, once, so a rig that
            // animates but ignores the app is distinguishable from one that
            // works.
            NSLog("Otto rig: bound")
        }
    }

    /// The wave, once. Safe to call before the binding finishes: it is held
    /// and fired the moment the instance arrives.
    func wave() {
        guard let instance else { pendingWave = true; return }
        instance.triggerProperty(fromPath: "wave")?.trigger()
    }

    /// Mid-sentence head movement while `true`.
    var talking: Bool = false {
        didSet {
            instance?.booleanProperty(fromPath: "talking")?.value = talking
        }
    }

    /// Which pose the rig draws. **The rig carries its own art, so the `pose`
    /// passed to `OttoRiveView` cannot change what it shows; only this can.**
    /// The breathing screen wants him cross-legged and the welcome screen
    /// wants him upright, and for a while both got the waving art because
    /// nothing told the rig otherwise.
    var sitting: Bool = false {
        didSet {
            instance?.booleanProperty(fromPath: "sitting")?.value = sitting
        }
    }

    /// Whether he is standing on the branch, with the leaves around him
    /// (Melvin, 2026-09-20: "I want him on a branch somehow. some kind of
    /// greenery"). **Off by default, and Home never turns it on**, because
    /// Home already stands him on its own horizon under a sky.
    ///
    /// The branch is not only scenery: the same state shrinks him to 88% and
    /// lifts him onto the limb, so the artboard makes room for it without
    /// growing. Growing the artboard would have shrunk him on every screen
    /// that does not ask for a branch.
    var branch: Bool = false {
        didSet {
            instance?.booleanProperty(fromPath: "branch")?.value = branch
        }
    }
}

/// Otto at `size` points, animated when the rig is present, the still pose
/// with the pulse when it is not. Tapping is the caller's business.
struct OttoRiveView: View {
    /// The drawn HEIGHT. The width follows the artboard unless one is given.
    var size: CGFloat
    /// The pose to draw. The rig can hold two of them, cross-legged and
    /// upright; anything else falls back to the still art for that pose.
    var pose: OttoPose = .talking
    /// Mouth and head move while this is true, so a line of copy reads as
    /// something he is saying rather than something printed near him.
    var talking: Bool = false
    /// Stand him on the branch. See `OttoRig.branch`.
    var branch: Bool = false
    /// An explicit frame width. Home passes its old square frame so that
    /// screen is untouched by the aspect fix; everything else takes the
    /// artboard's own proportions.
    var width: CGFloat? = nil
    /// Set once from the owner so the same rig survives re-renders.
    @ObservedObject var rig: OttoRigHolder

    var body: some View {
        if let live = rig.rig {
            live.viewModel.view()
                .frame(width: width ?? size * OttoRig.aspect, height: size)
                .accessibilityHidden(true)
                .onAppear {
                    rig.setSitting(pose == .meditating)
                    rig.setBranch(branch)
                    rig.setTalking(talking)
                }
                .onChange(of: pose) { _, new in rig.setSitting(new == .meditating) }
                .onChange(of: branch) { _, new in rig.setBranch(new) }
                .onChange(of: talking) { _, new in rig.setTalking(new) }
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
    func setSitting(_ on: Bool) { rig?.sitting = on }
    func setBranch(_ on: Bool) { rig?.branch = on }
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
    /// Matches the Breathe timeline in Otto.riv: 5 s in, 5 s out, which is
    /// six breaths a minute, the pace every other part of 808 claims.
    static let period: TimeInterval = 10

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
