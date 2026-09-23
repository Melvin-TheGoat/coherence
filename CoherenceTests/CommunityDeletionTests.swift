import XCTest
import CloudKit
@testable import Coherence

/// Deleting an 808 account must also delete what the person published to
/// Friends (App Review 5.1.1(v)): the local sign-out already happens
/// (`SessionStore.softDeleteCurrentUser`), but a profile, posts and
/// reactions left behind in the PUBLIC database would still be visible to
/// everyone else. Same two-store pattern as `CommunityStoreTests`.
final class CommunityDeletionTests: XCTestCase {

    private var db: MemoryCommunityDatabase!
    private var aziz: CommunityStore!
    private var melvin: CommunityStore!
    private let azizID = CommunityNames.profile(user: "_aziz")
    private let melvinID = CommunityNames.profile(user: "_melvin")

    override func setUp() async throws {
        db = MemoryCommunityDatabase(user: "_aziz")
        aziz = CommunityStore(database: db)
        db.user = "_melvin"
        melvin = CommunityStore(database: db)
        _ = try await melvin.me()
        db.user = "_aziz"
        _ = try await aziz.me()
    }

    private lazy var selfie: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("delete-test-selfie.jpg")
        try? Data([0xFF, 0xD8, 0xFF]).write(to: url)
        return url
    }()

    private func draft(score: Int = 70) -> CommunityStore.Draft {
        .init(score: score, minutes: 12, streak: 3, technique: "Counting", caption: "",
              photoURL: selfie, practicedAt: Date())
    }

    // MARK: The deleted person disappears

    func test_deletedProfileCanNoLongerBeFetchedOrSearched() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await aziz.deleteEverythingOfMine()

        let fetched = try await melvin.profile(named: azizID)
        XCTAssertNil(fetched, "another user must not be able to fetch the deleted profile")
        let found = try await melvin.search(username: "aziz")
        XCTAssertNil(found, "another user must not be able to search the deleted handle")
    }

    func test_theHandleBecomesClaimableAgain() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await aziz.deleteEverythingOfMine()

        db.user = "_lena"
        let lena = CommunityStore(database: db)
        _ = try await lena.me()
        let available = try await lena.isUsernameAvailable("aziz")
        XCTAssertTrue(available, "the freed handle must be claimable by somebody else")
        let claimed = try await lena.claimUsername("aziz", displayName: "Lena")
        XCTAssertEqual(claimed.username, "aziz")
    }

    func test_deletedPersonsPostsLeaveEveryFeed() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)

        let myPost = try await aziz.post(draft())
        let theirPost = try await melvin.post(draft(score: 81))
        let feedBefore = try await melvin.feed()
        XCTAssertEqual(feedBefore.count, 2)

        try await aziz.deleteEverythingOfMine()

        let feed = try await melvin.feed()
        XCTAssertEqual(feed.map(\.id), [theirPost.id], "the deleted person's post must be gone; their friend's own post must survive")
        XCTAssertNil(db.records[myPost.id])
    }

    func test_deletedPersonsReactionsDisappearFromOthersPosts() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        let post = try await melvin.post(draft(score: 55))
        try await aziz.react(to: post.id)
        var who = try await melvin.reactors(to: post.id)
        XCTAssertEqual(who, [azizID])

        try await aziz.deleteEverythingOfMine()

        who = try await melvin.reactors(to: post.id)
        XCTAssertEqual(who, [], "a reaction given by the deleted person must not still show on someone else's post")
    }

    // MARK: Nobody else's records move

    func test_theOtherPersonsOwnRecordsAreUntouched() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)
        let theirPost = try await melvin.post(draft(score: 64))

        let melvinRecordsBefore = db.records.values.filter { self.authoredByMelvinFixture($0) }.count
        try await aziz.deleteEverythingOfMine()

        XCTAssertNotNil(db.records[melvinID], "Melvin's own profile must survive Aziz deleting his account")
        XCTAssertNotNil(db.records[theirPost.id], "Melvin's own post must survive")
        XCTAssertEqual(db.records.values.filter { self.authoredByMelvinFixture($0) }.count, melvinRecordsBefore,
                       "nothing Melvin wrote should be removed by someone else's account deletion")
    }

    /// A record is "Melvin's" in this fixture if its creator field (`from`
    /// or `author`, whichever the type carries) is his profile — the same
    /// check `CommunityStore.authored` makes, done here from outside the
    /// actor to count records without a `me()` context of Melvin's own.
    private func authoredByMelvinFixture(_ record: CKRecord) -> Bool {
        for field in ["from", "author"] {
            if let ref = record[field] as? CKRecord.Reference, ref.recordID.recordName == melvinID { return true }
        }
        return record.recordID.recordName == melvinID
    }

    // MARK: Reports are moderation records, not the deleted person's to lose

    func test_reportsSurviveEitherDirection() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        let melvinsPost = try await melvin.post(draft(score: 40))
        // Aziz reported someone else, and someone else reported Aziz.
        let filedByAziz = try await aziz.report(melvinsPost.id, as: .post, reason: "spam")
        let filedAgainstAziz = try await melvin.report(azizID, as: .profile, reason: "spam")

        try await aziz.deleteEverythingOfMine()

        XCTAssertNotNil(db.records[filedByAziz.id], "a report Aziz filed must survive his own account deletion")
        XCTAssertNotNil(db.records[filedAgainstAziz.id], "a report filed against Aziz must survive too — moderation keeps it")
    }

    // MARK: Best effort

    func test_everyCategoryIsAttemptedEvenWhenOneFailsAndTheFailureSurfaces() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        let post = try await aziz.post(draft())
        try await aziz.block(melvinID)

        // The Block query fails; posts, which are queried first, must still
        // be attempted and removed.
        let failing = FailingQueryDatabase(inner: db, failing: CommunityType.block)
        let broken = CommunityStore(database: failing)
        _ = try await broken.me()   // resolves to "_aziz" via the wrapped fake

        do {
            try await broken.deleteEverythingOfMine()
            XCTFail("a category that fails to query must surface as a thrown error")
        } catch {
            // expected
        }

        XCTAssertNil(db.records[post.id], "a category that succeeded must not be rolled back by a later one failing")
        XCTAssertNotNil(db.records[CommunityNames.block(from: azizID, to: melvinID)],
                        "the category that failed to query is, correctly, still there")
    }
}

