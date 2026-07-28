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
        SessionReflection.self,
    ])

    /// Models safe to sync through the user's private iCloud: account, settings,
    /// tracks, the session log, and subjective reflections.
    static let cloudSyncedSchema = Schema([
        User.self,
        Preferences.self,
        MeditationTrack.self,
        Session.self,
        SessionReflection.self,
    ])

    /// Health-derived results (HR timeseries, stillness, breathing metrics).
    /// DEVICE-LOCAL ONLY, never CloudKit: App Review guideline 5.1.3(ii) forbids
    /// storing personal health information in iCloud, and the HR series is
    /// HealthKit-sourced. Kept in a separate named store so the same file is
    /// used whether the app runs in cloud or local mode.
    static let healthLocalSchema = Schema([MeditationStats.self])

    private static func healthConfig() -> ModelConfiguration {
        ModelConfiguration(
            "HealthLocal",
            schema: healthLocalSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
    }

    /// Persistent local store, CloudKit disabled. Also the fallback for
    /// `cloudKit()`. Uses the same two-store split so mode switches never move
    /// data between files.
    static func local() -> ModelContainer {
        let main = ModelConfiguration(
            schema: cloudSyncedSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [main, healthConfig()])
        } catch {
            fatalError("Failed to create local ModelContainer: \(error)")
        }
    }

    /// Persistent store with CloudKit sync (Phase 7) for the non-health models;
    /// health results stay in the device-local store. Falls back to the local
    /// container if the CloudKit container can't be created — so the app never
    /// crashes on a device/simulator without a provisioned iCloud account.
    static func cloudKit() -> ModelContainer {
        let synced = ModelConfiguration(
            schema: cloudSyncedSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [synced, healthConfig()])
        } catch {
            print("CloudKit ModelContainer unavailable, falling back to local store: \(error)")
            return local()
        }
    }

    /// In-memory store for tests and SwiftUI previews. Mirrors the same
    /// two-store split as the persistent containers: the test host app builds
    /// the real container first, and SwiftData maps entities to stores
    /// per-process — a single-store test container would route
    /// `MeditationStats` to a store it doesn't have.
    static func inMemory() -> ModelContainer {
        let main = ModelConfiguration(
            schema: cloudSyncedSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let health = ModelConfiguration(
            "HealthLocal",
            schema: healthLocalSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [main, health])
        } catch {
            fatalError("Failed to create in-memory ModelContainer: \(error)")
        }
    }
}
