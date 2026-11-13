import SwiftUI
import RiveRuntime

/// Otto's seven aura states, animated in Rive (Melvin, 2026-09-22: "the bugs
/// should come and go periodically. The aura should swirl around. He should
/// be floating up and down a little bit when hes floating. Use rive
/// obviously").
///
/// A file of its own, `OttoAura.riv`, NOT a second artboard in `Otto.riv`:
/// that export only ever carried its first artboard (see CLAUDE.md), and
/// the session rig Aziz edits must stay one artboard. One artboard here too,
/// "OttoAura", 664 x 744, which is exactly the canvas the stills are cut to
/// (`mockups/otto-v4/canvas.json`), so the rig and the stills frame the same
/// and either can stand in for the other. One state machine, "OttoAura", and
/// one view model property the app writes: `stage`, 1 to 13 (the seven
/// stages at the odd numbers, a drawing halfway between each pair at the
/// even ones; `OttoAura.look(level:)`).
///
/// The machine does everything else by itself: which drawing shows, the
/// bugs coming and going at the bottom, the light swirling at the top, and
/// the float. The app never drives a frame.
///
/// **It also keeps its own account of where he is** (`pose`), because the
/// hat is drawn by SwiftUI on top and has to sit on his head exactly. The
/// runtime cannot hand back a node's position, so the numbers below are read
/// out of the shipping `OttoAura.riv` itself and replayed on the rig's own
/// clock (Melvin, 2026-09-28: the hats sat low from look 10 up and did not
/// float with him; the old hand-copied lifts and scales were 4 to 16 units
/// and up to 5% off, and the old float ran on a timer of its own).
/// **Re-read them whenever the rig's `Lift`, `Bob`, the look timelines or
/// `Float` change** (`tools/riv_dump.py`).
@MainActor
final class OttoAuraRig {
    static let fileName = "OttoAura"
    static let artboard = "OttoAura"
    static let stateMachine = "OttoAura"

    /// Which rig, and where it puts him. Otto's thirteen looks, or one of his
    /// forms' seven (2026-11-12: `Companion<Form>.riv`, built by
    /// `tools/companion_rig_build.py` on the same 664 x 744 canvas with the
    /// figure at (332, 649): artboard, state machine and view model all
    /// "Companion", the same `stage` and `snap`). Read the numbers out of the
    /// shipping files with `tools/riv_dump.py`.
    struct Spec: Equatable {
        let fileName: String
        let artboard: String
        let stateMachine: String
        let lift: [Double]
        let scale: [Double]
        let floatsFrom: Int
        let restingLook: Int

        static let otto = Spec(fileName: OttoAuraRig.fileName, artboard: OttoAuraRig.artboard,
                               stateMachine: OttoAuraRig.stateMachine, lift: OttoAuraRig.lift,
                               scale: OttoAuraRig.scale, floatsFrom: OttoAuraRig.floatsFrom,
                               restingLook: OttoAura.Stage.steady.look)

        /// The forms' rigs: `Lift` is 0 for stages 1 to 5, -26 at 6 and -40
        /// at 7; `Bob` is never scaled; the float (the same 0 to -10 curve as
        /// Otto's) runs from stage 6 up. Read from all four files.
        static let companionLift: [Double] = [0, 0, 0, 0, 0, -26, -40]

        static func of(_ form: Companion) -> Spec {
            guard form != .otto else { return .otto }
            return Spec(fileName: "Companion\(form.key)", artboard: "Companion", stateMachine: "Companion",
                        lift: companionLift, scale: Array(repeating: 1, count: 7), floatsFrom: 6,
                        restingLook: OttoAura.Stage.steady.rawValue)
        }
    }

    let spec: Spec
    let viewModel: OttoAuraRiveViewModel
    private var instance: RiveDataBindingViewModel.Instance?

    // MARK: - Where he is, frame by frame

    /// `Lift`'s y and `Bob`'s scale in each look's one-frame timeline (S1 to
    /// S7 at the odd looks, M1 to M6 at the even ones), in look order.
    static let lift: [Double] = [0, 0, 0, 0, 0, 0, 0, 0, -16, -23, -30, -39, -48]
    static let scale: [Double] = [1.0345, 1.0676, 1.0187, 1.0471, 0.9967, 1.0152, 0.9836,
                                  1.049, 1.005, 1.049, 1.0582, 1.0619, 1.0582]
    /// Each look's body image inside `Bob`: its centre and its pixel height
    /// (images are drawn at scale 1 with their origin at their centre).
    static let body: [(x: Double, y: Double, h: Double)] = [
        (1.0, -293.0, 590), (0, -282.0, 566), (-3.0, -295.0, 600), (0, -288.0, 578),
        (0, -281.0, 654), (-0.5, -296.0, 596), (0.5, -305.5, 617), (0.5, -287.0, 576),
        (0, -299.0, 604), (1.0, -287.5, 579), (0.5, -284.5, 575), (2.5, -285.0, 576),
        (0.5, -283.5, 577),
    ]
    /// The `Stage` layer's look-to-look fade, and the `Float` layer's blend
    /// between `Still` and `Float` (stage 9 and up).
    static let lookFade = 0.5
    static let floatBlend = 0.7
    static let floatsFrom = 9

