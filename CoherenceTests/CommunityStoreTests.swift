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
        // Two stores over the SAME database, each acting as its own person
        // (`acting(as:)`), so the fake knows who is reading: Block records
        // are readable by their creator only.
        aziz = CommunityStore(database: db.acting(as: "_aziz"))
        melvin = CommunityStore(database: db.acting(as: "_melvin"))
        _ = try await melvin.me()
        _ = try await aziz.me()
    }

    // MARK: Edges that outlived a profile (2026-10-01)

    /// Found on two phones: Melvin deleted his account, made a new profile
    /// (same iCloud user, so the same record name) and sent a request. Aziz's
    /// half from the OLD friendship was still there, so the pair read as
    /// friends without Aziz accepting, and his following went up by itself.
    func test_aNewProfileDoesNotInheritAFriendshipFromADeletedOne() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)
        let before = try await aziz.friends()
        XCTAssertEqual(before, [melvinID])

        try await melvin.deleteEverythingOfMine()
        let gone = try await aziz.friends()
        XCTAssertEqual(gone, [])

        try await melvin.claimUsername("melvin", displayName: "Melvin")
        try await melvin.sendRequest(to: azizID)
        await aziz.forgetProfileDates()

        let friends = try await aziz.friends()
        XCTAssertEqual(friends, [], "nobody accepted the new profile's request")
        let incoming = try await aziz.incomingRequests()
        XCTAssertEqual(incoming, [melvinID], "it arrives as a request to answer")
        let rel = try await aziz.relationship(with: melvinID)
        XCTAssertEqual(rel, .incoming)
        let azizFollows = try await aziz.follows(of: azizID)
        XCTAssertEqual(azizFollows.following, [], "his following does not go up by itself")
        XCTAssertEqual(azizFollows.followers, [melvinID])
        let melvinRel = try await melvin.relationship(with: azizID)
        XCTAssertEqual(melvinRel, .requested, "the new profile sees its own request waiting")
        XCTAssertNil(db.records[CommunityNames.edge(from: azizID, to: melvinID)],
                     "the old half is cleaned up by its writer's app")

        try await aziz.accept(melvinID)
        let after = try await aziz.friends()
        XCTAssertEqual(after, [melvinID], "accepting makes them friends again")
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
    ///
    /// Search makes one query since 2026-09-29, and it is not about the
    /// handle: whether I blocked the person found, from my own blocks
    /// (`Block.from == me`). Blocks have random record names now, so there is
    /// no name to fetch; the handle itself is still never queried.
    func test_claimNeverQueries() async throws {
        let counting = CountingDatabase(inner: db)
        let store = CommunityStore(database: counting)
        _ = try await store.me()
        try await store.claimUsername("aziz", displayName: "Aziz")
        let ok = try await store.isUsernameAvailable("aziz")
        XCTAssertTrue(ok)
        _ = try await store.search(username: "aziz")
        XCTAssertEqual(counting.queries, 0, "claiming, checking and finding my own handle never query")
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        let found = try await store.search(username: "melvin")
        XCTAssertEqual(found?.id, melvinID)
        XCTAssertEqual(counting.queried.map(\.type), [CommunityType.block],
                       "finding someone else queries only my own blocks, never Username or Profile")
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

    /// The handle check is enforced in the store, so no screen can claim
    /// around it: an offensive handle is refused as content, a reserved one
    /// as taken, and neither reserves anything (2026-09-29).
    func test_handleFilterIsEnforcedAtClaim() async throws {
        do { try await aziz.claimUsername("fuckyou", displayName: "Aziz"); XCTFail() }
        catch let e as CommunityError { XCTAssertEqual(e, .contentBlocked) }
        do { try await aziz.claimUsername("808_support", displayName: "Aziz"); XCTFail() }
        catch let e as CommunityError { XCTAssertEqual(e, .usernameTaken) }
        let available = try await aziz.isUsernameAvailable("admin")
        XCTAssertFalse(available, "a reserved handle reads as taken")
        XCTAssertTrue(db.records.values.filter { $0.recordType == CommunityType.username }.isEmpty)
        let profile = try await aziz.myProfile()
        XCTAssertNil(profile, "a refused claim creates no profile")
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

    private lazy var selfie: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("selfie-test.jpg")
        try? Data([0xFF, 0xD8, 0xFF]).write(to: url)
        return url
    }()

    private lazy var testVideo: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("video-test.mp4")
        try? Data([0x00, 0x00, 0x00, 0x18]).write(to: url)
        return url
    }()

    private func draft(caption: String = "") -> CommunityStore.Draft {
        .init(minutes: 18, streak: 4, technique: "Counting", caption: caption,
              media: [.init(kind: .photo, aspect: 0.75, fileURL: selfie, posterURL: selfie)],
              practicedAt: Date())
    }

    func test_photoIsOptionalOnAPost() async throws {
        // A photo is not mandatory to share a session (Melvin, 2026-09-23:
        // "again like we are making the watch optional"). A post with no
        // media must save cleanly, with no media on the saved record. An
        // EMPTY array, not nil: nil would mean "leave what's there," which
        // is not what a brand new, deliberately photo-less post means.
        var d = draft()
        d.media = []
        let post = try await aziz.post(d)
        XCTAssertTrue(post.media.isEmpty)
        XCTAssertEqual(db.records.values.filter { $0.recordType == CommunityType.post }.count, 1)
    }

    func test_editingAPostKeepsItsSelfie() async throws {
        var d = draft(); d.sessionID = "S2"
        try await aziz.post(d)
        // nil, not []: an edit that does not re-send media (only the caption
        // changed) must leave the post's existing picture alone.
        d.media = nil; d.caption = "edited"
        let edited = try await aziz.post(d)
        XCTAssertFalse(edited.media.isEmpty, "an edit without new media keeps the old one")
    }

    func test_postCarriesOnlyTheFreeCardFields() async throws {
        let post = try await aziz.post(draft(caption: "Roof before work."))
        let record = try XCTUnwrap(db.records[post.id])
        XCTAssertEqual(Set(record.allKeys()), Set(Post.fields).subtracting(["sound"]),
                       "a post carries the free share card's data minus the score and nothing measured: no score, no heart, breath or stillness values, no curves (5.1.3(ii) and the free tier)")
        for banned in ["heart", "hr", "breath", "stillness", "curve", "bpm", "score"] {
            XCTAssertFalse(Post.fields.contains { $0.lowercased().contains(banned) }, banned)
        }
    }

    /// A post must never carry a score, even though `Draft` no longer has a
    /// field for one: this pins the CloudKit record itself (2026-09-23, the
    /// founders' call), not just the Swift type, so nothing could quietly
    /// resurrect the field on the wire. Score is derived from heart rate,
    /// this is the PUBLIC database, and 5.1.3(ii) forbids storing personal
    /// health information in iCloud with no consent exception.
    func test_postNeverCarriesAScore() async throws {
        let post = try await aziz.post(draft(caption: "no score, ever"))
        let record = try XCTUnwrap(db.records[post.id])
        XCTAssertNil(record["score"], "a post must never carry a score")
        XCTAssertFalse(Post.fields.contains("score"), "the Swift-side field list must not resurrect it either")
    }

    /// Several photos and a video, in order, through the fake database the
    /// way real CloudKit would hold them: four parallel List fields, read
    /// back fresh rather than trusting the value `post(_:)` just handed over.
    func test_postWithSeveralMediaRoundTripsInOrder() async throws {
        var d = draft()
        d.media = [
            .init(kind: .photo, aspect: 0.75, fileURL: selfie, posterURL: selfie),
            .init(kind: .video, aspect: 1.78, fileURL: testVideo, posterURL: selfie),
            .init(kind: .photo, aspect: 1.0, fileURL: selfie, posterURL: selfie),
        ]
        let post = try await aziz.post(d)
        XCTAssertEqual(post.media.map(\.kind), [.photo, .video, .photo])
        XCTAssertEqual(post.media.map(\.aspect), [0.75, 1.78, 1.0])
        XCTAssertEqual(post.media.map(\.index), [0, 1, 2])
        XCTAssertNotNil(post.media[1].url, "the video's own file, not just its poster")

        let refetched = try await aziz.post(id: post.id)
        XCTAssertEqual(refetched?.media.map(\.kind), [.photo, .video, .photo])
        XCTAssertEqual(refetched?.media.map(\.aspect), [0.75, 1.78, 1.0])
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

    /// `sessionID(forPost:)` is the inverse of `postID(forSession:)`, and
    /// it is what Edit post reads to decide whether a post has a session
    /// page to open at all.
    func test_sessionIDForPostIsTheInverseOfPostIDForSession() {
        let session = UUID()
        let id = CommunityStore.postID(forSession: session.uuidString)
        XCTAssertEqual(CommunityStore.sessionID(forPost: id), session)
        XCTAssertNil(CommunityStore.sessionID(forPost: UUID().uuidString),
                     "a post whose id isn't session-derived has nothing to open")
        XCTAssertNil(CommunityStore.sessionID(forPost: "post-not-a-uuid"))
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

    func test_filteredTextNeverReachesTheDatabase() async throws {
        var d = draft(caption: "f*ck this")
        do { try await aziz.post(d); XCTFail() } catch let e as CommunityError { XCTAssertEqual(e, .contentBlocked) }
        d.caption = "fine"; d.title = "porn"
        do { try await aziz.post(d); XCTFail() } catch let e as CommunityError { XCTAssertEqual(e, .contentBlocked) }
        do { try await aziz.claimUsername("b1tch", displayName: "x"); XCTFail() } catch let e as CommunityError { XCTAssertEqual(e, .contentBlocked) }
        XCTAssertTrue(db.records.isEmpty, "nothing refused is saved")
    }

    func test_reportPayloadCarriesNoPersonalData() throws {
        let data = ReportClient.body(reportID: "r1", target: "post-S1", kind: "post", reason: "spam", appVersion: "1.1")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(Set(json.keys), ["token", "report_id", "target", "kind", "reason", "app_version"])
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

        var old = draft(); old.practicedAt = Date().addingTimeInterval(-3_600)
        let mine = try await aziz.post(old)
        let theirs = try await melvin.post(draft())
        try await stranger.post(draft())

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

    // MARK: Blocks (private and one-sided since 2026-09-29)
    //
    // Melvin: "Don't want others to see who I blocked." A Block is readable by
    // its creator only, so the app reads nothing but its own blocks and
    // enforces them on the blocker's side. These tests run over a fake that
    // models creator-only read (`MemoryCommunityDatabase.creatorOnlyRead`).

    /// Blocking ends the friendship in both apps (by deleting the blocker's
    /// edge, which the blocked person's app can see is gone) and the blocker
    /// never sees the blocked person again.
    func test_blockEndsFriendshipAndTheBlockerNeverSeesThem() async throws {
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)

        try await aziz.block(melvinID)
        try await aziz.block(melvinID)   // a second tap writes nothing new

        XCTAssertEqual(db.records.values.filter { $0.recordType == CommunityType.block }.count, 1)
        XCTAssertNil(db.records[CommunityNames.edge(from: azizID, to: melvinID)], "the blocker's own edge is deleted")
        let mine = try await aziz.friends()
        XCTAssertEqual(mine, [])
        let his = try await melvin.friends()
        XCTAssertEqual(his, [], "the friendship ends in Melvin's app too, from the deleted edge alone")
        let found = try await aziz.search(username: "melvin")
        XCTAssertNil(found, "the blocker cannot find them")
        let page = try await aziz.profile(named: melvinID)
        XCTAssertNil(page, "or open their page")
        let rel = try await aziz.relationship(with: melvinID)
        XCTAssertEqual(rel, .none, "Melvin's standing edge must not read as a request to accept")
        let incoming = try await aziz.incomingRequests()
        XCTAssertEqual(incoming, [])
        let names = try await aziz.profiles(named: [melvinID])
        XCTAssertEqual(names.map(\.displayName), ["Melvin"], "the Blocked list can still name them")
        XCTAssertEqual(names.first?.practice, Coherence.PracticeStats.empty, "and nothing more")
        let blocked = try await aziz.blockedByMe()
        XCTAssertEqual(blocked, [melvinID])

        try await aziz.unblock(melvinID)
        let back = try await aziz.search(username: "melvin")
        XCTAssertEqual(back?.id, melvinID)
        let none = try await aziz.blockedByMe()
        XCTAssertEqual(none, [])
        XCTAssertFalse(db.records.values.contains { $0.recordType == CommunityType.block })
    }

    /// A request from someone I blocked never arrives and can never be
    /// accepted. Their app cannot know: it can still find me and ask, and
    /// sees a request nobody answers.
    func test_requestFromABlockedPersonNeverArrivesAndIsNeverAccepted() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        try await aziz.block(melvinID)

        let seen = try await melvin.search(username: "aziz")
        XCTAssertEqual(seen?.id, azizID, "the blocked person can still see the blocker's public profile")
        try await melvin.sendRequest(to: azizID)
        let waiting = try await melvin.sentRequests()
        XCTAssertEqual(waiting, [azizID], "to Melvin it reads as a request nobody has answered")
        let theirs = try await melvin.relationship(with: azizID)
        XCTAssertEqual(theirs, .requested)

        let incoming = try await aziz.incomingRequests()
        XCTAssertEqual(incoming, [], "it never arrives")
        let rel = try await aziz.relationship(with: melvinID)
        XCTAssertEqual(rel, .none)
        let followers = try await aziz.follows(of: azizID).followers
        XCTAssertEqual(followers, [], "not even as a follower")
        do {
            try await aziz.accept(melvinID)
            XCTFail("accepting a blocked person must be refused")
        } catch let e as CommunityError {
            XCTAssertEqual(e, .blocked)
        }
        XCTAssertNil(db.records[CommunityNames.edge(from: azizID, to: melvinID)], "no edge was written back")
        let friends = try await melvin.friends()
        XCTAssertEqual(friends, [], "so Melvin never becomes a friend")
    }

    /// The blocker does not see the blocked person in someone else's
    /// follower or following list either.
    func test_blockedPersonLeavesOtherPeoplesListsForTheBlocker() async throws {
        let lenaID = CommunityNames.profile(user: "_lena")
        let lena = CommunityStore(database: db.acting(as: "_lena"))
        _ = try await lena.me()
        try await lena.sendRequest(to: melvinID)
        try await melvin.accept(lenaID)
        var lists = try await aziz.follows(of: lenaID)
        XCTAssertEqual(lists.followers, [melvinID])

        try await aziz.block(melvinID)

        lists = try await aziz.follows(of: lenaID)
        XCTAssertEqual(lists.followers, [])
        XCTAssertEqual(lists.following, [])
        let his = try await aziz.follows(of: melvinID)
        XCTAssertTrue(his.followers.isEmpty && his.following.isEmpty, "and a blocked person has no lists for me")
    }

    /// Nobody but the blocker can read a block: not a third person, not the
    /// person blocked. By who it is about, by who made it, or by name.
    func test_nobodyElseCanReadWhoBlockedWhom() async throws {
        try await aziz.block(melvinID)
        let record = try XCTUnwrap(db.records.values.first { $0.recordType == CommunityType.block })
        let name = record.recordID.recordName
        XCTAssertFalse(name.contains("_aziz") || name.contains("_melvin"),
                       "the record name must not say who blocked whom: \(name)")

        for reader in ["_lena", "_melvin"] {
            let view = db.acting(as: reader)
            let byTo = try await view.query(CommunityQuery(type: CommunityType.block,
                                                           filters: [.equals("to", .reference(melvinID))]))
            let byFrom = try await view.query(CommunityQuery(type: CommunityType.block,
                                                             filters: [.equals("from", .reference(azizID))]))
            let fetched = try await view.fetch(name)
            XCTAssertTrue(byTo.isEmpty, "\(reader) must not find the block by who it is about")
            XCTAssertTrue(byFrom.isEmpty, "\(reader) must not find it by who made it")
            XCTAssertNil(fetched, "\(reader) must not fetch it by name")
            let theirOwn = try await CommunityStore(database: view).blockedByMe()
            XCTAssertEqual(theirOwn, [], "\(reader)'s store sees only their own blocks")
        }
        let own = try await db.acting(as: "_aziz").query(CommunityQuery(type: CommunityType.block,
                                                                        filters: [.equals("from", .reference(azizID))]))
        XCTAssertEqual(own.count, 1, "the blocker reads their own")
    }

    /// A block someone ELSE writes naming me as the blocker does nothing:
    /// my app never reads it, so it cannot hide a friend from me.
    func test_aPlantedBlockInMyNameDoesNothing() async throws {
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)
        let planted = CKRecord(recordType: CommunityType.block, recordID: CKRecord.ID(recordName: CommunityNames.newBlock()))
        Block(from: azizID, to: melvinID).apply(to: planted)
        _ = try await db.acting(as: "_lena").save(planted)

        let blocked = try await aziz.blockedByMe()
        XCTAssertEqual(blocked, [])
        let friends = try await aziz.friends()
        XCTAssertEqual(friends, [melvinID])
    }

    /// Every read of the Block type, across every store call the screens
    /// make, is `from == me`: nothing queries `Block.to` or fetches a block by
    /// name, so the Console can take world read off Block without any query
    /// failing. Run as the BLOCKED person too: their app never needs the
    /// blocker's record.
    func test_theOnlyBlockReadIsMyOwn() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)
        try await aziz.block(melvinID)

        for (user, other, handle) in [("_aziz", melvinID, "melvin"), ("_melvin", azizID, "aziz")] {
            let me = CommunityNames.profile(user: user)
            let recording = BlockReadRecordingDatabase(inner: db.acting(as: user))
            let store = CommunityStore(database: recording)
            _ = try await store.me()
            _ = try await store.friends()
            _ = try await store.incomingRequests()
            _ = try await store.sentRequests()
            _ = try await store.blockedByMe()
            _ = try await store.relationship(with: other)
            _ = try await store.search(username: handle)
            _ = try await store.profile(named: other)
            _ = try await store.profiles(named: [other])
            _ = try await store.follows(of: other)
            _ = try await store.follows(of: me)
            _ = try await store.friendFacts()
            _ = try await store.reactors(to: "post-x")
            _ = try await store.reactions(for: ["post-x"])
            try? await store.sendRequest(to: other)
            try await store.block(CommunityNames.profile(user: "_someone"))
            try await store.unblock(CommunityNames.profile(user: "_someone"))
            try await store.deleteEverythingOfMine()

            XCTAssertFalse(recording.blockQueries.isEmpty)
            for q in recording.blockQueries {
                XCTAssertEqual(q.filters, [.equals("from", .reference(me))], "\(user) read a Block that is not their own: \(q)")
            }
            XCTAssertEqual(recording.fetchedBlockNames, [], "\(user) fetched a Block by name")
        }
    }

    /// A block written before 2026-09-29 carries the old `block-<from>-<to>`
    /// name. It still counts, blocking again adds nothing, and Unblock
    /// removes it.
    func test_anOldNamedBlockStillCountsAndUnblocks() async throws {
        let legacyName = "block-" + azizID + "-" + melvinID
        let legacy = CKRecord(recordType: CommunityType.block, recordID: CKRecord.ID(recordName: legacyName))
        Block(id: legacyName, from: azizID, to: melvinID).apply(to: legacy)
        _ = try await db.acting(as: "_aziz").save(legacy)

        var blocked = try await aziz.blockedByMe()
        XCTAssertEqual(blocked, [melvinID])
        try await aziz.block(melvinID)
        XCTAssertEqual(db.records.values.filter { $0.recordType == CommunityType.block }.count, 1)
        try await aziz.unblock(melvinID)
        blocked = try await aziz.blockedByMe()
        XCTAssertEqual(blocked, [])
        XCTAssertNil(db.records[legacyName])
    }

    /// Being blocked drops their posts from my feed without my app reading
    /// their block: their edge is gone, so we are no longer friends.
    func test_blockedPersonsPostsLeaveTheFeed() async throws {
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)
        try await melvin.post(draft())
        var feed = try await aziz.feed()
        XCTAssertEqual(feed.count, 1)
        try await melvin.block(azizID)
        feed = try await aziz.feed()
        XCTAssertEqual(feed, [], "the friendship ended, so their posts leave my feed")
    }

    // MARK: Reports and first session

    func test_reportIsWrittenWithReporterAndTarget() async throws {
        let post = try await melvin.post(draft())
        let r = try await aziz.report(post.id, as: .post, reason: "not a meditation")
        let record = try XCTUnwrap(db.records[r.id])
        XCTAssertEqual(record.recordType, CommunityType.report)
        XCTAssertEqual((record["reporter"] as? CKRecord.Reference)?.recordID.recordName, azizID)
        // A Reference, matching the CloudKit schema: a String is refused by the
        // server and every report fails (2026-10-01).
        XCTAssertEqual((record["target"] as? CKRecord.Reference)?.recordID.recordName, post.id)
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

    // MARK: Practice stats

    // `CoherenceTests` compiles `Shared/` directly into itself (see the
    // header comment on `Shared/Community/InviteReward.swift`), so an
    // unqualified `PracticeStats` here resolves to THIS module's own copy,
    // not `Coherence.PracticeStats` — the type `CommunityStore` actually
    // takes. Qualified explicitly below for that reason.

    /// How often I meditate, published and read back — the fields
    /// `PracticeStats.compute` fills in, nothing else touched.
    func test_updatePracticeStatsWritesAndReadsBackAllFiveFields() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        let last = Date(timeIntervalSince1970: 2_000_000)
        let stats = Coherence.PracticeStats(sessions7d: 4, minutes7d: 62, currentStreak: 9,
                                            totalSessions: 41, lastSessionAt: last)
        let profile = try await aziz.updatePracticeStats(stats)
        XCTAssertEqual(profile.practice, stats)
        let reread = try await aziz.myProfile()
        XCTAssertEqual(reread?.practice, stats)
    }

    /// Publishing stats never disturbs the identity fields, and claiming or
    /// renaming never resets stats already published — each changes through
    /// its own call, like the avatar.
    func test_updatePracticeStatsLeavesIdentityUntouchedAndSurvivesARename() async throws {
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        let stats = Coherence.PracticeStats(sessions7d: 2, minutes7d: 20, currentStreak: 3,
                                            totalSessions: 10, lastSessionAt: Date(timeIntervalSince1970: 1_000))
        try await aziz.updatePracticeStats(stats)
        let renamed = try await aziz.claimUsername("aziz", displayName: "Aziz M")
        XCTAssertEqual(renamed.practice, stats, "a rename must not reset how often I meditate")
        XCTAssertEqual(renamed.username, "aziz")
        XCTAssertEqual(renamed.displayName, "Aziz M")
    }

    /// A profile that has never published anything reads the empty default,
    /// never a crash on a missing field.
    func test_practiceStatsDefaultToEmpty() async throws {
        let p = try await aziz.claimUsername("aziz", displayName: "Aziz")
        XCTAssertEqual(p.practice, .empty)
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
    var queried: [CommunityQuery] = []
    var queries: Int { queried.count }
    init(inner: MemoryCommunityDatabase) { self.inner = inner }
    func currentUserRecordName() async throws -> String { try await inner.currentUserRecordName() }
    func save(_ record: CKRecord) async throws -> CKRecord { try await inner.save(record) }
    func create(_ record: CKRecord) async throws -> CKRecord { try await inner.create(record) }
    func fetch(_ recordName: String) async throws -> CKRecord? { try await inner.fetch(recordName) }
    func query(_ query: CommunityQuery) async throws -> [CKRecord] { queried.append(query); return try await inner.query(query) }
    func delete(_ recordName: String) async throws { try await inner.delete(recordName) }
}

