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
@MainActor
final class OttoAuraRig {
    static let fileName = "OttoAura"
    static let artboard = "OttoAura"
    static let stateMachine = "OttoAura"

    let viewModel: RiveViewModel
    private var instance: RiveDataBindingViewModel.Instance?

    /// Which drawing, 1 to 13. Safe to set before the binding lands: it is
    /// said again on bind, as `OttoRig` does for its flags.
    var stage: Int = OttoAura.Stage.steady.look {
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
    static func make() -> OttoAuraRig? {
        guard Bundle.main.url(forResource: fileName, withExtension: "riv") != nil else { return nil }
        do {
            let model = try RiveModel(fileName: fileName, extension: ".riv", in: .main, loadCdn: false)
            try model.setArtboard(artboard)
            try model.setStateMachine(stateMachine)
            return OttoAuraRig(model: model)
        } catch {
            NSLog("Otto aura rig failed to load: %@", String(describing: error))
            if let file = try? RiveFile(name: fileName, extension: ".riv", in: .main, loadCdn: false) {
                NSLog("Otto aura rig: the file offers artboards [%@]; this app needs '%@' with a state machine '%@'",
                      file.artboardNames().joined(separator: ", "), artboard, stateMachine)
            }
            return nil
        }
    }

    private init(model: RiveModel) {
        viewModel = RiveViewModel(model,
                                  stateMachineName: Self.stateMachine,
                                  fit: .contain,
                                  alignment: .bottomCenter,
                                  autoPlay: true,
                                  artboardName: Self.artboard)
        viewModel.riveModel?.enableAutoBind { [weak self] instance in
            guard let self else { return }
            self.instance = instance
            instance.booleanProperty(fromPath: "snap")?.value = self.snap
            instance.numberProperty(fromPath: "stage")?.value = Float(self.stage)
            NSLog("Otto aura rig: bound")
        }
    }
}

/// Holds one aura rig for as long as the view that owns it.
@MainActor
final class OttoAuraRigHolder: ObservableObject {
    let rig: OttoAuraRig?
    init() { rig = OttoAuraRig.make() }
}
