import SwiftUI
import SwiftData

@main
struct CoherenceApp: App {
    // Phase 7: CloudKit sync ON (private database, per-user). Falls back to a
    // local store when CloudKit can't provision.
    let modelContainer: ModelContainer
    @StateObject private var coordinator: SessionCoordinator
    @StateObject private var store: Store
    @StateObject private var community: CommunityModel
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
        // The invite reward's balance lives on Preferences; the store reads it
        // to resolve per-session entitlements, the community model writes it.
        let ledger = RewardLedger(context: container.mainContext)
        let store = Store()
        store.ledger = ledger
        _store = StateObject(wrappedValue: store)
        _community = StateObject(wrappedValue: CommunityModel.app(ledger: ledger))
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
                // Friends: profile, feed, and any invite reward that landed
                // while the app was closed.
                .task { if FeatureFlags.friends { await community.load() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.state != .ready {
                        Task { await store.load() }
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
