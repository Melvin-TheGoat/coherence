import XCTest
@testable import Coherence

/// Invite codes (2026-10-18): the code's shape, and joining with one through
/// the store, two people over one fake public database.
final class InviteCodeTests: XCTestCase {

    // MARK: The code itself

    func test_aCodeIsTheUsernameThenThreeUnambiguousCharacters() {
        var rng = SeededGenerator(seed: 7)
        let code = InviteCode.make(username: "aziz.m_99", using: &rng)
        XCTAssertTrue(code.hasPrefix("AZIZM"))
        XCTAssertEqual(code.count, 10, "five letters of the name, five random: too many to guess")
        XCTAssertTrue(code.suffix(5).allSatisfy { InviteCode.alphabet.contains($0) })
        XCTAssertEqual(InviteCode.make(username: "_9_", using: &rng).prefix(4), "OTTO")
        for ch in "0O1IL2Z5S8B" { XCTAssertFalse(InviteCode.alphabet.contains(ch), "\(ch) reads as another") }
    }

    func test_typedPastedAndShownForms() {
        XCTAssertEqual(InviteCode.normalize("aziz-k7qx4"), "AZIZK7QX4")
        XCTAssertEqual(InviteCode.normalize(" AZIZ K7QX4 "), "AZIZK7QX4")
        XCTAssertEqual(InviteCode.normalize("Meditate with me on 808 🧘 Use my code AZIZ-K7QX4 when you join"), "AZIZK7QX4")
        XCTAssertEqual(InviteCode.normalize("saw an x-ray12 today, code AZIZ-K7QX4"), "AZIZK7QX4",
                       "the code in capitals wins over a hyphenated word")
        XCTAssertNil(InviteCode.normalize("hi"))
        XCTAssertNil(InviteCode.normalize("way-too-long-code"))
        XCTAssertEqual(InviteCode.display("AZIZK7QX4"), "AZIZ-K7QX4")
        XCTAssertTrue(InviteCode.message(for: "AZIZK7QX4").contains("AZIZ-K7QX4"))
        XCTAssertFalse(InviteCode.message(for: "AZIZK7QX4").contains("\u{2014}"), "no em dashes in copy")
    }

    // MARK: Through the store

    private var db: MemoryCommunityDatabase!
    private var aziz: CommunityStore!
    private var sam: CommunityStore!
    private var mel: CommunityStore!
    private let azizID = CommunityNames.profile(user: "_aziz")
    private let samID = CommunityNames.profile(user: "_sam")
    private let melID = CommunityNames.profile(user: "_mel")

    override func setUp() async throws {
        db = MemoryCommunityDatabase(user: "_aziz")
        aziz = CommunityStore(database: db.acting(as: "_aziz"))
        sam = CommunityStore(database: db.acting(as: "_sam"))
        mel = CommunityStore(database: db.acting(as: "_mel"))
        try await aziz.claimUsername("aziz", displayName: "Aziz")
    }

    func test_myCodeIsMadeOnceAndKept() async throws {
        let first = try await aziz.myInviteCode()
        let again = try await aziz.myInviteCode()
        XCTAssertEqual(first, again)
        XCTAssertTrue(first.hasPrefix("AZIZ"))
        XCTAssertNotNil(db.records[CommunityNames.inviteCode(first)])
        let profile = try await aziz.myProfile()
        XCTAssertEqual(profile?.inviteCode, first)
    }

    func test_aCodeIsLookedUpBeforeTheJoinerHasAProfile() async throws {
        let code = try await aziz.myInviteCode()
        let found = try await sam.inviter(forCode: InviteCode.display(code).lowercased())
        XCTAssertEqual(found?.id, azizID)
        let nobody = try await sam.inviter(forCode: "NOPE-AAAAA")
        XCTAssertNil(nobody)
    }

    func test_joiningWithACodeMakesFriendsAtOnceOnBothSides() async throws {
        let code = try await aziz.myInviteCode()
        try await sam.claimUsername("sam_p", displayName: "Sam")
        try await sam.redeem(code: code, myName: "Sam")

        // Before Aziz's app has done anything at all.
        let samFriends = try await sam.friends()
        let azizFriends = try await aziz.friends()
        XCTAssertEqual(samFriends, [azizID])
        XCTAssertEqual(azizFriends, [samID])
        let samSent = try await sam.sentRequests()
        let azizIncoming = try await aziz.incomingRequests()
        XCTAssertEqual(samSent, [], "never shown as a request")
        XCTAssertEqual(azizIncoming, [])
        let rel = try await sam.relationship(with: azizID)
        XCTAssertEqual(rel, .friends)

        // Aziz's app writes its half, and says who joined.
        let joined = try await aziz.answerCodeJoins()
        XCTAssertEqual(joined, [samID])
        XCTAssertNotNil(db.records[CommunityNames.edge(from: azizID, to: samID)])
        let samsFriendsSeenByMel = try await mel.friends(of: samID)
        XCTAssertEqual(samsFriendsSeenByMel, [azizID], "a plain friendship to everyone else")
    }

