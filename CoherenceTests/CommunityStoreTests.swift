import XCTest
import CloudKit
@testable import Coherence

final class CommunityStoreTests: XCTestCase {

    private var db: MemoryCommunityDatabase!
    private var aziz: CommunityStore!
    private var melvin: CommunityStore!
    private let azizID = CommunityNames.profile(user: "_aziz")
    private let melvinID = CommunityNames.profile(user: "_melvin")

    override func setUp() async throws {
        db = MemoryCommunityDatabase(user: "_aziz")
        aziz = CommunityStore(database: db)
        // A second store over the SAME database, acting as Melvin. The fake's
        // `user` is read once per store (cached), so each store keeps its
        // identity after the switch.
        db.user = "_melvin"
        melvin = CommunityStore(database: db)
        _ = try await melvin.me()
        db.user = "_aziz"
        _ = try await aziz.me()
    }

    // MARK: Usernames

    func test_claimCreatesProfileAndSecondClaimIsRefused() async throws {
        let p = try await aziz.claimUsername("@Aziz", displayName: "Aziz")
        XCTAssertEqual(p.username, "aziz", "normalised: lowercase, no @")
        XCTAssertEqual(p.id, azizID)

        do {
            try await melvin.claimUsername("aziz", displayName: "Melvin")
            XCTFail("a taken handle must be refused")
        } catch let e as CommunityError {
            XCTAssertEqual(e, .usernameTaken)
        }
        let mine = try await aziz.myProfile()
        XCTAssertEqual(mine?.username, "aziz", "the loser's attempt must not disturb the holder")
    }

