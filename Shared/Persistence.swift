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

    // MARK: - Health-stats rescue (one-time, after the 5.1.3 store split)

    /// Before the two-store split, `MeditationStats` lived in the main store.
    /// The split remapped the entity to the HealthLocal store, which starts
    /// empty — so every pre-split session showed "no results" even though its
    /// rows still sit in the old file. This one-time rescue copies them over.
    ///
    /// Call `rescueOrphanedHealthStatsIfNeeded()` BEFORE building the real
    /// container (the extract must read the old file first), then
    /// `completeRescue(_:into:)` after. Guarded by a UserDefaults flag that is
    /// only set once the copies are safely inserted, so a crash mid-rescue
    /// just retries next launch (insert dedupes by sessionID).

    static let healthRescueDoneKey = "healthStatsRescueDone.v1"

    /// SwiftData's default persistent-store location (the main store's file).
    static var defaultMainStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    static func rescueOrphanedHealthStatsIfNeeded() -> [MeditationStats] {
        guard !UserDefaults.standard.bool(forKey: healthRescueDoneKey) else { return [] }
        guard let rescued = extractOrphanedHealthStats(mainStoreURL: defaultMainStoreURL) else {
            return []   // extraction errored — leave the flag unset so a fix can retry
        }
        if rescued.isEmpty { UserDefaults.standard.set(true, forKey: healthRescueDoneKey) }
        return rescued
    }

    static func completeRescue(_ rescued: [MeditationStats], into container: ModelContainer) {
        guard !rescued.isEmpty else { return }
        insertRescuedHealthStats(rescued, into: container)
        UserDefaults.standard.set(true, forKey: healthRescueDoneKey)
    }

    /// Reads MeditationStats rows out of a (copy of the) old main-store file
    /// and returns detached copies. Returns nil on error, [] when none found.
    ///
    /// HOW: SwiftData's entity→store binding is process-global, so a temp
    /// container must use the SAME two-store shape as the real one (a
    /// single-config "old layout" container throws "store does not contain the
    /// object's entity"). So we copy the old main file (never touching the
    /// original) and mount the COPY as the HealthLocal side of a
    /// production-shaped container: lightweight migration reduces the copy to
    /// just the stats table — exactly the rows we're rescuing.
    static func extractOrphanedHealthStats(mainStoreURL: URL) -> [MeditationStats]? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: mainStoreURL.path) else { return [] }
        let tmpDir = fm.temporaryDirectory.appending(path: "health-rescue-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmpDir) }
        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let copy = tmpDir.appending(path: "stats-copy.store")
            try fm.copyItem(at: mainStoreURL, to: copy)
            // SQLite WAL sidecars can hold recent commits — copy them too.
            for ext in ["-wal", "-shm"] {
                let side = mainStoreURL.path + ext
                if fm.fileExists(atPath: side) {
                    try? fm.copyItem(atPath: side, toPath: copy.path + ext)
                }
            }
            let throwawayMain = tmpDir.appending(path: "main-throwaway.store")
            let temp = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: cloudSyncedSchema,
                                   url: throwawayMain, cloudKitDatabase: .none),
                ModelConfiguration("HealthLocal", schema: healthLocalSchema,
                                   url: copy, cloudKitDatabase: .none),
            ])
            let ctx = ModelContext(temp)
            let rows = try ctx.fetch(FetchDescriptor<MeditationStats>())
            return rows.map(detachedCopy)
        } catch {
            print("Health-stats rescue: extraction failed: \(error)")
            return nil
        }
    }

    /// Inserts rescued rows into the (HealthLocal side of the) given container,
    /// skipping sessionIDs that already have stats there.
    static func insertRescuedHealthStats(_ rescued: [MeditationStats], into container: ModelContainer) {
        guard !rescued.isEmpty else { return }
        let ctx = ModelContext(container)
        let existing = Set(((try? ctx.fetch(FetchDescriptor<MeditationStats>())) ?? []).compactMap(\.sessionID))
        for stats in rescued {
            guard let sid = stats.sessionID, !existing.contains(sid) else { continue }
            ctx.insert(stats)
        }
        try? ctx.save()
    }

    /// A context-free copy of a stats row (same field values, same id), safe to
    /// insert into a different container.
    private static func detachedCopy(_ s: MeditationStats) -> MeditationStats {
        MeditationStats(
            id: s.id,
            sessionID: s.sessionID,
            heartRateTimeseries: s.heartRateTimeseries,
            meanHR: s.meanHR,
            startHR: s.startHR,
            endHR: s.endHR,
            hrDecline: s.hrDecline,
            stillnessTimeseries: s.stillnessTimeseries,
            stillnessScore: s.stillnessScore,
            stillnessMethod: s.stillnessMethod,
            breathingRateTimeseries: s.breathingRateTimeseries,
            breathDepthTimeseries: s.breathDepthTimeseries,
            meanBreathingRate: s.meanBreathingRate,
            breathingRegularity: s.breathingRegularity,
            resonanceMatchScore: s.resonanceMatchScore,
            breathDoorwayRate: s.breathDoorwayRate,
            breathDoorwayHeldSec: s.breathDoorwayHeldSec,
            breathClarityTimeseries: s.breathClarityTimeseries,
            overallScore: s.overallScore,
            windowSec: s.windowSec,
            hopSec: s.hopSec,
            algorithmVersion: s.algorithmVersion,
            createdAt: s.createdAt
        )
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