/// Records every read of the Block type: queries with their filters, and
/// fetches of a `block-` record name. The app may only ever read its own.
private final class BlockReadRecordingDatabase: CommunityDatabase {
    let inner: CommunityDatabase
    var blockQueries: [CommunityQuery] = []
    var fetchedBlockNames: [String] = []
    init(inner: CommunityDatabase) { self.inner = inner }
    func currentUserRecordName() async throws -> String { try await inner.currentUserRecordName() }
    func save(_ record: CKRecord) async throws -> CKRecord { try await inner.save(record) }
    func create(_ record: CKRecord) async throws -> CKRecord { try await inner.create(record) }
    func fetch(_ recordName: String) async throws -> CKRecord? {
        if recordName.hasPrefix("block-") { fetchedBlockNames.append(recordName) }
        return try await inner.fetch(recordName)
    }
    func query(_ query: CommunityQuery) async throws -> [CKRecord] {
        if query.type == CommunityType.block { blockQueries.append(query) }
        return try await inner.query(query)
    }
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

final class CommunityBugfixTests: XCTestCase {
    private func stores() async throws -> (MemoryCommunityDatabase, CommunityStore, CommunityStore) {
        let db = MemoryCommunityDatabase(user: "_a")
        let a = CommunityStore(database: db); _ = try await a.me()
        db.user = "_b"
        let b = CommunityStore(database: db); _ = try await b.me()
        db.user = "_a"
        return (db, a, b)
    }

