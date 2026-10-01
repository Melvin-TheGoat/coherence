import SwiftUI
import SwiftData

/// Block's hooks on ContentView, kept off its chain the way `FriendsHooks` is
/// (ContentView sits at the type checker's limit).
///
/// - A tap on "Otto wants a word", or opening 808 by hand right after an
///   unanswered "Ask Otto", opens one of his screens. Never over a running
///   session: they are already doing the thing.
/// - A session that lands (from the phone or the Watch) releases the rest of
///   every window it counts for. Idempotent, so it simply runs on every new
///   session and every return to the foreground.
struct BlockHooks: ViewModifier {
    @ObservedObject var block: BlockController
    let sessionActive: Bool
    /// An award is being celebrated in its own cover: Otto waits for it, or
    /// the second cover would be dropped (the known one-cover trap).
    let awardShowing: Bool
    /// One of Otto's screens is up, or queued behind another cover. Another
    /// ask while he is already asking would queue a second Otto behind the
    /// first, to appear the moment the person answers him.
    let ottoShowing: Bool
    let lastSessionID: UUID?
    let sessions: [Session]
    let scenePhase: ScenePhase
    let pick: () -> InterventionKind
    let present: (InterventionKind) -> Void

    @State private var waiting = false
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .onChange(of: awardShowing) { _, showing in
                if !showing, waiting { waiting = false; showOtto() }
            }
            .onChange(of: block.interventionRequest) { _, request in
                guard FeatureFlags.block, request != nil else { return }
                block.interventionRequest = nil
                showOtto()
            }
            .onChange(of: sessions.first?.id) { _, _ in catchUp() }
            .onChange(of: lastSessionID) { _, _ in catchUp() }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard FeatureFlags.block, phase == .active else { return }
                block.refresh()
                catchUp()
                if block.hasUnansweredAsk { showOtto() }
            }
    }

    private func catchUp() {
        guard FeatureFlags.block else { return }
        // Read from the store, not the `sessions` the view last drew: the
        // catch-up also takes back openings whose session is gone, so the
        // list has to be complete and current, including a session saved a
        // moment ago that no redraw has picked up yet. Two days back covers
        // the 36 hours it judges, whatever the session's length.
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        let fetched = (try? context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate { $0.startedAt >= cutoff }))) ?? sessions
        // A recorded sit never opens apps (`Session.isLogged`).
        let recent = fetched.filter { !$0.isLogged }.map { session in
            (end: session.startedAt.addingTimeInterval(TimeInterval(session.durationSec)),
             durationSec: session.durationSec)
        }
        block.catchUp(with: recent)
    }

    /// Otto only when something is still held once any new session has
    /// been counted: a Watch session that landed in the background may
    /// already have opened the apps, and Otto asking about nothing (with "No
    /// passes left today") is worse than no Otto.
    private func showOtto() {
        guard !sessionActive, !ottoShowing else { return }
        catchUp()
        block.clearDeliveredAsk()
        guard !block.holding().isEmpty else { return }
        if awardShowing { waiting = true; return }
        guard block.claimPresentation() else { return }
        present(pick())
    }
}
