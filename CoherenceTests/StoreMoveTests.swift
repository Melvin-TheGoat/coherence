import XCTest

/// Moving a store out of the App Group's container (`Persistence.moveStore`,
/// Melvin, 2026-09-29, second pass of the pre-1.1 audit): all or nothing,
/// and a set-aside copy is never deleted.
final class StoreMoveTests: XCTestCase {

    private var root: URL!
    private var app: URL!
    private var group: URL!
    private let moment = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "store-move-\(UUID().uuidString)")
        app = root.appending(path: "app")
        group = root.appending(path: "group")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, in dir: URL, _ name: String) throws {
        try Data(text.utf8).write(to: dir.appending(path: name))
    }

    private func read(_ dir: URL, _ name: String) -> String? {
        (try? Data(contentsOf: dir.appending(path: name))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func names(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    private func setAside(_ dir: URL, _ prefix: String) -> [String] {
        names(dir).filter { $0.hasPrefix(prefix + ".before-group-move-") }
    }

    func test_everyPartMovesAndTheOldCopyIsSetAside() throws {
        try write("old store", in: app, "default.store")
        try write("old wal", in: app, "default.store-wal")
        try write("new store", in: group, "default.store")
        try write("new wal", in: group, "default.store-wal")
        try write("new shm", in: group, "default.store-shm")

        XCTAssertTrue(Persistence.moveStore("default", from: group, to: app, now: moment))

        XCTAssertEqual(read(app, "default.store"), "new store")
        XCTAssertEqual(read(app, "default.store-wal"), "new wal")
        XCTAssertEqual(read(app, "default.store-shm"), "new shm")
        XCTAssertEqual(names(group), [])
        let oldStore = try XCTUnwrap(setAside(app, "default.store").first)
        XCTAssertEqual(read(app, oldStore), "old store")
        let oldWal = try XCTUnwrap(setAside(app, "default.store-wal").first)
        XCTAssertEqual(read(app, oldWal), "old wal")
    }

    /// Two moves, even in the same second, keep both earlier copies. The
    /// first version removed the previous set-aside file to make room.
    func test_aSecondMoveNeverDeletesTheFirstSetAside() throws {
        try write("first", in: app, "default.store")
        try write("second", in: group, "default.store")
        XCTAssertTrue(Persistence.moveStore("default", from: group, to: app, now: moment))
        try write("third", in: group, "default.store")
        XCTAssertTrue(Persistence.moveStore("default", from: group, to: app, now: moment))

        XCTAssertEqual(read(app, "default.store"), "third")
        let kept = setAside(app, "default.store").compactMap { read(app, $0) }.sorted()
        XCTAssertEqual(kept, ["first", "second"], "every earlier copy survives")
    }

    /// A move that fails part way leaves both folders exactly as they were:
    /// never a store here with its log still in the group, never the app's
    /// old log beside a store it does not belong to.
    func test_aFailedMoveIsPutBackExactlyAsItWas() throws {
        try write("old store", in: app, "default.store")
        try write("old wal", in: app, "default.store-wal")
        try write("new store", in: group, "default.store")
        try write("new wal", in: group, "default.store-wal")
        let appBefore = names(app)
        let groupBefore = names(group)

        // Two set-asides, the group's store, then its log fails.
        var calls = 0
        let failOnFourth: (URL, URL) throws -> Void = { from, to in
            calls += 1
            if calls == 4 { throw CocoaError(.fileWriteUnknown) }
            try FileManager.default.moveItem(at: from, to: to)
        }
        XCTAssertFalse(Persistence.moveStore("default", from: group, to: app, now: moment, move: failOnFourth))

        XCTAssertEqual(names(app), appBefore)
        XCTAssertEqual(names(group), groupBefore)
        XCTAssertEqual(read(app, "default.store"), "old store")
        XCTAssertEqual(read(app, "default.store-wal"), "old wal")
        XCTAssertEqual(read(group, "default.store"), "new store")
        XCTAssertEqual(read(group, "default.store-wal"), "new wal")
    }

    /// The set-aside health copy stays out of iCloud Backup like the live
    /// store (5.1.3(ii)).
    func test_theSetAsideHealthCopyStaysOutOfBackup() throws {
        try write("old health", in: app, "HealthLocal.store")
        try write("new health", in: group, "HealthLocal.store")
        XCTAssertTrue(Persistence.moveStore("HealthLocal", from: group, to: app, now: moment))
        let aside = try XCTUnwrap(setAside(app, "HealthLocal.store").first)
        let values = try app.appending(path: aside).resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}
