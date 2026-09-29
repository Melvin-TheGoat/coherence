import XCTest
import CloudKit
@testable import Coherence

/// Leaving Friends (Melvin, 2026-09-29, second pass of the pre-1.1 audit).
/// Sign-out and Delete account used to leave the whole profile in memory:
/// Friends and Profile kept showing the deleted @username, onboarding's
/// profile step opened on it in Edit mode, practice stats kept publishing to
/// it (and could put back a profile record a deletion was taking down), and
/// the next person on the phone found the community rules already agreed.
@MainActor
final class CommunityResetTests: XCTestCase {

    private let keys = [CommunityModel.pendingDeletionKey, CommunityModel.publishingPausedKey,
                        CreateProfileView.rulesAcceptedKey, FriendsIntroView.shownKey]

    override func setUp() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private let meID = CommunityNames.profile(user: "_me")

    /// A model with a claimed profile and one session to publish.
    private func readyModel(_ db: CommunityDatabase) async -> CommunityModel {
        let model = CommunityModel(store: CommunityStore(database: db))
        model.allSessions = { [(startedAt: Date(), durationSec: 600)] }
        await model.load()
        _ = await model.claim("melvin", displayName: "Melvin")
        UserDefaults.standard.set(Date(), forKey: CreateProfileView.rulesAcceptedKey)
        UserDefaults.standard.set(true, forKey: FriendsIntroView.shownKey)
        return model
    }

    func test_deletingTheAccountForgetsTheProfileAtOnce() async throws {
        let db = MemoryCommunityDatabase(user: "_me")
        let model = await readyModel(db)
        XCTAssertTrue(model.hasProfile)

        await model.deleteAccountData()

        XCTAssertNil(model.profile)
        XCTAssertFalse(model.hasProfile)
        XCTAssertNotEqual(model.phase, .ready, "Friends must not go on showing the deleted handle")
        XCTAssertTrue(model.friends.isEmpty)
        XCTAssertNil(UserDefaults.standard.object(forKey: CreateProfileView.rulesAcceptedKey),
                     "the next person on this phone agrees to the rules for themselves")
        XCTAssertNil(UserDefaults.standard.object(forKey: FriendsIntroView.shownKey))
        XCTAssertNil(db.records[meID], "the public profile is gone")
    }

    func test_signingOutForgetsTheProfileAndStopsPublishing() async throws {
        let db = MemoryCommunityDatabase(user: "_me")
        let model = await readyModel(db)

        model.signedOut()

        XCTAssertNil(model.profile)
        XCTAssertEqual(model.phase, .loading)
        XCTAssertNil(UserDefaults.standard.object(forKey: CreateProfileView.rulesAcceptedKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: FriendsIntroView.shownKey))

        // The profile still exists in iCloud, so a later load finds it again,
        // and a later launch (a fresh model) too. Neither publishes to it.
        for reader in [model, CommunityModel(store: CommunityStore(database: db))] {
            reader.allSessions = { [(startedAt: Date(), durationSec: 900)] }
            await reader.load()
            XCTAssertTrue(reader.hasProfile)
            await reader.syncPracticeStats(force: true)
            XCTAssertNil(db.records[meID]?["totalSessions"], "nothing is published for someone who signed out")
        }
    }