    func test_reclaimingMyOwnHandleIsNotTaken() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        let ok = try await aziz.isUsernameAvailable("aziz")
        XCTAssertTrue(ok)
        let again = try await aziz.claimUsername("aziz", displayName: "Aziz M")
        XCTAssertEqual(again.displayName, "Aziz M", "re-claim edits the profile in place")
        XCTAssertEqual(db.records.values.filter { $0.recordType == CommunityType.profile }.count, 1)
        XCTAssertEqual(db.records.values.filter { $0.recordType == CommunityType.username }.count, 1)
    }

    /// The reservation is fetched by name, never queried: a fresh CloudKit
    /// container has no record types and no indexes, and a query-based check
    /// silently failed on a real phone (2026-09-14).
    func test_claimNeverQueries() async throws {
        let counting = CountingDatabase(inner: db)
        let store = CommunityStore(database: counting)
        _ = try await store.me()
        try await store.claimUsername("aziz", displayName: "Aziz")
        let ok = try await store.isUsernameAvailable("aziz")
        XCTAssertTrue(ok)
        _ = try await store.search(username: "aziz")
        XCTAssertEqual(counting.queries, 0)
    }

    func test_changingHandleReleasesTheOldOne() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await aziz.claimUsername("aziz_m", displayName: "Aziz")
        let free = try await melvin.isUsernameAvailable("aziz")
        XCTAssertTrue(free, "the old handle is released")
        let found = try await melvin.search(username: "aziz")
        XCTAssertNil(found)
        let now = try await melvin.search(username: "aziz_m")
        XCTAssertEqual(now?.id, azizID)
    }

    func test_simultaneousClaimLosesToTheServer() async throws {
        // Melvin's reservation lands between Aziz's check and Aziz's create.
        let r = CKRecord(recordType: CommunityType.username, recordID: CKRecord.ID(recordName: CommunityNames.username("zen")))
        r["profile"] = CommunityRecordValue.reference(melvinID).ckValue
        let racing = RacingDatabase(inner: db, injectBeforeCreate: r)
        let store = CommunityStore(database: racing)
        _ = try await store.me()
        do {
            try await store.claimUsername("zen", displayName: "Aziz")
            XCTFail("the server's existing reservation must win")
        } catch let e as CommunityError {
            XCTAssertEqual(e, .usernameTaken)
        }
    }

    func test_emptyHandleIsInvalid() async throws {
        do {
            try await aziz.claimUsername("@@", displayName: "x")
            XCTFail()
        } catch let e as CommunityError {
            XCTAssertEqual(e, .usernameInvalid)
        }
    }

    func test_searchFindsByHandle() async throws {
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        let found = try await aziz.search(username: "@Melvin")
        XCTAssertEqual(found?.id, melvinID)
        let missing = try await aziz.search(username: "nobody")
        XCTAssertNil(missing)
    }

    // MARK: Friendship is two edges

    func test_requestThenAcceptMakesFriends() async throws {
        try await aziz.sendRequest(to: melvinID)
        var rel = try await aziz.relationship(with: melvinID)
        XCTAssertEqual(rel, .requested)
        rel = try await melvin.relationship(with: azizID)
        XCTAssertEqual(rel, .incoming)
        let incoming = try await melvin.incomingRequests()
        XCTAssertEqual(incoming, [azizID])
        let sent = try await aziz.sentRequests()
        XCTAssertEqual(sent, [melvinID])
        var friends = try await aziz.friends()
        XCTAssertEqual(friends, [], "one edge is a request, not a friendship")

        try await melvin.accept(azizID)
        friends = try await aziz.friends()
        XCTAssertEqual(friends, [melvinID])
        friends = try await melvin.friends()
        XCTAssertEqual(friends, [azizID])
        let pending = try await melvin.incomingRequests()
        XCTAssertEqual(pending, [])
    }

    func test_resendingARequestDoesNotDuplicate() async throws {
        try await aziz.sendRequest(to: melvinID)
        try await aziz.sendRequest(to: melvinID)
        XCTAssertEqual(db.records.values.filter { $0.recordType == CommunityType.edge }.count, 1)
    }

    func test_removeDeletesOnlyMyEdge() async throws {
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)
        try await aziz.removeFriend(melvinID)
        let mine = try await aziz.friends()
        XCTAssertEqual(mine, [])
        let rel = try await melvin.relationship(with: azizID)
        XCTAssertEqual(rel, .requested, "Melvin's edge is his to keep; from his side it is now a pending request")
    }

    func test_cannotFriendMyself() async throws {
        try await aziz.sendRequest(to: azizID)
        XCTAssertTrue(db.records.isEmpty)
    }

    // MARK: Posts and the feed

    private func draft(score: Int = 77, caption: String = "") -> CommunityStore.Draft {
        .init(score: score, minutes: 18, streak: 4, technique: "Counting", caption: caption,
              photoURL: nil, practicedAt: Date())
    }

    func test_postCarriesOnlyTheFreeCardFields() async throws {
        let post = try await aziz.post(draft(caption: "Roof before work."))
        let record = try XCTUnwrap(db.records[post.id])
        XCTAssertEqual(Set(record.allKeys()), Set(Post.fields).subtracting(["photo", "sound"]),
                       "a post carries the free share card's data and nothing measured: no heart, breath or stillness values, no curves (5.1.3 and the free tier)")
        for banned in ["heart", "hr", "breath", "stillness", "curve", "bpm"] {
            XCTAssertFalse(Post.fields.contains { $0.lowercased().contains(banned) }, banned)
        }
    }

    func test_savingASessionAgainUpdatesItsPostAndUnpostRemovesIt() async throws {
        var d = draft(caption: "first")
        d.sessionID = "S1"; d.title = "Evening meditation"; d.sound = "Rain"
        let first = try await aziz.post(d)
        d.caption = "edited"
        let second = try await aziz.post(d)
        XCTAssertEqual(first.id, second.id, "one post per session")
        XCTAssertEqual(db.records.values.filter { $0.recordType == CommunityType.post }.count, 1)
        XCTAssertEqual(second.caption, "edited")
        XCTAssertEqual(second.title, "Evening meditation")
        XCTAssertEqual(second.sound, "Rain")
        XCTAssertEqual(second.createdAt, first.createdAt, "an edit keeps its place in the feed")

        try await aziz.unpost(session: "S1")
        XCTAssertTrue(db.records.values.filter { $0.recordType == CommunityType.post }.isEmpty)
        try await aziz.unpost(session: "S1")   // already gone: no throw
    }

    func test_avatarIsSetAndCleared() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-test.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: file)
        var p = try await aziz.setAvatar(file)
        XCTAssertEqual(p.avatarURL, file)
        p = try await aziz.claimUsername("aziz", displayName: "Aziz M")
        XCTAssertEqual(p.avatarURL, file, "renaming never drops the photo")
        p = try await aziz.setAvatar(nil)
        XCTAssertNil(p.avatarURL)
    }

    func test_captionIsTrimmedAndClipped() async throws {
        let long = String(repeating: "a", count: 300)
        let post = try await aziz.post(draft(caption: "  " + long + "  "))
        XCTAssertEqual(post.caption.count, CommunityStore.captionLimit)
    }

    func test_feedIsFriendsAndMeNewestFirst() async throws {
        let stranger = CommunityStore(database: db)
        db.user = "_stranger"; _ = try await stranger.me(); db.user = "_aziz"

        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)

        var old = draft(score: 60); old.practicedAt = Date().addingTimeInterval(-3_600)
        let mine = try await aziz.post(old)
        let theirs = try await melvin.post(draft(score: 81))
        try await stranger.post(draft(score: 99))

        let feed = try await aziz.feed()
        XCTAssertEqual(feed.map(\.id), [theirs.id, mine.id], "most recently practiced first; the stranger's post is not in my feed")
    }

    func test_strangersPostsAreNotReadable() async throws {
        try await melvin.post(draft())
        let seen = try await aziz.posts(by: melvinID)
        XCTAssertEqual(seen, [], "a profile shows posts only to friends")
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)
        let now = try await aziz.posts(by: melvinID)
        XCTAssertEqual(now.count, 1)
    }

    // MARK: Reactions

    func test_oneReactionPerPersonPerPost() async throws {
        let post = try await melvin.post(draft())
        try await aziz.react(to: post.id)
        try await aziz.react(to: post.id)
        var who = try await melvin.reactors(to: post.id)
        XCTAssertEqual(who, [azizID])
        try await aziz.unreact(to: post.id)
        who = try await melvin.reactors(to: post.id)
        XCTAssertEqual(who, [])
    }

    // MARK: Blocks

    func test_blockEndsFriendshipAndHidesBothWays() async throws {
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)

        try await aziz.block(melvinID)

        let mine = try await aziz.friends()
        XCTAssertEqual(mine, [])
        let his = try await melvin.friends()
        XCTAssertEqual(his, [], "a block removes the friendship from BOTH views, even though Melvin's edge still exists")
        let seenByMelvin = try await melvin.search(username: "aziz")
        XCTAssertNil(seenByMelvin, "the blocked person cannot find the blocker")
        let seenByAziz = try await aziz.profile(named: melvinID)
        XCTAssertNil(seenByAziz, "and the blocker no longer sees them")

        do {
            try await melvin.sendRequest(to: azizID)
            XCTFail("a request across a block must be refused")
        } catch let e as CommunityError {
            XCTAssertEqual(e, .blocked)
        }
        let blocked = try await aziz.blockedByMe()
        XCTAssertEqual(blocked, [melvinID])

        try await aziz.unblock(melvinID)
        let after = try await melvin.search(username: "aziz")
        XCTAssertEqual(after?.id, azizID)
    }

    func test_blockedPersonsPostsLeaveTheFeed() async throws {
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)
        try await melvin.post(draft())
        var feed = try await aziz.feed()
        XCTAssertEqual(feed.count, 1)
        try await melvin.block(azizID)
        feed = try await aziz.feed()
        XCTAssertEqual(feed, [], "being blocked also drops their posts from my feed")
    }

    // MARK: Reports and first session

    func test_reportIsWrittenWithReporterAndTarget() async throws {
        let post = try await melvin.post(draft())
        let r = try await aziz.report(post.id, as: .post, reason: "not a meditation")
        let record = try XCTUnwrap(db.records[r.id])
        XCTAssertEqual(record.recordType, CommunityType.report)
        XCTAssertEqual((record["reporter"] as? CKRecord.Reference)?.recordID.recordName, azizID)
        XCTAssertEqual(record["target"] as? String, post.id)
        XCTAssertEqual(record["targetType"] as? String, "post")
    }

    func test_firstSessionIsRecordedOnce() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        let first = Date(timeIntervalSince1970: 1_000)
        try await aziz.markFirstSession(at: first)
        try await aziz.markFirstSession(at: Date())
        let p = try await aziz.myProfile()
        XCTAssertEqual(p?.firstSessionAt, first)
    }

    func test_firstSessionBeforeProfileIsANoOp() async throws {
        try await aziz.markFirstSession()
        XCTAssertTrue(db.records.isEmpty)
    }

    // MARK: The query description round-trips to a CloudKit predicate

    func test_queryBuildsAPredicateCloudKitAccepts() {
        var q = CommunityQuery(type: CommunityType.post,
                               filters: [.isIn("author", [.reference("profile-a"), .reference("profile-b")]),
                                         .equals("caption", .string("x"))])
        q.sortField = "createdAt"
        let ck = q.ckQuery
        XCTAssertEqual(ck.recordType, "Post")
        XCTAssertEqual(ck.sortDescriptors?.first?.key, "createdAt")
        XCTAssertTrue(ck.predicate.predicateFormat.contains("author IN"))
        XCTAssertTrue(ck.predicate.predicateFormat.contains("caption == \"x\""))
    }
}


