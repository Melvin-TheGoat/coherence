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
        _coordinator = StateObject(wrappedValue: SessionCoordinator(container: container))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
        .modelContainer(modelContainer)
    }
}
