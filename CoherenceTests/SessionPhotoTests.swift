import XCTest
import SwiftData
@testable import Coherence

/// The photo kept with a session (Aziz, 2026-09-15: a picture after every
/// sit, private ones too, shown on the calendar). One row per session,
/// replaced in place on a retake, gone with the session and with the account.
@MainActor
final class SessionPhotoTests: XCTestCase {

    // The container is held: a ModelContext does not retain it in tests.
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() {
        super.setUp()
        container = Persistence.inMemory()
        ctx = ModelContext(container)
    }

    override func tearDown() {
        ctx = nil
        container = nil
        super.tearDown()
    }

    private func makeSession(userID: UUID? = nil, startedAt: Date = Date()) -> UUID {
        let s = Session(id: UUID())
        s.userID = userID
        s.startedAt = startedAt
        s.durationSec = 600
        ctx.insert(s)
        try? ctx.save()
        return s.id
    }

    private func photoCount() -> Int {
        ((try? ctx.fetch(FetchDescriptor<SessionPhoto>())) ?? []).count
    }

    func test_noPhotoByDefault() {
        let sid = makeSession()
        XCTAssertNil(SessionStore.photo(for: sid, in: ctx))
    }

    func test_savedPhotoIsReadBackWithBothSizes() {
        let sid = makeSession()
        SessionStore.savePhoto(sessionID: sid, jpeg: Data([1, 2, 3]), thumbnail: Data([9]), in: ctx)
        let row = SessionStore.photo(for: sid, in: ctx)
        XCTAssertEqual(row?.jpeg, Data([1, 2, 3]))
        XCTAssertEqual(row?.thumbnail, Data([9]))
        XCTAssertEqual(row?.sessionID, sid)
    }

    /// A retake replaces in place. A session never carries two pictures.
    func test_retakeReplacesInPlace() {
        let sid = makeSession()
        let first = SessionStore.savePhoto(sessionID: sid, jpeg: Data([1]), thumbnail: Data([1]), in: ctx)
        let second = SessionStore.savePhoto(sessionID: sid, jpeg: Data([2]), thumbnail: Data([2]), in: ctx)
        XCTAssertEqual(first.id, second.id, "the same row, not a second one")
        XCTAssertEqual(photoCount(), 1)
        XCTAssertEqual(SessionStore.photo(for: sid, in: ctx)?.jpeg, Data([2]))
    }

    func test_photosAreKeyedBySession() {
        let a = makeSession(), b = makeSession()
        SessionStore.savePhoto(sessionID: a, jpeg: Data([0xA]), thumbnail: Data([0xA]), in: ctx)
        SessionStore.savePhoto(sessionID: b, jpeg: Data([0xB]), thumbnail: Data([0xB]), in: ctx)
        XCTAssertEqual(SessionStore.photo(for: a, in: ctx)?.jpeg, Data([0xA]))
        XCTAssertEqual(SessionStore.photo(for: b, in: ctx)?.jpeg, Data([0xB]))
        XCTAssertEqual(photoCount(), 2)
    }

