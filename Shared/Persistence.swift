import Foundation
import SwiftData

/// ModelContainer factories.
///
/// Phase 7 uses `cloudKit()` — a persistent store that mirrors each user's rows
/// to their PRIVATE iCloud database (personal cross-device sync + backup; nothing
/// shared between users). The models were shaped CloudKit-safe from day one (all
/// properties optional/defaulted, no `.unique`, no relationships), so the flip is
/// a one-line change in CoherenceApp. `cloudKit()` falls back to `local()` if the
/// CloudKit container can't init (no iCloud account, simulator, or a dev whose
/// capability isn't provisioned yet) — the app still runs, just without sync.
///
/// The Watch never builds a container — all persistence happens on the phone.
enum Persistence {

    /// Every @Model type in the app. Keep this in sync when a model is added.
    static let schema = Schema([
        User.self,
        Preferences.self,
        MeditationTrack.self,
        Session.self,
        MeditationStats.self,
    ])

    /// Persistent local store, CloudKit disabled. Used now (Phase 0 onward).
    static func local() -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create local ModelContainer: \(error)")
        }
    }

    /// Persistent store with CloudKit sync (Phase 7). Falls back to the local
    /// store if the CloudKit container can't be created — so the app never
    /// crashes on a device/simulator without a provisioned iCloud account.
    static func cloudKit() -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("CloudKit ModelContainer unavailable, falling back to local store: \(error)")
            return local()
        }
    }

    /// In-memory store for tests and SwiftUI previews.
    static func inMemory() -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create in-memory ModelContainer: \(error)")
        }
    }
}
