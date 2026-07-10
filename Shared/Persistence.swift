import Foundation
import SwiftData

/// ModelContainer factories.
///
/// Phase 0–6 use `local()` — a persistent on-device store with CloudKit OFF, so
/// the app runs under free provisioning with no iCloud entitlement. The models
/// are already shaped CloudKit-safe (all properties optional/defaulted, no
/// `.unique`, no relationships), so Phase 7 flips to `cloudKit()` as a one-line
/// change in CoherenceApp.
///
/// The Watch never builds a container — all persistence happens on the phone.
enum Persistence {

    /// Every @Model type in the app. Keep this in sync when a model is added.
    static let schema = Schema([
        User.self,
        Preferences.self,
        MeditationTrack.self,
        Session.self,
        HeartbeatSeries.self,
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

    /// Persistent store with CloudKit sync. Written now, NOT called until Phase 7
    /// (needs the paid program + iCloud entitlement). Flipping CoherenceApp from
    /// `local()` to `cloudKit()` is the only change required to enable sync.
    static func cloudKit() -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create CloudKit ModelContainer: \(error)")
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