    /// Once Aziz's app has answered a join, removing Sam is an ordinary
    /// removal: it sticks on both phones, and the next refresh never writes
    /// Aziz's half back (found in review, 2026-10-18).
    func test_removingAFriendWhoJoinedWithMyCodeSticks() async throws {
        let code = try await aziz.myInviteCode()
        try await sam.claimUsername("sam_p", displayName: "Sam")
        try await sam.redeem(code: code, myName: "Sam")
        _ = try await aziz.answerCodeJoins()
        try await aziz.removeFriend(samID)
        _ = try await aziz.answerCodeJoins()
        let azizFriends = try await aziz.friends()
        let samFriends = try await sam.friends()
        XCTAssertEqual(azizFriends, [])
        XCTAssertEqual(samFriends, [])
        XCTAssertNil(db.records[CommunityNames.edge(from: azizID, to: samID)])
    }

    /// Sam joined Aziz's code: Aziz brought Sam, never the reverse.
    func test_theJoinerNeverEarnsBroughtAFriend() async throws {
        let code = try await aziz.myInviteCode()
        try await sam.claimUsername("sam_p", displayName: "Sam")
        try await sam.redeem(code: code, myName: "Sam")
        _ = try await aziz.answerCodeJoins()
        let samsFacts = try await sam.friendFacts()
        XCTAssertEqual(samsFacts, [])
    }

    func test_yourOwnCodeAndAnUnknownCodeAreRefused() async throws {
        let code = try await aziz.myInviteCode()
        do { try await aziz.redeem(code: code, myName: "Aziz"); XCTFail("own code") }
        catch let e as CommunityError { XCTAssertEqual(e, .inviteCodeIsYours) }
        try await sam.claimUsername("sam_p", displayName: "Sam")
        do { try await sam.redeem(code: "ZZZZ-AAAAA", myName: "Sam"); XCTFail("unknown") }
        catch let e as CommunityError { XCTAssertEqual(e, .inviteCodeUnknown) }
    }

    /// A code on an edge proves a friendship only with the code's owner:
    /// Sam putting Aziz's code on a request to Mel makes nobody friends.
    func test_aCodeOnTheWrongPersonsEdgeProvesNothing() async throws {
        let code = try await aziz.myInviteCode()
        try await sam.claimUsername("sam_p", displayName: "Sam")
        try await mel.claimUsername("mel", displayName: "Mel")
        let record = CKRecordFactory.edge(from: samID, to: melID, viaCode: code)
        db.records[record.recordID.recordName] = record
        let samFriends = try await sam.friends()
        let melFriends = try await mel.friends()
        XCTAssertEqual(samFriends, [])
        XCTAssertEqual(melFriends, [])
    }

    func test_someoneIBlockedCannotBeFoundByTheirCode() async throws {
        let code = try await aziz.myInviteCode()
        try await sam.claimUsername("sam_p", displayName: "Sam")
        try await sam.block(azizID)
        let found = try await sam.inviter(forCode: code)
        XCTAssertNil(found)
    }

    func test_deletingAnAccountReleasesItsCode() async throws {
        let code = try await aziz.myInviteCode()
        try await aziz.deleteEverythingOfMine()
        XCTAssertNil(db.records[CommunityNames.inviteCode(code)])
    }

    /// Someone who joined with my code was brought by me, for the award,
    /// though my edge to them is the newer one.
    func test_aCodeJoinCountsAsBroughtAFriend() async throws {
        let code = try await aziz.myInviteCode()
        try await sam.claimUsername("sam_p", displayName: "Sam")
        try await sam.redeem(code: code, myName: "Sam")
        _ = try await aziz.answerCodeJoins()
        let facts = try await aziz.friendFacts()
        XCTAssertEqual(facts.first?.id, samID)
        XCTAssertEqual(facts.first?.iAskedFirst, true)
    }
}

import CloudKit

/// Builds a raw edge record, for writing one the app itself never would.
private enum CKRecordFactory {
    static func edge(from: String, to: String, viaCode: String) -> CKRecord {
        let edge = FriendEdge(from: from, to: to, viaCode: viaCode, fromName: "x")
        let record = CKRecord(recordType: CommunityType.edge, recordID: CKRecord.ID(recordName: edge.id))
        edge.apply(to: record)
        return record
    }
}