    /// Re-sending a request must not reset its date: the older edge decides
    /// who asked first, and so who earns the invite reward.
    func test_resendingARequestKeepsItsDate() async throws {
        let (db, a, b) = try await stores()
        let bID = CommunityNames.profile(user: "_b"), aID = CommunityNames.profile(user: "_a")
        try await a.sendRequest(to: bID)
        let first = db.records[CommunityNames.edge(from: aID, to: bID)]?["createdAt"] as? Date
        try await Task.sleep(nanoseconds: 5_000_000)
        try await b.accept(aID)
        try await a.sendRequest(to: bID)          // a taps Add friend again
        let after = db.records[CommunityNames.edge(from: aID, to: bID)]?["createdAt"] as? Date
        XCTAssertEqual(first, after)
        let facts = try await a.friendFacts()
        XCTAssertEqual(facts.first?.iAskedFirst, true)
    }

    /// A failed profile save must give back the handle it just reserved.
    func test_failedProfileSaveReleasesTheNewHandle() async throws {
        let db = FailingProfileSaveDatabase(user: "_c")
        let c = CommunityStore(database: db)
        do { try await c.claimUsername("calm", displayName: "C"); XCTFail() } catch {}
        XCTAssertNil(db.records[CommunityNames.username("calm")], "the reservation was rolled back")
    }
}

/// Saves everything except Profile records, which fail.
private final class FailingProfileSaveDatabase: CommunityDatabase {
    let inner: MemoryCommunityDatabase
    var records: [String: CKRecord] { inner.records }
    init(user: String) { inner = MemoryCommunityDatabase(user: user) }
    func currentUserRecordName() async throws -> String { try await inner.currentUserRecordName() }
    func save(_ record: CKRecord) async throws -> CKRecord {
        if record.recordType == CommunityType.profile { throw CommunityError.unavailable }
        return try await inner.save(record)
    }
    func create(_ record: CKRecord) async throws -> CKRecord { try await inner.create(record) }
    func fetch(_ recordName: String) async throws -> CKRecord? { try await inner.fetch(recordName) }
    func query(_ query: CommunityQuery) async throws -> [CKRecord] { try await inner.query(query) }
    func delete(_ recordName: String) async throws { try await inner.delete(recordName) }
}

final class InviteFarmingTests: XCTestCase {
    /// Adding someone who already practised before you asked is not bringing
    /// them: no reward, however long you stay friends.
    func test_friendWhoSatBeforeTheRequestIsNotRewarded() async throws {
        let db = MemoryCommunityDatabase(user: "_old")
        let old = CommunityStore(database: db); _ = try await old.me()
        try await old.claimUsername("veteran", displayName: "V")
        try await old.markFirstSession(at: Date(timeIntervalSince1970: 1_000))
        db.user = "_me"
        let me = CommunityStore(database: db); _ = try await me.me()
        try await me.sendRequest(to: CommunityNames.profile(user: "_old"))
        db.user = "_old"
        try await old.accept(CommunityNames.profile(user: "_me"))
        db.user = "_me"
        let facts = try await me.friendFacts()
        XCTAssertEqual(facts.first?.iAskedFirst, true)
        XCTAssertEqual(facts.first?.hasFirstSession, false, "their first session predates my request")
    }

