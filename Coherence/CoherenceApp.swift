import SwiftUI
import SwiftData

@main
struct CoherenceApp: App {
    // Phase 0–6: local store, CloudKit OFF. Phase 7 flips this to
    // `Persistence.cloudKit()`.
    let modelContainer: ModelContainer
    @StateObject private var coordinator: SessionCoordinator

    init() {
        let container = Persistence.local()
        modelContainer = container
        let setup = ModelContext(container)
        TrackSeeder.seedIfNeeded(in: setup)                     // Phase 5: built-in tracks
        SessionStore.purgeExpired(in: setup)                    // Phase 7: 30-day account purge
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
