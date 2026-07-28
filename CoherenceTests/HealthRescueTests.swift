import XCTest
import SwiftData

/// The one-time rescue of pre-split MeditationStats: before the 5.1.3 store
/// split, stats lived in the main store; the split remapped the entity to the
/// (empty) HealthLocal store, orphaning every pre-split row.
///
/// NOTE on fixtures: SwiftData's entity→store binding is process-global, so a
/// single-config "old layout" container cannot be built in this process (the
/// host app already runs the two-store layout). The fixture "old main file"
/// is therefore produced by writing stats through a split-shaped container —
/// what matters is that the file contains a MeditationStats table, which is
/// all the extractor reads.
final class HealthRescueTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appending(path: "rescue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func url(_ name: String) -> URL { dir.appending(path: name) }

    /// A production-shaped (two-store) container over the given files.
    private func splitContainer(main: URL, health: URL) throws -> ModelContainer {
        try ModelContainer(for: Persistence.schema, configurations: [
            ModelConfiguration(schema: Persistence.cloudSyncedSchema,
                               url: main, cloudKitDatabase: .none),
            ModelConfiguration("HealthLocal", schema: Persistence.healthLocalSchema,
                               url: health, cloudKitDatabase: .none),
        ])
    }

    /// Writes one stats row into `file` (playing the pre-split main store).
    @discardableResult
    private func seedStatsFile(_ file: URL) throws -> UUID {
        let sessionID = UUID()
        try autoreleasepool {
            let container = try splitContainer(main: url("seed-main.store"), health: file)
            let ctx = ModelContext(container)
            ctx.insert(MeditationStats(sessionID: sessionID, meanHR: 68,
                                       stillnessScore: 0.8, overallScore: 0.7))
            try ctx.save()
        }
        return sessionID
    }

    /// Full path: extract from the old file, insert into a fresh split store —
    /// the stats become visible to the app's normal fetch.
    func test_rescueMovesStatsIntoHealthStore() throws {
        let oldMain = url("old-main.store")
        let sessionID = try seedStatsFile(oldMain)

        let rescued = try XCTUnwrap(Persistence.extractOrphanedHealthStats(mainStoreURL: oldMain))
        XCTAssertEqual(rescued.count, 1)
        XCTAssertEqual(rescued.first?.sessionID, sessionID)

        let dest = try splitContainer(main: url("dest-main.store"), health: url("dest-health.store"))
        Persistence.insertRescuedHealthStats(rescued, into: dest)

        let ctx = ModelContext(dest)
        let visible = try ctx.fetch(FetchDescriptor<MeditationStats>())
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.sessionID, sessionID)
        XCTAssertEqual(visible.first?.overallScore, 0.7)
    }

    /// The scenario on a device that launched the split build BEFORE the
    /// rescue existed: the split layout has already opened the old main file
    /// (which migrates it to a schema without MeditationStats). The orphaned
    /// rows must still be extractable afterward — this pins down whether that
    /// migration destroys the old table's data.
    func test_orphanedStatsSurviveSplitOpen_thenRescue() throws {
        let oldMain = url("old-main.store")
        let sessionID = try seedStatsFile(oldMain)

        // A pre-rescue launch of the split build: the old file becomes the
        // MAIN (cloud-synced) store; stats are not part of that schema.
        try autoreleasepool {
            let container = try splitContainer(main: oldMain, health: url("fresh-health.store"))
            let ctx = ModelContext(container)
            XCTAssertEqual(try ctx.fetch(FetchDescriptor<MeditationStats>()).count, 0)
        }

        // A later launch with the rescue: are the rows still in the file?
        let rescued = try XCTUnwrap(Persistence.extractOrphanedHealthStats(mainStoreURL: oldMain))
        XCTAssertEqual(rescued.count, 1)
        XCTAssertEqual(rescued.first?.sessionID, sessionID)
    }

    /// Insert dedupes by sessionID, so a crash between extract and the done
    /// flag just retries safely next launch.
    func test_insertDedupesBySessionID() throws {
        let oldMain = url("old-main.store")
        let sessionID = try seedStatsFile(oldMain)
        let dest = try splitContainer(main: url("dest-main.store"), health: url("dest-health.store"))

        let rescued = try XCTUnwrap(Persistence.extractOrphanedHealthStats(mainStoreURL: oldMain))
        Persistence.insertRescuedHealthStats(rescued, into: dest)
        Persistence.insertRescuedHealthStats(rescued, into: dest)   // retry

        let ctx = ModelContext(dest)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MeditationStats>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MeditationStats>()).first?.sessionID, sessionID)
    }

    /// A missing main store (fresh install) extracts nothing and doesn't error.
    func test_missingStoreExtractsNothing() throws {
        let rescued = try XCTUnwrap(Persistence.extractOrphanedHealthStats(mainStoreURL: url("nope.store")))
        XCTAssertEqual(rescued.count, 0)
    }
}