    func test_friendWhoSatAfterTheRequestIsRewarded() async throws {
        let db = MemoryCommunityDatabase(user: "_new")
        let new = CommunityStore(database: db); _ = try await new.me()
        try await new.claimUsername("newbie", displayName: "N")
        db.user = "_me"
        let me = CommunityStore(database: db); _ = try await me.me()
        try await me.sendRequest(to: CommunityNames.profile(user: "_new"))
        db.user = "_new"
        try await new.accept(CommunityNames.profile(user: "_me"))
        try await new.markFirstSession(at: Date().addingTimeInterval(5))
        db.user = "_me"
        let facts = try await me.friendFacts()
        XCTAssertEqual(facts.first?.hasFirstSession, true)
    }
}

@MainActor
final class PostRemovalTests: XCTestCase {
    /// Deleting a session's post from the feed tells the app which session,
    /// so its "Friends can see this" chip stops lying.
    func test_deletingASessionPostReportsTheSession() async throws {
        let db = MemoryCommunityDatabase(user: "_me")
        let model = CommunityModel(store: CommunityStore(database: db))
        await model.load()
        _ = await model.claim("poster", displayName: "P")
        let session = UUID()
        let selfie = FileManager.default.temporaryDirectory.appendingPathComponent("rm-test.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: selfie)
        let ok = await model.post(.init(minutes: 10, streak: 1, technique: nil, caption: "",
                                        media: [.init(kind: .photo, aspect: 0.75, fileURL: selfie, posterURL: selfie)],
                                        practicedAt: Date(), sessionID: session.uuidString))
        XCTAssertTrue(ok)
        var told: UUID?
        model.onPostRemoved = { told = $0 }
        await model.deletePost(CommunityStore.postID(forSession: session.uuidString))
        XCTAssertEqual(told, session)
        XCTAssertTrue(model.feed.isEmpty)
    }

    /// An edited post keeps its place, and a post saved late (a session
    /// shared days after it was practiced) lands by its date, never on top.
    func test_aSavedPostTakesItsPlaceByDateNotTheTop() {
        let now = Date()
        func post(_ id: String, hoursAgo: Double, caption: String = "") -> Post {
            Post(id: id, author: "a", minutes: 10, streak: 1, caption: caption,
                 practicedAt: now.addingTimeInterval(-hoursAgo * 3600))
        }
        let feed = [post("tonight", hoursAgo: 1), post("afternoon", hoursAgo: 7), post("yesterday", hoursAgo: 24)]

        let edited = CommunityModel.placing(post("afternoon", hoursAgo: 7, caption: "edited"), in: feed)
        XCTAssertEqual(edited.map(\.id), ["tonight", "afternoon", "yesterday"])
        XCTAssertEqual(edited[1].caption, "edited")

        let late = CommunityModel.placing(post("lastWeek", hoursAgo: 150), in: feed)
        XCTAssertEqual(late.map(\.id), ["tonight", "afternoon", "yesterday", "lastWeek"])

        let justNow = CommunityModel.placing(post("justNow", hoursAgo: 0), in: feed)
        XCTAssertEqual(justNow.first?.id, "justNow")
    }
}

/// Records every record type queried, to prove what a screen never asks for.
private final class TypeRecordingDatabase: CommunityDatabase {
    let inner: MemoryCommunityDatabase
    var types: [String] = []
    init(inner: MemoryCommunityDatabase) { self.inner = inner }
    func currentUserRecordName() async throws -> String { try await inner.currentUserRecordName() }
    func save(_ record: CKRecord) async throws -> CKRecord { try await inner.save(record) }
    func create(_ record: CKRecord) async throws -> CKRecord { try await inner.create(record) }
    func fetch(_ recordName: String) async throws -> CKRecord? { try await inner.fetch(recordName) }
    func query(_ query: CommunityQuery) async throws -> [CKRecord] { types.append(query.type); return try await inner.query(query) }
    func delete(_ recordName: String) async throws { try await inner.delete(recordName) }
}

/// Friends is optional (Melvin, 2026-09-29), and the feed is gone.
@MainActor
final class FriendsOptionalTests: XCTestCase {
    private let meID = CommunityNames.profile(user: "_me")
    private let otherID = CommunityNames.profile(user: "_other")

