import SwiftUI

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
    let lastSessionID: UUID?
    let sessions: [Session]
    let scenePhase: ScenePhase
    let pick: () -> InterventionKind
    let present: (InterventionKind) -> Void

    func body(content: Content) -> some View {
        content
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
        let recent = sessions.prefix(24).map { session in
            (end: session.startedAt.addingTimeInterval(TimeInterval(session.durationSec)),
             durationSec: session.durationSec)
        }
        block.catchUp(with: Array(recent))
    }

    private func showOtto() {
        guard !sessionActive, block.claimPresentation() else { return }
        present(pick())
    }
}
