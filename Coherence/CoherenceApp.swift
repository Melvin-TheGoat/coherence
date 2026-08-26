import SwiftUI
import SwiftData

@main
struct CoherenceApp: App {
    // Phase 7: CloudKit sync ON (private database, per-user). Falls back to a
    // local store when CloudKit can't provision.
    let modelContainer: ModelContainer
    @StateObject private var coordinator: SessionCoordinator
    @StateObject private var store = Store()

    init() {
        Analytics.start()   // no-op until a provider key is set
        // One-time rescue of pre-split health stats — the extract MUST run
        // before the split container first opens the main store.
        let rescued = Persistence.rescueOrphanedHealthStatsIfNeeded()
        let container = Persistence.cloudKit()
        modelContainer = container
        #if DEBUG
        CloudSyncProbe.start()   // prints the sync story to the launch console
        #endif
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
                .environmentObject(store)
                // Products are fetched from Apple, so this is a network call
                // and the paywall has to survive it not having finished. Until
                // it does, `store.state` is .loading and the screen shows the
                // beta copy, which is also the correct answer if it never
                // finishes.
                .task { await store.load() }
        }
        .modelContainer(modelContainer)
    }
}