/// Fails querying one record type, so a test can prove account deletion
/// still attempts every other category and reports the failure. Same shape
/// as `CountingDatabase` / `RacingDatabase` in `CommunityStoreTests`.
private final class FailingQueryDatabase: CommunityDatabase {
    let inner: MemoryCommunityDatabase
    let failingType: String
    init(inner: MemoryCommunityDatabase, failing type: String) { self.inner = inner; self.failingType = type }
    func currentUserRecordName() async throws -> String { try await inner.currentUserRecordName() }
    func save(_ record: CKRecord) async throws -> CKRecord { try await inner.save(record) }
    func create(_ record: CKRecord) async throws -> CKRecord { try await inner.create(record) }
    func fetch(_ recordName: String) async throws -> CKRecord? { try await inner.fetch(recordName) }
    func query(_ query: CommunityQuery) async throws -> [CKRecord] {
        if query.type == failingType { throw CommunityError.unavailable }
        return try await inner.query(query)
    }
    func delete(_ recordName: String) async throws { try await inner.delete(recordName) }
}

/// Every call throws except identity, so `CommunityModel.deleteAccountData`
/// can be proven to set its pending flag on a genuinely failed run.
private final class AlwaysFailingCommunityDatabase: CommunityDatabase {
    let user: String
    init(user: String) { self.user = user }
    func currentUserRecordName() async throws -> String { user }
    func save(_ record: CKRecord) async throws -> CKRecord { throw CommunityError.unavailable }
    func create(_ record: CKRecord) async throws -> CKRecord { throw CommunityError.unavailable }
    func fetch(_ recordName: String) async throws -> CKRecord? { throw CommunityError.unavailable }
    func query(_ query: CommunityQuery) async throws -> [CKRecord] { throw CommunityError.unavailable }
    func delete(_ recordName: String) async throws { throw CommunityError.unavailable }
}

/// `CommunityModel.deleteAccountData`'s pending-flag mechanism: a failed
/// attempt has to leave a mark that survives the method returning, since
/// nothing else is watching for the failure once the delete-account sheet
/// has already dismissed.
@MainActor
final class AccountDeletionPendingFlagTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CommunityModel.pendingDeletionKey)
    }

    func test_aFailedDeletionSetsThePendingFlagAndAHealthyRetryClearsIt() async throws {
        let failingModel = CommunityModel(store: CommunityStore(database: AlwaysFailingCommunityDatabase(user: "_pending")))
        await failingModel.deleteAccountData()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: CommunityModel.pendingDeletionKey),
                      "a run that could not finish must leave something to retry")

        let workingDB = MemoryCommunityDatabase(user: "_pending")
        let healthyModel = CommunityModel(store: CommunityStore(database: workingDB))
        await healthyModel.deleteAccountData()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: CommunityModel.pendingDeletionKey),
                       "a run that finishes clean must clear the flag")
    }

    func test_aSuccessfulDeletionNeverSetsThePendingFlag() async throws {
        let db = MemoryCommunityDatabase(user: "_ok")
        let model = CommunityModel(store: CommunityStore(database: db))
        await model.deleteAccountData()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: CommunityModel.pendingDeletionKey))
    }
}
