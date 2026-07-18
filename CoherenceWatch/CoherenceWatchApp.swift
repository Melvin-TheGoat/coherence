import SwiftUI

@main
struct CoherenceWatchApp: App {
    // NO ModelContainer on the Watch — it is a stateless sensor/compute/transfer
    // device. All persistence happens on the phone. The session manager owns the
    // WCSession + workout for the whole app lifetime.
    @StateObject private var manager = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(manager)
        }
    }
}