    struct Pose {
        var lift: Double
        var scale: Double
        /// `Bob`'s y: the float, 0 to -10 and back every five seconds.
        var bob: Double
    }

    /// A look at rest: no fade, no float. For layout (how tall a hat stands).
    static func rest(_ look: Int) -> Pose {
        let i = min(max(look, 1), 13) - 1
        return Pose(lift: lift[i], scale: scale[i], bob: 0)
    }

    /// The rig's own clock: the sum of every advance Rive reports.
    private(set) var clock: Double = 0
    private var bound = false
    private var shown: Int?
    private var fadeFrom = (lift: 0.0, scale: 1.0)
    private var fadeStart = 0.0
    private var fadeLength = 0.0
    private var floatStart: Double?
    private var floatStop: Double?

    /// A look of THIS rig at rest.
    func restPose(_ look: Int) -> Pose {
        let i = min(max(look, 1), spec.lift.count) - 1
        return Pose(lift: spec.lift[i], scale: spec.scale[i], bob: 0)
    }

    /// Where `Lift` and `Bob` are right now.
    func pose() -> Pose {
        guard let shown else { return restPose(stage) }
        let i = min(max(shown, 1), spec.lift.count) - 1
        let m = fadeLength > 0 ? min(1, (clock - fadeStart) / fadeLength) : 1
        var bob = 0.0
        if let start = floatStart {
            let t = clock - start
            var mix = min(1, t / Self.floatBlend)
            if let stop = floatStop { mix *= 1 - min(1, (clock - stop) / Self.floatBlend) }
            bob = mix * Self.float(t)
        }
        return Pose(lift: fadeFrom.lift + (spec.lift[i] - fadeFrom.lift) * m,
                    scale: fadeFrom.scale + (spec.scale[i] - fadeFrom.scale) * m,
                    bob: bob)
    }

    /// The `Float` timeline: 300 frames at 60 fps, looping, keyed 0 at frame
    /// 0, -10 at 150 and 0 at 300, each segment on Rive's default cubic ease
    /// (0.42, 0, 0.58, 1).
    static func float(_ t: Double) -> Double {
        let f = (t * 60).truncatingRemainder(dividingBy: 300)
        return f < 150 ? -10 * ease(f / 150) : -10 * (1 - ease((f - 150) / 150))
    }

