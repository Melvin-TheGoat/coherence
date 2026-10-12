import SwiftUI
import UIKit

/// How 808 answers a touch (Melvin, 2026-10-09: "add haptic feedback, same
/// as from the onboarding, for every tab switch, button click, etc, and
/// include this as an option to turn off in the settings").
///
/// **Onboarding's press, everywhere**: a heavy pulse as a button goes down
/// and a rigid one as it comes up (`PressHaptic`), and one soft note
/// (`SoundEffect.tap`) with the first, a note higher for a main button (the
/// filled green and gold ones, and the plus). Every shared button style reports to
/// it through `PressFeedback`, and `TactilePlainButtonStyle` stands in for
/// `.plain`, so a new button gets it without anyone remembering to add it.
///
/// **Settings > Haptics governs every haptic in the app** (`hapticsOn`,
/// mirrored from `Preferences.hapticsEnabled` at the root). Onboarding runs
/// before a Preferences row exists, so it gets the default, which is on.
enum Tactile {
    static var hapticsOn = true

    /// Connects the shared styles to the phone's haptics and sound.
    static func install() {
        PressFeedback.handler = { pressed, main in press(pressed, main: main) }
        PressFeedback.prepare = { if hapticsOn { PressHaptic.prepare() } }
        PressHaptic.prepare()
    }

    /// One half of a press: going down (`true`) or coming up.
    static func press(_ pressed: Bool, main: Bool = false) {
        if hapticsOn { PressHaptic.fire(pressed: pressed) }
        if pressed { AppAudio.shared.play(.tap(main: main)) }
    }

    /// A tap gesture that is a button in all but name: both halves, a beat
    /// apart, the way a finger would give them.
    static func tap() {
        press(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { press(false) }
    }
}

/// `.plain`, with the press answered. It looks exactly as a plain button
/// does: no background, no tint, the label dimmed while the finger is down.
/// Like `.plain`, only what the label draws is tappable; nothing here widens
/// a button's hit area.
struct TactilePlainButtonStyle: ButtonStyle {
    /// A button that draws its own fill and is the one the screen exists
    /// for (the plus): it sounds a note higher, as `PrimaryButtonStyle` does.
    var main = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .pressFeedback(configuration.isPressed, main: main)
    }
}

extension ButtonStyle where Self == TactilePlainButtonStyle {
    /// `.plain` with onboarding's press and the tap sound.
    static var tactile: TactilePlainButtonStyle { TactilePlainButtonStyle() }
    /// `.tactile` for a main button that draws its own fill, like the plus.
    static var tactileMain: TactilePlainButtonStyle { TactilePlainButtonStyle(main: true) }
}

extension View {
    /// A tap gesture that answers like a button: the press haptics and the
    /// tap sound, then `action`.
    func tactileTap(perform action: @escaping () -> Void) -> some View {
        onTapGesture {
            Tactile.tap()
            action()
        }
    }
}
