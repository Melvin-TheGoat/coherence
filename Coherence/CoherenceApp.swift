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
        // Set before launch finishes, so a tap that opened the app is still
        // delivered. Installed on every build, not only Block's: it is also
        // what plays the timed session's end chime with 808 on screen.
        BlockNotifications.shared.install()
        // One-time rescue of pre-split health stats — the extract MUST run
        // before the split container first opens the main store.
        let rescued = Persistence.rescueOrphanedHealthStatsIfNeeded()
        let container = Persistence.cloudKit()
        modelContainer = container
        #if DEBUG
        CloudSyncProbe.start()   // prints the sync story to the launch console
        MainThreadWatch.shared.start()   // names the step a freeze happened in (2026-10-06)
        #endif
        Persistence.completeRescue(rescued, into: container)
        let setup = ModelContext(container)
        TrackSeeder.seedIfNeeded(in: setup)                     // Phase 5: built-in tracks
        SessionStore.purgeExpired(in: setup)                    // accounts older builds soft-deleted (deletion is immediate since 2026-09-29)
        SessionStore.repairOwnership(in: setup)                 // sessions filed under a stray bootstrap row (2026-09-29)
        OttoAura.markGlowStartIfNeeded()                        // Otto's glow counts from 1.1's first launch, at 50
        ScoreMigration.backfillIfNeeded(in: setup)              // v3 score across all history
        _coordinator = StateObject(wrappedValue: SessionCoordinator(container: container))
        // The invite reward's balance lives on Preferences; the store reads it
        // to resolve per-session entitlements, the community model writes it.
        let ledger = RewardLedger(context: container.mainContext)
        let store = Store()
        store.ledger = ledger
        _store = StateObject(wrappedValue: store)
        let community = CommunityModel.app(ledger: ledger)
        let mainContext = container.mainContext
        community.firstLocalSession = {
            var d = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)])
            d.fetchLimit = 1
            return (try? mainContext.fetch(d))?.first?.startedAt
        }
        // Every session, all sources — Watch, phone, hand-logged — for the
        // practice stats published on my profile (`syncPracticeStats`), the
        // same set the streak already reads.
        community.allSessions = {
            let d = FetchDescriptor<Session>()
            return ((try? mainContext.fetch(d)) ?? []).map { ($0.startedAt, $0.durationSec) }
        }
        community.onPostRemoved = { sessionID in
            if let row = SessionStore.reflection(for: sessionID, in: mainContext) {
                row.visibility = "private"
                row.updatedAt = Date()
                try? mainContext.save()
            }
        }
        _community = StateObject(wrappedValue: community)
        // Every session written, phone or Watch, current or stale: Block
        // opens the rest of the windows it counts for (2026-09-22), and
        // Friends republishes how often I meditate (2026-09-27). One hook,
        // set once at launch, so a Watch session landing while 808 is in the
        // background still does both.
        SessionCoordinator.onSessionSaved = { startedAt, durationSec in
            if FeatureFlags.block {
                Task { @MainActor in
                    BlockController.shared.recordSession(
                        endingAt: startedAt.addingTimeInterval(TimeInterval(durationSec)),
                        durationSec: durationSec)
                }
            }
            Task { @MainActor in
                await community.syncPracticeStats(force: true)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // One rounded family everywhere (see `DisplayFont`): every
                // `.system(size:)` and text style below resolves to it.
                .fontDesign(.rounded)
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
                // Do Not Disturb that 808 still owes back: a sit that ended
                // with the phone locked, or iOS closing 808 mid-sit. Asked
                // about with a one-tap alert, never opened by itself (App
                // Review pass, 2026-09-29).
                .task { await FocusShortcut.shared.becameActive() }
                .modifier(FocusRestorePrompt())
                // The Silence and Restore shortcuts answer here: x-success,
                // x-error or x-cancel. Only a success counts (App Review
                // pass, 2026-09-29; see FocusShortcut.handle).
                .onOpenURL { url in
                    // The home screen widget's tap opens Home (WidgetLink).
                    if !FocusShortcut.shared.handle(url) { WidgetLink.handle(url) }
                }
                // An account deletion whose Friends cleanup could not finish
                // (no network, no iCloud, at the exact moment somebody left)
                // retries here until it does. See
                // CommunityModel.retryPendingDeletion.
                .task { await CommunityModel.retryPendingDeletion() }
                // Posting was removed 2026-09-27: this takes down whatever
                // this person had already shared, once, retrying on a later
                // launch if it can't reach iCloud. See
                // CommunityModel.clearMyPostsIfNeeded.
                .task { await community.clearMyPostsIfNeeded() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.state != .ready {
                        Task { await store.load() }
                    }
                    if phase == .active {
                        Task { await FocusShortcut.shared.becameActive() }
                        // Gated to once every few minutes inside
                        // `syncPracticeStats`, so coming back to the app
                        // repeatedly costs at most one write.
                        Task { await community.syncPracticeStats() }
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