    func test_removePhotoLeavesTheSession() {
        let sid = makeSession()
        SessionStore.savePhoto(sessionID: sid, jpeg: Data([1]), thumbnail: Data([1]), in: ctx)
        SessionStore.removePhoto(for: sid, in: ctx)
        XCTAssertNil(SessionStore.photo(for: sid, in: ctx))
        let sessions = (try? ctx.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertEqual(sessions.count, 1, "removing a photo never touches the session")
    }

    /// Deleting a session takes its photo with it, like its stats and its
    /// reflection. An orphaned picture would still show on the calendar for
    /// a day with no sit.
    func test_deleteSessionRemovesItsPhoto() {
        let keep = makeSession(), gone = makeSession()
        SessionStore.savePhoto(sessionID: keep, jpeg: Data([1]), thumbnail: Data([1]), in: ctx)
        SessionStore.savePhoto(sessionID: gone, jpeg: Data([2]), thumbnail: Data([2]), in: ctx)
        XCTAssertTrue(SessionStore.deleteSession(id: gone, in: ctx))
        XCTAssertNil(SessionStore.photo(for: gone, in: ctx))
        XCTAssertNotNil(SessionStore.photo(for: keep, in: ctx))
        XCTAssertEqual(photoCount(), 1)
    }

    /// Account deletion: the 30-day purge removes an expired user's photos
    /// with the rest of their rows. A face left behind after "delete my
    /// account" would be the worst thing this feature could do.
    func test_purgeRemovesAnExpiredUsersPhotos() {
        let user = SessionStore.currentUser(in: ctx)
        let mine = makeSession(userID: user.id)
        SessionStore.savePhoto(sessionID: mine, jpeg: Data([1]), thumbnail: Data([1]), in: ctx)

        let longAgo = Calendar.current.date(byAdding: .day, value: -45, to: Date())!
        SessionStore.softDeleteCurrentUser(now: longAgo, in: ctx)
        SessionStore.purgeExpired(in: ctx)

        XCTAssertEqual(photoCount(), 0)
        XCTAssertNil(SessionStore.photo(for: mine, in: ctx))
    }

    /// The photo model rides the synced store, deliberately: a photo is not
    /// health data, so it may survive a new phone with the sessions and die
    /// with the account. Locks the schema membership so it cannot drift into
    /// the health-local store by accident.
    func test_photoIsInTheSyncedSchemaAndNotTheHealthOne() {
        let synced = Persistence.cloudSyncedSchema.entities.map(\.name)
        let health = Persistence.healthLocalSchema.entities.map(\.name)
        XCTAssertTrue(synced.contains("SessionPhoto"))
        XCTAssertFalse(health.contains("SessionPhoto"))
    }

    // MARK: - Several photos (Melvin, 2026-09-23: "share multiple photos or videos")

    /// `addPhoto` appends, unlike `savePhoto`'s replace-in-place: a session
    /// can keep several, each its own row, in the order they were added.
    func test_addPhotoAppendsInOrder() {
        let sid = makeSession()
        let a = SessionStore.addPhoto(sessionID: sid, jpeg: Data([1]), thumbnail: Data([1]), in: ctx)
        let b = SessionStore.addPhoto(sessionID: sid, jpeg: Data([2]), thumbnail: Data([2]), in: ctx)
        let c = SessionStore.addPhoto(sessionID: sid, jpeg: Data([3]), thumbnail: Data([3]), in: ctx)
        XCTAssertEqual(photoCount(), 3, "three separate rows, not one replaced in place")
        let ordered = SessionStore.photos(for: sid, in: ctx)
        XCTAssertEqual(ordered.map(\.jpeg), [Data([1]), Data([2]), Data([3])])
        XCTAssertEqual(ordered.map(\.id), [a?.id, b?.id, c?.id].compactMap { $0 })
    }

    /// `photo(for:)` (the calendar dot, `EvidenceRow`, the results screen)
    /// still answers with ONE item: the first, by order.
    func test_photoForSessionIsStillTheFirstByOrder() {
        let sid = makeSession()
        SessionStore.addPhoto(sessionID: sid, jpeg: Data([1]), thumbnail: Data([1]), in: ctx)
        SessionStore.addPhoto(sessionID: sid, jpeg: Data([2]), thumbnail: Data([2]), in: ctx)
        XCTAssertEqual(SessionStore.photo(for: sid, in: ctx)?.jpeg, Data([1]))
    }

    func test_removingOneItemLeavesTheRestInPlace() {
        let sid = makeSession()
        let a = SessionStore.addPhoto(sessionID: sid, jpeg: Data([1]), thumbnail: Data([1]), in: ctx)!
        let b = SessionStore.addPhoto(sessionID: sid, jpeg: Data([2]), thumbnail: Data([2]), in: ctx)!
        let c = SessionStore.addPhoto(sessionID: sid, jpeg: Data([3]), thumbnail: Data([3]), in: ctx)!
        SessionStore.removePhotoItem(id: b.id, in: ctx)
        XCTAssertEqual(SessionStore.photos(for: sid, in: ctx).map(\.id), [a.id, c.id])
    }

    func test_addPhotoRefusesPastTheCap() {
        let sid = makeSession()
        for i in 0..<SessionStore.maxPhotosPerSession {
            XCTAssertNotNil(SessionStore.addPhoto(sessionID: sid, jpeg: Data([UInt8(i)]), thumbnail: Data([UInt8(i)]), in: ctx))
        }
        XCTAssertNil(SessionStore.addPhoto(sessionID: sid, jpeg: Data([99]), thumbnail: Data([99]), in: ctx),
                     "the 11th item is refused, not silently dropped or wrapped around")
        XCTAssertEqual(photoCount(), SessionStore.maxPhotosPerSession)
    }

    /// Deleting a session takes EVERY one of its photos with it, not just the
    /// first, exactly as it already did for stats and reflection.
    func test_deleteSessionRemovesEveryPhoto() {
        let keep = makeSession(), gone = makeSession()
        SessionStore.addPhoto(sessionID: gone, jpeg: Data([1]), thumbnail: Data([1]), in: ctx)
        SessionStore.addPhoto(sessionID: gone, jpeg: Data([2]), thumbnail: Data([2]), in: ctx)
        SessionStore.addPhoto(sessionID: gone, jpeg: Data([3]), thumbnail: Data([3]), in: ctx)
        SessionStore.addPhoto(sessionID: keep, jpeg: Data([9]), thumbnail: Data([9]), in: ctx)
        XCTAssertTrue(SessionStore.deleteSession(id: gone, in: ctx))
        XCTAssertTrue(SessionStore.photos(for: gone, in: ctx).isEmpty)
        XCTAssertEqual(SessionStore.photos(for: keep, in: ctx).count, 1)
        XCTAssertEqual(photoCount(), 1)
    }

    /// Account deletion purges every one of an expired user's photos, not
    /// just the first.
    func test_purgeRemovesEveryPhotoOfAnExpiredUser() {
        let user = SessionStore.currentUser(in: ctx)
        let mine = makeSession(userID: user.id)
        SessionStore.addPhoto(sessionID: mine, jpeg: Data([1]), thumbnail: Data([1]), in: ctx)
        SessionStore.addPhoto(sessionID: mine, jpeg: Data([2]), thumbnail: Data([2]), in: ctx)
        SessionStore.addPhoto(sessionID: mine, jpeg: Data([3]), thumbnail: Data([3]), in: ctx)

        let longAgo = Calendar.current.date(byAdding: .day, value: -45, to: Date())!
        SessionStore.softDeleteCurrentUser(now: longAgo, in: ctx)
        SessionStore.purgeExpired(in: ctx)

        XCTAssertEqual(photoCount(), 0)
    }
}
