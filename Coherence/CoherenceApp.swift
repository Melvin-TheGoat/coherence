import SwiftUI
import SwiftData

@main
struct CoherenceApp: App {
    // Phase 0–6: local store, CloudKit OFF. Phase 7 flips this to
    // `Persistence.cloudKit()`.
    let modelContainer: ModelContainer = Persistence.local()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
