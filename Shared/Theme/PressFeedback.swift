import SwiftUI

/// What pressing a button feels and sounds like, on the phone.
///
/// Every shared button style reports its press here, and the iOS app answers
/// with onboarding's two pulses and a soft tap (`Tactile`, Melvin,
/// 2026-10-09: haptics "same as from the onboarding, for every tab switch,
/// button click"). The styles live in Shared, which the Watch compiles too,
/// and the Watch must never buzz (CLAUDE.md, "THE WATCH PLAYS NO HAPTICS"),
/// so a style only calls this hook and only the iOS app ever sets it.
enum PressFeedback {
    /// Called with `true` as a press goes down and `false` as it comes up,
    /// and whether the button is a `main` one (the one a screen exists for),
    /// which sounds a little higher.
    static var handler: ((_ pressed: Bool, _ main: Bool) -> Void)?
    /// Called as a button appears, so the haptic is ready before the first
    /// press: an unprepared Taptic Engine drops the first pulse
    /// (`PressHaptic`).
    static var prepare: (() -> Void)?
}

extension View {
    /// Reports a button style's `isPressed` to `PressFeedback`. `main` marks
    /// the button a screen exists for: the green and gold buttons, the plus.
    func pressFeedback(_ pressed: Bool, main: Bool = false) -> some View {
        onAppear { PressFeedback.prepare?() }
            .onChange(of: pressed) { _, now in PressFeedback.handler?(now, main) }
    }
}