    /// With no profile, nothing reaches another person: no search, no
    /// request, no published practice stats.
    func test_withoutAProfileNothingReachesAnyone() async throws {
        let db = MemoryCommunityDatabase(user: "_other")
        let other = CommunityStore(database: db)
        _ = try await other.me()
        try await other.claimUsername("melvin", displayName: "Melvin")
        db.user = "_me"
        let model = CommunityModel(store: CommunityStore(database: db))
        model.allSessions = { [(startedAt: Date(), durationSec: 600)] }
        await model.load()
        XCTAssertEqual(model.phase, .needsUsername)
        XCTAssertFalse(model.hasProfile)

        let found = await model.search("melvin")
        XCTAssertNil(found, "searching waits for a profile")
        await model.request(otherID)
        XCTAssertNotNil(model.errorText)
        XCTAssertNil(db.records[CommunityNames.edge(from: meID, to: otherID)], "no request was written")
        await model.syncPracticeStats(force: true)
        XCTAssertNil(db.records[meID], "nothing about how often I meditate was published")
    }

    /// Opening Friends asks for friends, requests and blocks, never the
    /// removed feed: in a container missing the Post type or its index that
    /// query failed and the whole tab read as broken.
    func test_openingFriendsNeverQueriesPostsOrReactions() async throws {
        let recording = TypeRecordingDatabase(inner: MemoryCommunityDatabase(user: "_me"))
        let model = CommunityModel(store: CommunityStore(database: recording))
        await model.load()
        _ = await model.claim("aziz", displayName: "Aziz")
        await model.refresh()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(recording.types.isEmpty, "the lists were loaded")
        XCTAssertFalse(recording.types.contains(CommunityType.post))
        XCTAssertFalse(recording.types.contains(CommunityType.reaction))
    }

