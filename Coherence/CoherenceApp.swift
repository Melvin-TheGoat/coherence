import SwiftUI
import SwiftData

@main
struct CoherenceApp: App {
    // Phase 7: CloudKit sync ON (private database, per-user). Falls back to a
    // local store when CloudKit can't provision.
    let modelContainer: ModelContainer
    @StateObject private var coordinator: SessionCoordinator

    init() {
        // One-time rescue of pre-split health stats — the extract MUST run
        // before the split container first opens the main store.
        let rescued = Persistence.rescueOrphanedHealthStatsIfNeeded()
        let container = Persistence.cloudKit()
        modelContainer = container
        Persistence.completeRescue(rescued, into: container)
        let setup = ModelContext(container)
        TrackSeeder.seedIfNeeded(in: setup)                     // Phase 5: built-in tracks
        SessionStore.purgeExpired(in: setup)                    // Phase 7: 30-day account purge
        ScoreMigration.backfillIfNeeded(in: setup)              // v3 score across all history
        _coordinator = StateObject(wrappedValue: SessionCoordinator(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
        }
        .modelContainer(modelContainer)
    }
}
