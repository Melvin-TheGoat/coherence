import SwiftUI
import SwiftData

@main
struct CoherenceApp: App {
    // Phase 7: CloudKit sync ON (private database, per-user). Falls back to a
    // local store when CloudKit can't provision.
    let modelContainer: ModelContainer
    @StateObject private var coordinator: SessionCoordinator
    @StateObject private var store = Store()
    @StateObject private var community = CommunityModel.app()
    @Environment(\.scenePhase) private var scenePhase

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
                .environmentObject(community)
                // Products are fetched from Apple, so this is a network call
                // and the paywall has to survive it not having finished. Until
                // it does, `store.state` is .loading. If the launch had no
                // network the store lands on .unavailable (free); coming back
                // to the foreground retries, so that person can still buy.
                .task { await store.load() }
                // A no-Watch waitlist signup that could not be delivered (no
                // network at the end of onboarding) goes out on a later launch.
                .task { await WaitlistClient.flush() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.state != .ready {
                        Task { await store.load() }
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