    static func ease(_ x: Double) -> Double {
        let (x1, y1, x2, y2) = (0.42, 0.0, 0.58, 1.0)
        func bez(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<30 {
            let v = bez(t, x1, x2)
            if abs(v - x) < 1e-6 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return bez(t, y1, y2)
    }

    /// Called after every advance, with what the machine just did: a look it
    /// had not shown starts its fade at the start of this advance (instant on
    /// the first, from Entry, and under `snap`), and so does the float.
    private func advanced(_ seconds: Double) {
        let before = clock
        clock += seconds
        guard bound else { return }
        if shown != stage {
            if let shown, !snap {
                let now = poseLiftScale(at: before, look: shown)
                fadeFrom = now
                fadeStart = before
                fadeLength = Self.lookFade
            } else {
                fadeLength = 0
            }
            shown = stage
        }
        if stage >= spec.floatsFrom {
            if floatStart == nil || floatStop != nil { floatStart = before; floatStop = nil }
        } else if floatStart != nil, floatStop == nil {
            floatStop = before
        }
        if let stop = floatStop, clock - stop >= Self.floatBlend { floatStart = nil; floatStop = nil }
    }

    private func poseLiftScale(at time: Double, look: Int) -> (lift: Double, scale: Double) {
        let i = min(max(look, 1), spec.lift.count) - 1
        let m = fadeLength > 0 ? min(1, (time - fadeStart) / fadeLength) : 1
        return (fadeFrom.lift + (spec.lift[i] - fadeFrom.lift) * m,
                fadeFrom.scale + (spec.scale[i] - fadeFrom.scale) * m)
    }

    /// Which drawing, 1 to 13. Safe to set before the binding lands: it is
    /// said again on bind, as `OttoRig` does for its flags.
    var stage: Int = 0 {
        didSet {
            guard stage != oldValue else { return }
            instance?.numberProperty(fromPath: "stage")?.value = Float(stage)
        }
    }

    /// Change drawing at once instead of cross-fading into it. The fade is
    /// right on Home, where the look changes once when a session lands, and
    /// wrong under a finger: dragging the stress bar through thirteen looks
    /// left him half a second behind the thumb (Melvin, 2026-09-23: "make it
    /// like instant as you scroll through").
    var snap = false {
        didSet {
            guard snap != oldValue else { return }
            instance?.booleanProperty(fromPath: "snap")?.value = snap
        }
    }

    /// Nil when the file is not in the bundle or will not load; the figure
    /// then draws the still for its stage, so a bad export costs motion and
    /// never a picture. Logged with NSLog for the reason `OttoRig.make` gives.
    /// The parsed file, kept for the life of the app. Parsing it is the
    /// expensive part of a rig (hundreds of KB, on the main thread), and every
    /// screen with Otto on it used to parse it again as it appeared, which
    /// stalled the slide onto that screen for a few frames (Aziz, 2026-09-23:
    /// the jumpy transitions). Each rig still gets its own artboard instance.
    private static var cachedFiles: [String: RiveFile] = [:]

    private static func parsedFile(_ name: String) throws -> RiveFile {
        if let file = cachedFiles[name] { return file }
        let file = try RiveFile(name: name, extension: ".riv", in: .main, loadCdn: false)
        cachedFiles[name] = file
        return file
    }

    /// Parses the file now, while nothing is moving, so the first screen that
    /// shows him does not pay for it mid-transition. The form he wears too.
    static func preload() {
        for spec in Set([Spec.otto.fileName, Spec.of(CompanionBook.chosen()).fileName]) {
            guard Bundle.main.url(forResource: spec, withExtension: "riv") != nil else { continue }
            _ = try? parsedFile(spec)
        }
    }

    static func make(_ spec: Spec = .otto) -> OttoAuraRig? {
        guard Bundle.main.url(forResource: spec.fileName, withExtension: "riv") != nil else { return nil }
        do {
            let model = RiveModel(riveFile: try parsedFile(spec.fileName))
            try model.setArtboard(spec.artboard)
            try model.setStateMachine(spec.stateMachine)
            return OttoAuraRig(model: model, spec: spec)
        } catch {
            NSLog("Otto aura rig %@ failed to load: %@", spec.fileName, String(describing: error))
            if let file = try? RiveFile(name: spec.fileName, extension: ".riv", in: .main, loadCdn: false) {
                NSLog("Otto aura rig: the file offers artboards [%@]; this app needs '%@' with a state machine '%@'",
                      file.artboardNames().joined(separator: ", "), spec.artboard, spec.stateMachine)
            }
            return nil
        }
    }

    private init(model: RiveModel, spec: Spec) {
        self.spec = spec
        self.stage = spec.restingLook
        viewModel = OttoAuraRiveViewModel(model,
                                          stateMachineName: spec.stateMachine,
                                          fit: .contain,
                                          alignment: .bottomCenter,
                                          autoPlay: true,
                                          artboardName: spec.artboard)
        viewModel.onAdvance = { [weak self] seconds in self?.advanced(seconds) }
        viewModel.riveModel?.enableAutoBind { [weak self] instance in
            guard let self else { return }
            self.instance = instance
            instance.booleanProperty(fromPath: "snap")?.value = self.snap
            instance.numberProperty(fromPath: "stage")?.value = Float(self.stage)
            self.bound = true
            NSLog("Otto aura rig: bound (%@)", self.spec.fileName)
        }
    }
}

/// Reports each of Rive's advances, so `OttoAuraRig` can keep the rig's clock.
final class OttoAuraRiveViewModel: RiveViewModel {
    var onAdvance: ((Double) -> Void)?

    override func player(didAdvanceby seconds: Double, riveModel: RiveModel?) {
        super.player(didAdvanceby: seconds, riveModel: riveModel)
        onAdvance?(seconds)
    }
}

/// Holds one aura rig for as long as the view that owns it, and swaps it
/// when the form he wears changes.
@MainActor
final class OttoAuraRigHolder: ObservableObject {
    @Published private(set) var rig: OttoAuraRig?
    private(set) var form: Companion
    init(form: Companion = .otto) {
        self.form = form
        rig = OttoAuraRig.make(.of(form))
    }

    /// Swap to `next`'s rig, already told which drawing and whether to snap.
    /// The rig view's own `onAppear` can run on the OLD rig before the swap
    /// lands, so a figure showing a form other than the one worn (the Hat
    /// lab, Otto's forms) left every new rig at its resting Steady.
    func use(_ next: Companion, stage: Int, snap: Bool) {
        guard next != form else { return }
        form = next
        let made = OttoAuraRig.make(.of(next))
        made?.snap = snap
        made?.stage = stage
        rig = made
    }
}