    func test_keepingTheProfileOrClaimingOneResumesPublishing() async throws {
        let db = MemoryCommunityDatabase(user: "_me")
        let model = await readyModel(db)
        model.signedOut()
        await model.load()

        model.resumePublishing()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: CommunityModel.publishingPausedKey))
        await model.syncPracticeStats(force: true)
        XCTAssertNotNil(db.records[meID]?["totalSessions"], "taking the profile back up publishes again")

        model.signedOut()
        await model.load()
        _ = await model.claim("melvin", displayName: "Melvin")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: CommunityModel.publishingPausedKey),
                       "saving a profile is taking it up too")
    }

    /// A deletion that could not finish must never be undone by the next
    /// load: the profile stays out of sight, nothing publishes to it, and the
    /// flag stays set to be retried.
    func test_anUnfinishedDeletionIsNeverShownOrPublishedTo() async throws {
        let inner = MemoryCommunityDatabase(user: "_me")
        _ = await readyModel(inner)
        let stuck = CommunityModel(store: CommunityStore(database: UndeletableDatabase(inner: inner)))
        stuck.allSessions = { [(startedAt: Date(), durationSec: 600)] }

        await stuck.deleteAccountData()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: CommunityModel.pendingDeletionKey))
        XCTAssertNotNil(inner.records[meID], "fixture: the profile record could not be deleted")

        await stuck.load()
        XCTAssertNil(stuck.profile)
        XCTAssertEqual(stuck.phase, .needsUsername)
        await stuck.syncPracticeStats(force: true)
        XCTAssertNil(inner.records[meID]?["totalSessions"])
        XCTAssertTrue(UserDefaults.standard.bool(forKey: CommunityModel.pendingDeletionKey))

        // Once the database lets it through, the next load finishes the job.
        let healthy = CommunityModel(store: CommunityStore(database: inner))
        await healthy.load()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: CommunityModel.pendingDeletionKey))
        XCTAssertNil(inner.records[meID])
        XCTAssertEqual(healthy.phase, .needsUsername)
    }

    // MARK: Post and Reaction are retired types

    /// A Production container without the Post or Reaction index answers
    /// every query of them with an error. That must not keep a deletion
    /// pending forever: nothing was ever written to a type nobody can query.
    func test_aMissingIndexOnARetiredTypeDoesNotHoldUpDeletion() async throws {
        let inner = MemoryCommunityDatabase(user: "_me")
        let store = CommunityStore(database: inner)
        try await store.claimUsername("melvin", displayName: "Melvin")
        try await store.block(CommunityNames.profile(user: "_other"))

        let broken = CommunityStore(database: RefusingQueryDatabase(
            inner: inner, refusing: [CommunityType.post, CommunityType.reaction],
            error: CKError(.invalidArguments)))
        try await broken.deleteEverythingOfMine()

        XCTAssertNil(inner.records[meID])
        XCTAssertFalse(inner.records.values.contains { $0.recordType == CommunityType.block },
                       "my block went with the rest")
    }

    /// No network is still worth retrying, even on a retired type.
    func test_noNetworkOnARetiredTypeStillFailsTheDeletion() async throws {
        let inner = MemoryCommunityDatabase(user: "_me")
        let store = CommunityStore(database: inner)
        try await store.claimUsername("melvin", displayName: "Melvin")
        let offline = CommunityStore(database: RefusingQueryDatabase(
            inner: inner, refusing: [CommunityType.post], error: CKError(.networkUnavailable)))
        do {
            try await offline.deleteEverythingOfMine()
            XCTFail("a transient failure must leave the deletion to retry")
        } catch {}
    }

    /// The live types still fail the deletion on any error.
    func test_aMissingIndexOnALiveTypeStillFailsTheDeletion() async throws {
        let inner = MemoryCommunityDatabase(user: "_me")
        let broken = CommunityStore(database: RefusingQueryDatabase(
            inner: inner, refusing: [CommunityType.edge], error: CKError(.invalidArguments)))
        do {
            try await broken.deleteEverythingOfMine()
            XCTFail("friend edges that cannot be queried may still exist")
        } catch {}
    }

    /// The one-time post cleanup finishes too, instead of retrying at every
    /// launch against a type that cannot be queried.
    func test_postCleanupFinishesWhenThePostTypeCannotBeQueried() async throws {
        UserDefaults.standard.removeObject(forKey: CommunityModel.postsClearedKey)
        defer { UserDefaults.standard.removeObject(forKey: CommunityModel.postsClearedKey) }
        let model = CommunityModel(store: CommunityStore(database: RefusingQueryDatabase(
            inner: MemoryCommunityDatabase(user: "_me"), refusing: [CommunityType.post],
            error: CKError(.invalidArguments))))
        await model.clearMyPostsIfNeeded()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: CommunityModel.postsClearedKey))
    }
}

/// Everything works except deleting, so a deletion can be left unfinished
/// with the profile record still there.
private final class UndeletableDatabase: CommunityDatabase {
    let inner: MemoryCommunityDatabase
    init(inner: MemoryCommunityDatabase) { self.inner = inner }
    func currentUserRecordName() async throws -> String { try await inner.currentUserRecordName() }
    func save(_ record: CKRecord) async throws -> CKRecord { try await inner.save(record) }
    func create(_ record: CKRecord) async throws -> CKRecord { try await inner.create(record) }
    func fetch(_ recordName: String) async throws -> CKRecord? { try await inner.fetch(recordName) }
    func query(_ query: CommunityQuery) async throws -> [CKRecord] { try await inner.query(query) }
    func delete(_ recordName: String) async throws { throw CKError(.networkFailure) }
}

/// Refuses queries of some record types with a given error, the way a
/// Production container missing an index does.
private final class RefusingQueryDatabase: CommunityDatabase {
    let inner: MemoryCommunityDatabase
    let refusing: Set<String>
    let error: Error
    init(inner: MemoryCommunityDatabase, refusing: Set<String>, error: Error) {
        self.inner = inner; self.refusing = refusing; self.error = error
    }
    func currentUserRecordName() async throws -> String { try await inner.currentUserRecordName() }
    func save(_ record: CKRecord) async throws -> CKRecord { try await inner.save(record) }
    func create(_ record: CKRecord) async throws -> CKRecord { try await inner.create(record) }
    func fetch(_ recordName: String) async throws -> CKRecord? { try await inner.fetch(recordName) }
    func query(_ query: CommunityQuery) async throws -> [CKRecord] {
        if refusing.contains(query.type) { throw error }
        return try await inner.query(query)
    }
    func delete(_ recordName: String) async throws { try await inner.delete(recordName) }
}