/// Counts queries so a test can assert a path never needs an index.
private final class CountingDatabase: CommunityDatabase {
    let inner: MemoryCommunityDatabase
    var queries = 0
    init(inner: MemoryCommunityDatabase) { self.inner = inner }
    func currentUserRecordName() async throws -> String { try await inner.currentUserRecordName() }
    func save(_ record: CKRecord) async throws -> CKRecord { try await inner.save(record) }
    func create(_ record: CKRecord) async throws -> CKRecord { try await inner.create(record) }
    func fetch(_ recordName: String) async throws -> CKRecord? { try await inner.fetch(recordName) }
    func query(_ query: CommunityQuery) async throws -> [CKRecord] { queries += 1; return try await inner.query(query) }
    func delete(_ recordName: String) async throws { try await inner.delete(recordName) }
}

/// Lets a rival's record appear after the check and before the create.
private final class RacingDatabase: CommunityDatabase {
    let inner: MemoryCommunityDatabase
    var inject: CKRecord?
    init(inner: MemoryCommunityDatabase, injectBeforeCreate: CKRecord) { self.inner = inner; self.inject = injectBeforeCreate }
    func currentUserRecordName() async throws -> String { try await inner.currentUserRecordName() }
    func save(_ record: CKRecord) async throws -> CKRecord { try await inner.save(record) }
    func create(_ record: CKRecord) async throws -> CKRecord {
        if let inject { _ = try await inner.save(inject); self.inject = nil }
        return try await inner.create(record)
    }
    func fetch(_ recordName: String) async throws -> CKRecord? { try await inner.fetch(recordName) }
    func query(_ query: CommunityQuery) async throws -> [CKRecord] { try await inner.query(query) }
    func delete(_ recordName: String) async throws { try await inner.delete(recordName) }
}
