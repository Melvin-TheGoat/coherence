import SwiftUI

/// The app's live view of Otto's forms (`CompanionBook`, which keeps the
/// rules and the stored state). Published, so Home, the Shop and every figure
/// redraw when a rebirth plays or a form is chosen, and the glow (which
/// restarts at 50 on a rebirth) moves with them.
@MainActor
final class CompanionStore: ObservableObject {
    static let shared = CompanionStore()

    @Published private(set) var chosen: Companion = CompanionBook.chosen()
    @Published private(set) var announced: [Companion] = CompanionBook.announced()
    /// When the glow last restarted at 50 (`OttoAura.glowRestart`).
    @Published private(set) var restart: Date? = CompanionBook.glowRestart()
    /// Rebirths played since launch, for "2 of 2" when a member catches up.
    @Published private(set) var playedThisLaunch = 0

    /// The form every figure draws: the chosen one, or PREVIEW_COMPANION.
    var effective: Companion { Self.preview ?? chosen }

    /// Forms that can be picked: Otto and every rebirth that has played.
    var available: [Companion] { [.otto] + announced.sorted() }

    /// Re-read after anything outside this store changed the book (sign-out,
    /// account deletion).
    func refresh() {
        chosen = CompanionBook.chosen()
        announced = CompanionBook.announced()
        restart = CompanionBook.glowRestart()
    }

    /// Rebirths these lifetime points have earned that have not played yet,
    /// in order.
    func pending(lifetime: Int) -> [Companion] {
        CompanionBook.pending(lifetime: lifetime, announced: announced)
    }

    /// The rebirth played: he wears the new form and his glow starts again
    /// at 50 (`CompanionBook.announce`).
    func announce(_ form: Companion) {
        guard CompanionBook.announce(form) else { return }
        playedThisLaunch += 1
        refresh()
        Analytics.track(.companionUnlocked(form: form.rawValue))
    }

    /// A form chosen in Otto's forms. The glow stays where it is.
    func choose(_ form: Companion) {
        guard CompanionBook.choose(form) else { return }
        refresh()
        Analytics.track(.companionChosen(form: form.rawValue))
    }

    /// PREVIEW_COMPANION=<redPanda|tiger|phoenix|dragon|otto> (DEBUG) draws
    /// that form everywhere, unlocked or not, without storing anything.
    static var preview: Companion? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PREVIEW_COMPANION"].flatMap(Companion.init(rawValue:))
        #else
        return nil
        #endif
    }

    /// PREVIEW_EVOLVE=<form> (DEBUG) replays that form's rebirth on a quiet
    /// Home, once a launch, without storing it.
    static var previewEvolve: Companion? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PREVIEW_EVOLVE"].flatMap(Companion.init(rawValue:))
        #else
        return nil
        #endif
    }
}
