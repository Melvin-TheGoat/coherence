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

    /// Which store the app actually ended up with. `cloudKit()` falls back to a
    /// local store when the container can't init, and that fallback used to be
    /// invisible: a `print` nobody sees on a device. A silently non-syncing app
    /// looks identical to a working one until a user wipes their phone, so the
    /// outcome is recorded here and surfaced in Settings under DEBUG.
    enum Mode: Equatable {
        case cloudKit
        case localFallback(String)
        case localByDesign

        var label: String {
            switch self {
            case .cloudKit:            return "CloudKit sync active"
            case .localByDesign:       return "Local store (by design)"
            case .localFallback:       return "NOT SYNCING (fell back to local)"
            }
        }
        var reason: String? {
            if case .localFallback(let why) = self { return why }
            return nil
        }
    }

    private(set) static var mode: Mode = .localByDesign

    /// Every @Model type in the app. Keep this in sync when a model is added.
    static let schema = Schema([
        User.self,
        Preferences.self,
        MeditationTrack.self,
        Session.self,
        MeditationStats.self,
        SessionReflection.self,
        SessionPhoto.self,
    ])

    /// Models safe to sync through the user's private iCloud: account, settings,
    /// tracks, the session log, and subjective reflections.
    static let cloudSyncedSchema = Schema([
        User.self,
        Preferences.self,
        MeditationTrack.self,
        Session.self,
        SessionReflection.self,
        SessionPhoto.self,
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
            groupContainer: storeContainer,
            cloudKitDatabase: .none
        )
    }

    /// Where the stores live: the app's own container, never the App Group's
    /// (Melvin, 2026-09-29, found in the pre-1.1 audit).
    ///
    /// `ModelConfiguration` defaults to `groupContainer: .automatic`, which
    /// puts the stores in the App Group's container as soon as the app holds
    /// one, and it has since Block added the group on 2026-09-22. Every 1.0
    /// install keeps its stores in the app's own container, so a 1.1 on the
    /// default would open an EMPTY database on update: onboarding again, and
    /// the device-local health results gone for good. Nothing else reads
    /// these stores; Block shares only UserDefaults through the group.
    static let storeContainer: ModelConfiguration.GroupContainer = .none

    private static var storesPlaced = false

    /// Phones that ran a build between 2026-09-22 and 2026-09-29 (the
    /// founders' phones, the beta, the simulators) wrote their stores into
    /// the App Group's container. Before anything opens a store, a group copy
    /// that is newer than the app container's (or the only one) is moved back
    /// to where every build now looks. The app container's older copy is
    /// renamed aside, never deleted. Once per launch, and on a phone that
    /// never had a group store it is a directory lookup and nothing else.
    static func moveStoresOutOfAppGroupIfNeeded() {
        guard !storesPlaced else { return }
        storesPlaced = true
        let fm = FileManager.default
        guard let bundle = Bundle.main.bundleIdentifier,
              let group = fm.containerURL(forSecurityApplicationGroupIdentifier: "group." + bundle)
        else { return }
        let from = group.appending(path: "Library/Application Support")
        let to = URL.applicationSupportDirectory
        for store in ["default", "HealthLocal"] {
            guard let groupDate = lastWritten(storeParts(store, in: from)) else { continue }
            if let appDate = lastWritten(storeParts(store, in: to)), appDate >= groupDate { continue }
            moveStore(store, from: from, to: to)
        }
    }

    /// Everything Core Data keeps for one store: the SQLite file, its
    /// write-ahead log and shared memory (most recent writes live in the
    /// log), and the support folder with the photos kept as external data.
    static func storeParts(_ store: String, in dir: URL) -> [URL] {
        [dir.appending(path: store + ".store"), dir.appending(path: store + ".store-wal"),
         dir.appending(path: store + ".store-shm"), dir.appending(path: "." + store + "_SUPPORT")]
    }

    /// When the store or its log was last written (the log is written on
    /// every save, the store only at a checkpoint). nil when neither exists.
    private static func lastWritten(_ parts: [URL]) -> Date? {
        parts.prefix(2).compactMap {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }.max()
    }

    /// Moves one store's files from the App Group's folder into the app's,
    /// all or nothing (Melvin, 2026-09-29, second pass of the pre-1.1 audit).
    ///
    /// Two rules, both about never losing a write:
    /// - **A set-aside copy is never deleted.** Each one gets its own
    ///   timestamped name (`default.store.before-group-move-20260929T101500Z`),
    ///   so a second move on a later launch cannot overwrite the first. The
    ///   first version removed any earlier set-aside file to make room.
    /// - **A move that fails part way is put back exactly as it was.** Every
    ///   rename is recorded and, on the first failure, undone in reverse
    ///   order: the app's own files return to their names and the group copy
    ///   stays in the group, to be tried again next launch. Without this a
    ///   `.store` could land here while its `-wal` (which holds the newest
    ///   writes) stayed behind, or the app's old `-wal` could be left beside
    ///   a store it does not belong to, which SQLite would replay into it.
    ///
    /// `move` is FileManager's in the app; a test passes one that fails on
    /// cue. Returns whether the store moved.
    @discardableResult
    static func moveStore(_ store: String, from: URL, to: URL, now: Date = Date(),
                          move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) -> Bool {
        let fm = FileManager.default
        let stamp = setAsideStamp(now)
        var done: [(from: URL, to: URL)] = []
        do {
            try fm.createDirectory(at: to, withIntermediateDirectories: true)
            for old in storeParts(store, in: to) where fm.fileExists(atPath: old.path) {
                let aside = setAsideURL(for: old, stamp: stamp)
                try move(old, aside)
                done.append((old, aside))
                // The set-aside health copy is still health data: it stays
                // out of iCloud Backup like the live store (5.1.3(ii)).
                if store == "HealthLocal" {
                    var file = aside
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    try? file.setResourceValues(values)
                }
            }
            for (src, dst) in zip(storeParts(store, in: from), storeParts(store, in: to))
            where fm.fileExists(atPath: src.path) {
                try move(src, dst)
                done.append((src, dst))
            }
            return true
        } catch {
            print("Moving the \(store) store out of the App Group failed; putting everything back: \(error)")
            for step in done.reversed() {
                do { try move(step.to, step.from) } catch {
                    print("Could not put \(step.to.lastPathComponent) back: \(error)")
                }
            }
            return false
        }
    }

    /// "20260929T101500Z": sortable, and the same for every file of one move.
    private static func setAsideStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    /// A name beside `original` that nothing has used yet. Two moves in the
    /// same second get "-2", "-3".
    private static func setAsideURL(for original: URL, stamp: String) -> URL {
        let base = original.path + ".before-group-move-" + stamp
        var candidate = URL(fileURLWithPath: base)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: base + "-\(n)")
            n += 1
        }
        return candidate
    }

    /// Persistent local store, CloudKit disabled. Also the fallback for
    /// `cloudKit()`. Uses the same two-store split so mode switches never move
    /// data between files.
    static func local() -> ModelContainer {
        moveStoresOutOfAppGroupIfNeeded()
        let main = ModelConfiguration(
            schema: cloudSyncedSchema,
            isStoredInMemoryOnly: false,
            groupContainer: storeContainer,
            cloudKitDatabase: .none
        )
        do {
            let health = healthConfig()
            let container = try ModelContainer(for: schema, configurations: [main, health])
            if mode == .localByDesign { mode = .localByDesign }
            excludeFromBackup(storeAt: health.url)
            return container
        } catch {
            fatalError("Failed to create local ModelContainer: \(error)")
        }
    }

    /// Persistent store with CloudKit sync (Phase 7) for the non-health models;
    /// health results stay in the device-local store. Falls back to the local
    /// container if the CloudKit container can't be created — so the app never
    /// crashes on a device/simulator without a provisioned iCloud account.
    static func cloudKit() -> ModelContainer {
        moveStoresOutOfAppGroupIfNeeded()
        let synced = ModelConfiguration(
            schema: cloudSyncedSchema,
            isStoredInMemoryOnly: false,
            groupContainer: storeContainer,
            cloudKitDatabase: .automatic
        )
        do {
            let health = healthConfig()
            let container = try ModelContainer(for: schema, configurations: [synced, health])
            mode = .cloudKit
            excludeFromBackup(storeAt: health.url)
            return container
        } catch {
            // Deliberately not fatal: a dev machine or an unprovisioned build
            // should still run. But it must never again be silent.
            mode = .localFallback(String(describing: error))
            print("CloudKit ModelContainer unavailable, falling back to local store: \(error)")
            let fallback = local()
            mode = .localFallback(String(describing: error))
            return fallback
        }
    }

    /// Keeps the health store out of iCloud Backup (Melvin, 2026-09-29, App
    /// Review 5.1.3(ii): personal health information may not be stored in
    /// iCloud). Keeping `MeditationStats` out of CloudKit was half of it; a
    /// device backup would have carried the same file to iCloud anyway.
    ///
    /// Set on the store, its SQLite sidecars and Core Data's support folder
    /// beside it (external blobs land there) on EVERY launch, because SQLite
    /// deletes and recreates `-wal` and `-shm`, and a recreated file does not
    /// inherit the flag. A file that does not exist yet is skipped silently;
    /// the next launch catches it. Four attribute writes, cheap. `url` is
    /// the configuration's own, so this follows the store wherever SwiftData
    /// put it.
    static func excludeFromBackup(storeAt url: URL) {
        let support = url.deletingLastPathComponent()
            .appendingPathComponent("." + url.deletingPathExtension().lastPathComponent + "_SUPPORT").path
        for path in [url.path, url.path + "-wal", url.path + "-shm", support] {
            var file = URL(fileURLWithPath: path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? file.setResourceValues(values)
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
        // The rescue reads the main store's file, so it must be in place first.
        moveStoresOutOfAppGroupIfNeeded()
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
            breathDoorwayStartSec: s.breathDoorwayStartSec,
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