    /// Remove photo on Edit profile takes the published photo down, not just
    /// the one picked on the screen.
    func test_clearAvatarTakesThePublishedPhotoDown() async throws {
        let db = MemoryCommunityDatabase(user: "_me")
        let model = CommunityModel(store: CommunityStore(database: db))
        await model.load()
        _ = await model.claim("aziz", displayName: "Aziz")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-clear.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: file)
        _ = try await model.store?.setAvatar(file)
        XCTAssertNotNil(db.records[meID]?["avatar"])
        await model.clearAvatar()
        XCTAssertNil(db.records[meID]?["avatar"])
        XCTAssertNil(model.profile?.avatarURL)
    }
}

/// What the phone keeps about someone I blocked (Melvin, 2026-09-29: the
/// blocker never sees the blocked person, practice summary included).
@MainActor
final class BlockPrivacyModelTests: XCTestCase {
    private let otherID = CommunityNames.profile(user: "_other")

    func test_blockingDropsEverythingButTheirName() async throws {
        UserDefaults.standard.removeObject(forKey: CommunityModel.pendingDeletionKey)
        let db = MemoryCommunityDatabase(user: "_other")
        let other = CommunityStore(database: db.acting(as: "_other"))
        try await other.claimUsername("melvin", displayName: "Melvin")
        try await other.updatePracticeStats(Coherence.PracticeStats(sessions7d: 4, minutes7d: 60, currentStreak: 9,
                                                                   totalSessions: 41, lastSessionAt: Date()))
        let model = CommunityModel(store: CommunityStore(database: db.acting(as: "_me")))
        await model.load()
        _ = await model.claim("aziz", displayName: "Aziz")
        await model.request(otherID)
        XCTAssertEqual(model.person(otherID)?.practice.totalSessions, 41, "cached in full while not blocked")

        await model.block(otherID)

        XCTAssertTrue(model.isBlocked(otherID))
        XCTAssertEqual(model.blocked, [otherID])
        XCTAssertTrue(model.sent.isEmpty)
        XCTAssertEqual(model.person(otherID)?.displayName, "Melvin", "the Blocked list can still name them")
        XCTAssertEqual(model.person(otherID)?.practice, Coherence.PracticeStats.empty, "their practice summary is gone")
        await model.loadFollowCounts(otherID)
        XCTAssertNil(model.followCounts[otherID], "no follow lists for a blocked person")
        await model.loadPerson(otherID)
        XCTAssertEqual(model.person(otherID)?.practice, Coherence.PracticeStats.empty, "opening their page loads nothing")

        // A fresh model on the same phone, as after a relaunch.
        let fresh = CommunityModel(store: CommunityStore(database: db.acting(as: "_me")))
        await fresh.load()
        await fresh.loadBlocked()
        XCTAssertEqual(fresh.blocked, [otherID])
        XCTAssertEqual(fresh.person(otherID)?.displayName, "Melvin")
        XCTAssertEqual(fresh.person(otherID)?.practice, Coherence.PracticeStats.empty)

        await fresh.unblock(otherID)
        XCTAssertFalse(fresh.isBlocked(otherID))
        await fresh.loadPerson(otherID)
        XCTAssertEqual(fresh.person(otherID)?.practice.totalSessions, 41, "unblocking brings them back in full")
    }
}
