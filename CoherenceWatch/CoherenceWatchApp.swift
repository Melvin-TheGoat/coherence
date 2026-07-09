import SwiftUI

@main
struct CoherenceWatchApp: App {
    // NO ModelContainer on the Watch — it is a stateless sensor/compute/transfer
    // device. All persistence happens on the phone.
    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
