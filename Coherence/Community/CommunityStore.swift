import Foundation
import CloudKit
import os

/// Everything the Friends tab and the post composer do, over any
/// `CommunityDatabase`. No UI, no SwiftData; callers pass in what they know
/// (display name, the session's numbers) and get value types back.
///
/// Identity: the iCloud user record name, read once per store. The profile
/// record name is derived from it, so "me" is always `CommunityNames
/// .profile(user:)` and never needs a lookup.
///
/// **Blocks are private, and enforced entirely on the blocker's side**
/// (Melvin, 2026-09-29: "Don't want others to see who I blocked"). The
/// `Block` record type is readable only by its creator, so this store reads
/// ONLY the blocks the current person wrote (`myBlocks`, one query,
/// `from == me`) and never anyone else's: no query on `Block.to`, no fetch of
/// another person's block by name. With those blocks it hides the blocked
/// person from the blocker everywhere: search, profile pages, friends,
/// requests (theirs never arrive, and can never be accepted), follower and
/// following lists, and their practice summary. Blocking also deletes the
/// friend edge the blocker wrote, which ends the friendship for both apps.
///
/// **What a creator-only block cannot do, stated plainly:** the blocked
/// person's app can no longer learn that it was blocked. It can still look up
/// the blocker's public profile (anyone can, by username) and still send a
/// friend request. That request simply never arrives: the blocker's app
/// filters it out and will not accept it, so from the blocked side it reads
/// as a request nobody has answered, which is exactly what "they won't be
/// told" means.
actor CommunityStore {
    private let db: CommunityDatabase
    private var cachedUser: String?

    init(database: CommunityDatabase) { self.db = database }

    // MARK: - Authorship

    /// Whether a record's claimed author (`field`, a profile reference) is
    /// the iCloud user who actually created it.
    ///
    /// The public database lets anyone create a record, and a reference
    /// field is just data: without this, anyone could write a Post, a
    /// FriendEdge, a Reaction or a Block naming someone else, and every
    /// reader would believe it (a post "by" your friend, a fake acceptance).
    /// CloudKit stamps `creatorUserRecordID` itself, so it cannot be forged.
    /// For the current user's own records it reads `__defaultOwner__`. The
    /// in-memory database leaves it nil, which is trusted.
    private func authored(_ record: CKRecord, by field: String) -> Bool {
        guard let claimed = (record[field] as? CKRecord.Reference)?.recordID.recordName else { return false }
        guard let creator = record.creatorUserRecordID?.recordName else { return true }
        if creator == CKCurrentUserDefaultName {
            return cachedUser.map { claimed == CommunityNames.profile(user: $0) } ?? false
        }
        return claimed == CommunityNames.profile(user: creator)
    }

    // MARK: - Me

    /// My profile record name, deriving the user on first use.
    func me() async throws -> String {
        if let cachedUser { return CommunityNames.profile(user: cachedUser) }
        let user = try await db.currentUserRecordName()
        cachedUser = user
        return CommunityNames.profile(user: user)
    }

    func myProfile() async throws -> Profile? {
        guard let record = try await db.fetch(try await me()) else { return nil }
        return Profile(record: record)
    }

    /// The owner of a handle, or nil when nobody holds it.
    ///
    /// **Usernames are reserved by RECORD NAME, never found by query.** A
    /// query needs the record type to exist and the field to be indexed in
    /// the CloudKit Console; on a fresh container neither is true, and the
    /// first version's claim screen silently failed on Aziz's phone for
    /// exactly that reason. A fetch by name needs no schema and no index.
    private func holder(of handle: String) async throws -> String? {
        guard let record = try await db.fetch(CommunityNames.username(handle)) else { return nil }
        return (record["profile"] as? CKRecord.Reference)?.recordID.recordName
    }

    /// True when nobody else holds the handle. My own reservation counts as
    /// free, so re-saving my own name never reads as taken.
    func isUsernameAvailable(_ raw: String) async throws -> Bool {
        guard let handle = Username.normalize(raw) else { throw CommunityError.usernameInvalid }
        let mine = try await me()
        let owner = try await holder(of: handle)
        // A handle already mine stays mine, even if it was claimed before the
        // reserved-word and blocked-word rules existed (2026-09-30): checking
        // the filter first locked those people out of every profile edit.
        if owner == mine { return true }
        switch ContentFilter.checkHandle(handle) {
        case .blocked: throw CommunityError.contentBlocked
        case .reserved: return false
        case .ok: break
        }
        return owner == nil
    }

    /// Claim a handle, creating the profile if this is the first time.
    ///
    /// The reservation is CREATED, not saved: the server refuses a second
    /// record with the same name, so two people claiming one name in the same
    /// second cannot both win. Changing handles releases the old reservation
    /// after the new one is held, so a failure never leaves someone nameless.
    @discardableResult
    func claimUsername(_ raw: String, displayName: String) async throws -> Profile {
        guard let handle = Username.normalize(raw) else { throw CommunityError.usernameInvalid }
        let mine = try await me()
        let currentHolder = try await holder(of: handle)
        // A handle already mine is kept as it is: the filters below are for
        // NEW claims, so someone who took "team" before those rules existed
        // can still change their display name (2026-09-30).
        let keepsOwn = currentHolder == mine
        guard ContentFilter.check(keepsOwn ? [displayName] : [handle, displayName]) == .ok else {
            throw CommunityError.contentBlocked
        }
        // A handle is one word, so it gets the substring check too
        // ("fuckyou" is a single word in no list), and handles that would
        // read as 808 or its staff are never handed out (Melvin, 2026-09-29).
        // Enforced here, not only on the screen, so no door can skip it.
        if !keepsOwn {
            switch ContentFilter.checkHandle(handle) {
            case .blocked: throw CommunityError.contentBlocked
            case .reserved: throw CommunityError.usernameTaken
            case .ok: break
            }
        }

        var reservedNow = false
        switch currentHolder {
        case .some(let owner) where owner != mine:
            throw CommunityError.usernameTaken
        case .some:
            break   // already mine
        case .none:
            reservedNow = true
            let reservation = CKRecord(recordType: CommunityType.username,
                                       recordID: CKRecord.ID(recordName: CommunityNames.username(handle)))
            reservation["profile"] = CommunityRecordValue.reference(mine).ckValue
            do {
                _ = try await db.create(reservation)
            } catch CommunityError.alreadyExists {
                throw CommunityError.usernameTaken
            }
        }

        let record = try await db.fetch(mine) ?? CKRecord(recordType: CommunityType.profile,
                                                          recordID: CKRecord.ID(recordName: mine))
        var profile = Profile(record: record) ?? Profile(id: mine, username: handle, displayName: displayName)
        let previous = profile.username
        profile.username = handle
        profile.displayName = displayName
        profile.apply(to: record)
        let saved: CKRecord
        do {
            saved = try await db.save(record)
        } catch {
            // Give back a handle reserved in this call, or a failed save would
            // hold it forever against a profile that never carried it.
            if reservedNow { try? await db.delete(CommunityNames.username(handle)) }
            throw error
        }

        if !previous.isEmpty, previous != handle {
            try? await db.delete(CommunityNames.username(previous))
        }
        births[mine] = nil
        return Profile(record: saved) ?? profile
    }

    /// Sets or clears the profile photo. `url` is a prepared JPEG
    /// (`PostPhoto.prepare`); nil removes the photo.
    @discardableResult
    func setAvatar(_ url: URL?) async throws -> Profile {
        let mine = try await me()
        guard let record = try await db.fetch(mine) else { throw CommunityError.noProfile }
        record["avatar"] = url.map { CKAsset(fileURL: $0) }
        let saved = try await db.save(record)
        guard let profile = Profile(record: saved) else { throw CommunityError.noProfile }
        return profile
    }

    /// Records that a first session exists, for the invite reward. Called
    /// once; later calls are no-ops so the date stays the first one.
    func markFirstSession(at date: Date = Date()) async throws {
        let mine = try await me()
        guard let record = try await db.fetch(mine), record["firstSessionAt"] == nil else { return }
        record["firstSessionAt"] = date as NSDate
        _ = try await db.save(record)
    }

    /// Publishes how often I meditate (`CommunityModel.syncPracticeStats`
    /// computes it from every local session and calls this after one lands
    /// and on each app foreground). Only these five fields change; everything
    /// else on the profile record is left exactly as it was.
    @discardableResult
    func updatePracticeStats(_ stats: PracticeStats) async throws -> Profile {
        let mine = try await me()
        guard let record = try await db.fetch(mine) else { throw CommunityError.noProfile }
        stats.apply(to: record)
        let saved = try await db.save(record)
        guard let profile = Profile(record: saved) else { throw CommunityError.noProfile }
        return profile
    }

    // MARK: - Finding people

    /// Someone's profile page. nil for anyone I blocked.
    func profile(named recordName: String) async throws -> Profile? {
        let mine = try await me()
        if recordName != mine, try await iBlocked(recordName) { return nil }
        guard let record = try await db.fetch(recordName) else { return nil }
        return Profile(record: record)
    }

    /// Finds a profile by username. nil for anyone I blocked. (The person I
    /// blocked can still find me: see the header.)
    func search(username raw: String) async throws -> Profile? {
        guard let handle = Username.normalize(raw), let owner = try await holder(of: handle) else { return nil }
        guard let record = try await db.fetch(owner), let profile = Profile(record: record),
              profile.username == handle else { return nil }
        let mine = try await me()
        if profile.id != mine, try await iBlocked(profile.id) { return nil }
        return profile
    }

    /// Profiles for the lists the model caches. Anyone I blocked comes back
    /// as a name only (`nameOnly`), which is all my Blocked list needs, so
    /// their practice summary never reaches my screen.
    func profiles(named names: [String]) async throws -> [Profile] {
        guard !names.isEmpty else { return [] }
        let blocked = try await myBlockedSet()
        var out: [Profile] = []
        for name in names {
            if let record = try await db.fetch(name), let p = Profile(record: record) {
                out.append(blocked.contains(name) ? Self.nameOnly(p) : p)
            }
        }
        return out
    }

    /// What I may still hold about someone I blocked: their name and handle,
    /// for the Blocked list and its Unblock button. No photo, no practice
    /// summary, no first-session date, no "practicing since".
    static func nameOnly(_ p: Profile) -> Profile {
        Profile(id: p.id, username: p.username, displayName: p.displayName)
    }

    // MARK: - Friends

    enum Relationship: Equatable { case none, requested, incoming, friends }

    /// Edges I wrote (my requests and my half of every friendship).
    private func edgeListFromMe() async throws -> [FriendEdge] {
        let mine = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.edge,
                                                        filters: [.equals("from", .reference(mine))], limit: 500))
        return try await live(records.filter { authored($0, by: "from") })
    }

    /// Edges written towards me (requests to me and their half of friendships).
    private func edgeListToMe() async throws -> [FriendEdge] {
        let mine = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.edge,
                                                        filters: [.equals("to", .reference(mine))], limit: 500))
        return try await live(records.filter { authored($0, by: "from") })
    }

    private func edgesFromMe() async throws -> Set<String> { Set(try await edgeListFromMe().map(\.to)) }
    private func edgesToMe() async throws -> Set<String> { Set(try await edgeListToMe().map(\.from)) }

    /// Where I stand with everyone, read once: the edges both ways, and the
    /// friendships an invite code made (`codeFriends`).
    private func standing() async throws -> (out: Set<String>, inn: Set<String>, code: Set<String>) {
        async let o = edgeListFromMe()
        async let i = edgeListToMe()
        let (out, inn) = try await (o, i)
        let code = try await codeFriends(out: out, inn: inn)
        return (Set(out.map(\.to)), Set(inn.map(\.from)), code)
    }

    // MARK: Edges that outlived a profile

    /// The edges that still mean something. **An edge belongs to the two
    /// profiles that existed when it was written** (found on two phones,
    /// 2026-10-01). Deleting an account deletes only the edges that person
    /// wrote; the other side's half stays, because only its writer may
    /// delete it. A profile is named after its iCloud user, so a new profile
    /// made after a deletion has the SAME name, and that old half then met
    /// the new person's first request and read as a friendship nobody
    /// accepted. So an edge written before either of its profiles came into
    /// being is ignored, and one I wrote is deleted on the spot (best
    /// effort). A profile that does not exist at all leaves the edge alone,
    /// as before: every screen already treats an unknown person as unknown.
    private func live(_ records: [CKRecord]) async throws -> [FriendEdge] {
        let mine = try await me()
        var out: [FriendEdge] = []
        for record in records {
            guard let edge = FriendEdge(record: record) else { continue }
            let written = record.creationDate ?? edge.createdAt
            let from = try await born(edge.from), to = try await born(edge.to)
            let outlived = (from.map { $0 > written } ?? false) || (to.map { $0 > written } ?? false)
            if !outlived {
                out.append(edge)
            } else if edge.from == mine, to.map({ $0 > written }) == true {
                // Only when THEY are the newer profile: a request I am
                // sending while my own profile is being made is never lost.
                try? await db.delete(edge.id)
            }
        }
        return out
    }

    /// When a profile came into being, nil when it does not exist. CloudKit's
    /// own creation date where there is one (no device clock can skew it),
    /// the profile's `createdAt` otherwise. Remembered for a few seconds, so
    /// one refresh, which reads edges three ways at once, fetches each
    /// person once.
    private func born(_ profile: String) async throws -> Date? {
        if let known = births[profile], Date().timeIntervalSince(known.at) < 15 { return known.born }
        let record = try await db.fetch(profile)
        let born = record.map { $0.creationDate ?? ($0["createdAt"] as? Date) ?? .distantPast }
        births[profile] = (born, Date())
        return born
    }
    private var births: [String: (born: Date?, at: Date)] = [:]

    #if DEBUG
    /// For tests that delete and re-make a profile inside the few seconds a
    /// date is remembered, which on a phone takes minutes.
    func forgetProfileDates() { births = [:] }
    #endif

    /// `.none` for anyone I blocked, whatever edges exist: a request of theirs
    /// never reads as `.incoming`, so their page never offers Accept.
    func relationship(with other: String) async throws -> Relationship {
        if try await iBlocked(other) { return .none }
        let s = try await standing()
        if s.code.contains(other) { return .friends }
        let out = s.out.contains(other)
        let back = s.inn.contains(other)
        switch (out, back) {
        case (true, true):   return .friends
        case (true, false):  return .requested
        case (false, true):  return .incoming
        case (false, false): return .none
        }
    }

    /// The facts the invite reward reads, one per friend: whether my edge is
    /// the older one (I asked, they accepted) and whether their profile shows
    /// a first session.
    func friendFacts() async throws -> [InviteReward.FriendFact] {
        let mine = try await me()
        let out = try await db.query(CommunityQuery(type: CommunityType.edge,
                                                    filters: [.equals("from", .reference(mine))], limit: 500))
        let inn = try await db.query(CommunityQuery(type: CommunityType.edge,
                                                    filters: [.equals("to", .reference(mine))], limit: 500))
        let sent = Dictionary(out.filter { authored($0, by: "from") }.compactMap(FriendEdge.init(record:))
                                .map { ($0.to, $0.createdAt) }, uniquingKeysWith: { a, _ in a })
        let received = Dictionary(inn.filter { authored($0, by: "from") }.compactMap(FriendEdge.init(record:))
                                    .map { ($0.from, $0.createdAt) }, uniquingKeysWith: { a, _ in a })
        // Someone who joined with MY code was brought by me, whichever edge
        // landed first (mine is written after theirs, by `answerCodeJoins`).
        let myCodes = try await myProfile()?.allInviteCodes ?? []
        let joinedWithMyCode = Set(inn.filter { authored($0, by: "from") }.compactMap(FriendEdge.init(record:))
                                     .filter { myCodes.contains($0.viaCode ?? "") }.map(\.from))
        // And the reverse: someone whose code I joined with was not brought
        // by me, though my edge to them is the older one.
        var joinedTheirCode = Set<String>()
        for e in try await edgeListFromMe() {
            if let code = e.viaCode, try await codeOwner(code) == e.to { joinedTheirCode.insert(e.to) }
        }
        var facts: [InviteReward.FriendFact] = []
        for id in try await friends() where !joinedTheirCode.contains(id) {
            let profile = try await db.fetch(id).flatMap(Profile.init(record:))
            if joinedWithMyCode.contains(id), let joinedAt = received[id] {
                let satAfter = profile?.firstSessionAt.map { $0 >= joinedAt } ?? false
                facts.append(.init(id: id, iAskedFirst: true, hasFirstSession: satAfter))
                continue
            }
            guard let mineAt = sent[id], let theirsAt = received[id] else { continue }
            // "Brought" means they sat for the first time AFTER I asked.
            // Without this, adding someone who has practised for months paid
            // out as if I had brought them, and could be farmed.
            let satAfterAsked = profile?.firstSessionAt.map { $0 >= mineAt } ?? false
            facts.append(.init(id: id, iAskedFirst: mineAt < theirsAt, hasFirstSession: satAfterAsked))
        }
        return facts
    }

    /// Following and followers for ANY profile, mine or someone else's.
    ///
    /// No new record type and no schema change: the edge has always been
    /// directional (`from` asked, `to` was asked), so "following" is the
    /// edges a person wrote and "followers" the edges written at them. A
    /// mutual pair is a friendship, which is why the two numbers differ only
    /// by the requests either side has not answered. Anyone I blocked is left
    /// out of both lists, and a person I blocked has no lists at all for me.
    /// (Only MY blocks: nobody else's are readable.)
    ///
    /// For my OWN profile the model already holds the lists and does this
    /// arithmetic without a query (`CommunityModel.follow`).
    /// Anyone's friends: people with edges in both directions, which means
    /// one asked and the other accepted. A request nobody answered is not a
    /// friendship and is counted nowhere on a profile (Aziz, 2026-10-01:
    /// "just friends ... only if they accept we are friends").
    func friends(of person: String) async throws -> [String] {
        let (followers, following) = try await follows(of: person)
        return Set(followers).intersection(following).sorted()
    }

    func followCounts(of person: String) async throws -> (followers: Int, following: Int) {
        let (followers, following) = try await follows(of: person)
        return (followers.count, following.count)
    }

    /// The two lists behind `followCounts`.
    func follows(of person: String) async throws -> (followers: [String], following: [String]) {
        let blocked = try await myBlockedSet()
        if blocked.contains(person) { return ([], []) }
        async let outRecords = db.query(CommunityQuery(type: CommunityType.edge,
                                                       filters: [.equals("from", .reference(person))], limit: 500))
        async let inRecords = db.query(CommunityQuery(type: CommunityType.edge,
                                                      filters: [.equals("to", .reference(person))], limit: 500))
        let (out, inn) = try await (outRecords, inRecords)
        // `authored` cannot vouch for someone else's edges the way it does
        // for mine (only CloudKit's creator field proves an author, and it
        // names the edge's own writer), so an edge counts when its writer
        // wrote it: `from` is the author by construction of the record name.
        // And only while both profiles it joined still exist (`live`).
        let following = Set(try await live(out).filter { $0.from == person }.map(\.to))
        let followers = Set(try await live(inn).filter { $0.to == person }.map(\.from))
        return (followers.subtracting(blocked).sorted(), following.subtracting(blocked).sorted())
    }

    /// Profile record names of everyone with edges in BOTH directions, minus
    /// anyone I blocked.
    ///
    /// Someone who blocked ME drops out without my app reading their block:
    /// blocking deleted the edge they wrote towards me, so the pair is no
    /// longer mutual.
    func friends() async throws -> [String] {
        let s = try await standing()
        let mutual = s.out.intersection(s.inn).union(s.code)
        let blocked = try await myBlockedSet()
        return mutual.subtracting(blocked).sorted()
    }

    /// People who asked me and whom I have not answered, minus anyone I
    /// blocked: a request from someone I blocked never arrives.
    func incomingRequests() async throws -> [String] {
        let s = try await standing()
        let pending = s.inn.subtracting(s.out).subtracting(s.code)
        let blocked = try await myBlockedSet()
        return pending.subtracting(blocked).sorted()
    }

    /// People I asked who have not answered, minus anyone I blocked (blocking
    /// deletes my edge; this covers a block whose edge delete failed).
    ///
    /// Someone who blocked me stays here, as a request nobody answers. My app
    /// cannot read their block, and that is the point.
    func sentRequests() async throws -> [String] {
        let s = try await standing()
        let pending = s.out.subtracting(s.inn).subtracting(s.code)
        let blocked = try await myBlockedSet()
        return pending.subtracting(blocked).sorted()
    }

    /// Ask, or accept: both are "write my edge towards them". Refused towards
    /// anyone I blocked, so I can never accept a blocked person's request.
    ///
    /// NOT refused when the other person blocked me: my app cannot know. My
    /// edge is written, and their app never shows it (see the header).
    func sendRequest(to other: String) async throws {
        let mine = try await me()
        guard other != mine else { return }
        if try await iBlocked(other) { throw CommunityError.blocked }
        // Already asked (or already friends): leave the edge alone. Re-saving
        // would reset `createdAt`, which decides who asked first and so who
        // earns the invite reward.
        if try await db.fetch(CommunityNames.edge(from: mine, to: other)) != nil { return }
        let edge = FriendEdge(from: mine, to: other)
        let record = CKRecord(recordType: CommunityType.edge, recordID: CKRecord.ID(recordName: edge.id))
        edge.apply(to: record)
        _ = try await db.save(record)
    }

    func accept(_ other: String) async throws { try await sendRequest(to: other) }

    /// Remove a friend, decline a request, or withdraw one: all are "delete
    /// my edge towards them". Their edge, if any, is theirs to keep or drop.
    func removeFriend(_ other: String) async throws {
        let mine = try await me()
        try await db.delete(CommunityNames.edge(from: mine, to: other))
    }

    // MARK: - Invite codes (2026-10-18)

    /// Who owns a code, nil when nobody does. Only a reservation its owner
    /// really wrote counts (`authored`), so nobody can claim to be someone
    /// else's code. Remembered for the session: a code never changes owner.
    private func codeOwner(_ code: String) async throws -> String? {
        if let known = codeOwners[code] { return known }
        guard let record = try await db.fetch(CommunityNames.inviteCode(code)),
              authored(record, by: "profile"),
              let owner = (record["profile"] as? CKRecord.Reference)?.recordID.recordName else { return nil }
        codeOwners[code] = owner
        return owner
    }
    private var codeOwners: [String: String] = [:]

    /// How many of my codes keep working. The oldest beyond this are let go.
    static let keptInviteCodes = 100

    /// A NEW invite code, every time (Aziz, 2026-10-18: "each time we send an
    /// invite code it's a different one"). Reserved by record NAME like a
    /// username (a fetch needs no index), CREATED so two people can never
    /// hold one code, then added to my profile's list, so every code I have
    /// ever sent still finds me.
    func newInviteCode() async throws -> String {
        let mine = try await me()
        guard let record = try await db.fetch(mine), let profile = Profile(record: record),
              !profile.username.isEmpty else { throw CommunityError.noProfile }
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<12 {
            let code = InviteCode.make(username: profile.username, using: &rng)
            let reservation = CKRecord(recordType: CommunityType.inviteCode,
                                       recordID: CKRecord.ID(recordName: CommunityNames.inviteCode(code)))
            reservation["profile"] = CommunityRecordValue.reference(mine).ckValue
            do {
                _ = try await db.create(reservation)
            } catch CommunityError.alreadyExists {
                continue
            }
            var codes = profile.inviteCodes
            if codes.isEmpty, let old = profile.inviteCode { codes.append(old) }
            codes.append(code)
            let dropped = codes.count > Self.keptInviteCodes ? Array(codes.prefix(codes.count - Self.keptInviteCodes)) : []
            codes = Array(codes.suffix(Self.keptInviteCodes))
            record["inviteCode"] = code
            record["inviteCodes"] = codes
            do {
                _ = try await db.save(record)
            } catch {
                try? await db.delete(CommunityNames.inviteCode(code))
                throw error
            }
            codeOwners[code] = mine
            for old in dropped {
                try? await db.delete(CommunityNames.inviteCode(old))
                codeOwners[old] = nil
            }
            return code
        }
        throw CommunityError.alreadyExists
    }

    /// The person a code belongs to, or nil when it is nobody's, theirs no
    /// longer (their profile carries a different code), or someone I blocked.
    /// Works before I have a profile: onboarding looks codes up this way.
    func inviter(forCode raw: String) async throws -> Profile? {
        guard let code = InviteCode.normalize(raw), let owner = try await codeOwner(code),
              let profile = try await db.fetch(owner).flatMap(Profile.init(record:)),
              profile.allInviteCodes.contains(code), !profile.username.isEmpty else { return nil }
        if try await iBlocked(owner) { return nil }
        return profile
    }

    /// Join with a code: my edge to its owner, carrying the code, which makes
    /// us friends at once (`codeFriends`). Needs my profile. An edge I had
    /// already written (a request they never answered) gains the code.
    @discardableResult
    func redeem(code raw: String, myName: String) async throws -> Profile {
        let mine = try await me()
        guard let code = InviteCode.normalize(raw),
              let inviter = try await inviter(forCode: code) else { throw CommunityError.inviteCodeUnknown }
        guard inviter.id != mine else { throw CommunityError.inviteCodeIsYours }
        guard try await db.fetch(mine) != nil else { throw CommunityError.noProfile }
        let name = CommunityNames.edge(from: mine, to: inviter.id)
        let record = try await db.fetch(name)
            ?? CKRecord(recordType: CommunityType.edge, recordID: CKRecord.ID(recordName: name))
        var edge = FriendEdge(record: record) ?? FriendEdge(from: mine, to: inviter.id)
        edge.viaCode = code
        edge.fromName = myName
        edge.apply(to: record)
        _ = try await db.save(record)
        return inviter
    }

    /// Friendships an invite code made, with one edge so far: someone who
    /// joined with MY code (their edge carries it), and the owner of a code
    /// I joined with (verified against the reservation, so a forged code on
    /// my own edge proves nothing). The owner's app writes its half too
    /// (`answerCodeJoins`); until it runs, this is what makes them friends.
    ///
    /// **Only until the owner's app has answered** (`Profile.answeredJoins`).
    /// After that the two edges carry the friendship like any other, so the
    /// owner removing or blocking the joiner sticks, on both phones: the
    /// code on the joiner's edge stops counting the moment they are answered.
    private func codeFriends(out: [FriendEdge], inn: [FriendEdge]) async throws -> Set<String> {
        let mine = try await me()
        var friends = Set<String>()
        let joiners = inn.filter { $0.viaCode != nil }
        if !joiners.isEmpty, let profile = try await myProfile() {
            let answered = Set(profile.answeredJoins)
            let myCodes = profile.allInviteCodes
            for e in joiners where myCodes.contains(e.viaCode ?? "") && !answered.contains(e.from) { friends.insert(e.from) }
        }
        for e in out {
            guard let code = e.viaCode, try await codeOwner(code) == e.to else { continue }
            let owner = try await db.fetch(e.to).flatMap(Profile.init(record:))
            if owner?.answeredJoins.contains(mine) != true { friends.insert(e.to) }
        }
        return friends
    }

    /// Writes my half for everyone who joined with my code and does not have
    /// it yet, so the friendship looks like any other to everyone else
    /// (`friends(of:)` reads both edges). Returns who joined, new or not, so
    /// the friends list can tag them.
    func answerCodeJoins() async throws -> Set<String> {
        let mine = try await me()
        guard let record = try await db.fetch(mine), let profile = Profile(record: record) else { return [] }
        let myCodes = profile.allInviteCodes
        guard !myCodes.isEmpty else { return [] }
        let answered = Set(profile.answeredJoins)
        let joiners = Set(try await edgeListToMe().filter { myCodes.contains($0.viaCode ?? "") }.map(\.from))
        let blocked = try await myBlockedSet()
        // Each joiner is answered ONCE: someone removed or blocked after that
        // is never written back.
        var nowAnswered = answered
        for id in joiners.subtracting(answered).subtracting(blocked) {
            do {
                try await sendRequest(to: id)
                nowAnswered.insert(id)
            } catch { continue }
        }
        if nowAnswered != answered {
            // Fetched again: the copy above may be seconds old, and saving
            // it would roll back practice stats or a photo saved meanwhile.
            let fresh = try await db.fetch(mine) ?? record
            let already = Set((fresh["answeredJoins"] as? [String]) ?? [])
            fresh["answeredJoins"] = already.union(nowAnswered).sorted()
            _ = try await db.save(fresh)
        }
        return joiners.subtracting(blocked)
    }

    /// The push for someone joining with my code, once I have one.
    func subscribeToCodeJoins() async {
        guard let mine = try? await me(), let codes = try? await myProfile()?.allInviteCodes,
              !codes.isEmpty else { return }
        await db.ensureCodeJoinSubscription(me: mine, codes: codes.sorted())
    }

    // MARK: - Meditating together

    /// My halves of every goal (invites I sent and answers I gave).
    private func myGoalHalves() async throws -> [GoalHalf] {
        let mine = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.goalMember,
                                                        filters: [.equals("member", .reference(mine))], limit: 200))
        return records.filter { authored($0, by: "member") }.compactMap(GoalHalf.init(record:))
    }

    /// Halves other people wrote naming me as their partner: invites to me,
    /// and the answers to mine. Only ones their writer really wrote.
    private func goalHalvesToMe() async throws -> [GoalHalf] {
        let mine = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.goalMember,
                                                        filters: [.equals("partner", .reference(mine))], limit: 200))
        return records.filter { authored($0, by: "member") }.compactMap(GoalHalf.init(record:))
    }

    /// Every shared goal I am in or have been asked to join, as pairs, minus
    /// anything with someone I blocked, and minus any from somebody who is
    /// not (or no longer) my friend: a goal is between friends.
    /// `friends` is passed in so one refresh reads the edges once.
    func goals(friends: Set<String>) async throws -> [GoalPair] {
        let mine = try await me()
        async let a = myGoalHalves()
        async let b = goalHalvesToMe()
        let (my, theirs) = try await (a, b)
        let blocked = try await myBlockedSet()
        var byGoal: [String: (mine: GoalHalf?, theirs: GoalHalf?)] = [:]
        for h in my { byGoal[h.goal, default: (nil, nil)].mine = h }
        // Only a half that names the same pair as mine (or the only half).
        for h in theirs {
            if let m = byGoal[h.goal]?.mine, m.partner != h.member { continue }
            byGoal[h.goal, default: (nil, nil)].theirs = h
        }
        return byGoal.values.compactMap { GoalHalf.pair(mine: $0.mine, theirs: $0.theirs, me: mine) }
            .filter { friends.contains($0.partner) && !blocked.contains($0.partner) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Ask a friend to meditate together. Returns the new goal's id.
    @discardableResult
    func inviteGoal(to partner: String, target: Int, myName: String) async throws -> String {
        let mine = try await me()
        guard partner != mine else { throw CommunityError.blocked }
        if try await iBlocked(partner) { throw CommunityError.blocked }
        let goal = UUID().uuidString
        let half = GoalHalf(goal: goal, member: mine, partner: partner, kind: .invite,
                            target: min(max(target, 1), 7), fromName: myName)
        let record = CKRecord(recordType: CommunityType.goalMember, recordID: CKRecord.ID(recordName: half.id))
        half.apply(to: record)
        _ = try await db.save(record)
        return goal
    }

    /// Say yes. `today` (my local day key) becomes the first day of week one
    /// for both of us.
    func acceptGoal(_ goal: GoalPair, today: String, myName: String) async throws {
        try await answer(goal, kind: .accept, startDay: today, myName: myName)
    }

    /// "Not now". Their invite stays theirs; my answer ends it for both.
    func declineGoal(_ goal: GoalPair, myName: String) async throws {
        try await answer(goal, kind: .decline, startDay: nil, myName: myName)
    }

    private func answer(_ goal: GoalPair, kind: GoalHalf.Kind, startDay: String?, myName: String) async throws {
        let mine = try await me()
        if try await iBlocked(goal.partner) { throw CommunityError.blocked }
        let half = GoalHalf(goal: goal.id, member: mine, partner: goal.partner, kind: kind,
                            target: goal.target, startDay: startDay,
                            declinedAt: kind == .decline ? Date() : nil, fromName: myName)
        let record = CKRecord(recordType: CommunityType.goalMember, recordID: CKRecord.ID(recordName: half.id))
        half.apply(to: record)
        _ = try await db.save(record)
    }

    /// End a goal for both of us, or withdraw an invite nobody answered.
    /// A withdrawn invite is deleted outright; a running goal keeps my half
    /// with `endedAt`, so their app learns it is over.
    func endGoal(_ goal: GoalPair, myName: String) async throws {
        let mine = try await me()
        let name = CommunityNames.goalMember(goal: goal.id, member: mine)
        if goal.state == .waitingForThem {
            try await db.delete(name)
            return
        }
        if let record = try await db.fetch(name), var half = GoalHalf(record: record) {
            half.endedAt = Date()
            half.apply(to: record)
            _ = try await db.save(record)
        } else {
            // An invite to me I never answered: end it by answering.
            let half = GoalHalf(goal: goal.id, member: mine, partner: goal.partner, kind: .decline,
                                target: goal.target, declinedAt: Date(), fromName: myName)
            let record = CKRecord(recordType: CommunityType.goalMember, recordID: CKRecord.ID(recordName: half.id))
            half.apply(to: record)
            _ = try await db.save(record)
        }
    }

    /// Publishes my qualifying days on my half of one goal. A no-op when
    /// nothing changed, so a foreground tick costs a fetch at most.
    func publishGoalDays(goal: String, days: [GoalDay]) async throws {
        let mine = try await me()
        guard let record = try await db.fetch(CommunityNames.goalMember(goal: goal, member: mine)),
              var half = GoalHalf(record: record), half.endedAt == nil, half.days != days else { return }
        half.days = days
        half.apply(to: record)
        _ = try await db.save(record)
    }

    /// Nudge (or high-five) a friend, once a day. Returns false when today's
    /// was already sent.
    @discardableResult
    func nudge(_ other: String, kind: Nudge.Kind, today: String, myName: String) async throws -> Bool {
        let mine = try await me()
        if try await iBlocked(other) { throw CommunityError.blocked }
        let name = CommunityNames.nudge(from: mine, to: other, day: today)
        if try await db.fetch(name) != nil { return false }
        let n = Nudge(from: mine, to: other, day: today, kind: kind, fromName: myName)
        let record = CKRecord(recordType: CommunityType.nudge, recordID: CKRecord.ID(recordName: name))
        n.apply(to: record)
        _ = try await db.save(record)
        return true
    }

    /// Tells a friend we just finished a week together (2026-10-27): a
    /// Nudge of kind `week`, which their phone's subscription turns into a
    /// push, "You and Melvin finished this week's goal together". One per
    /// week: a second call finds the first and sends nothing.
    func announceWeek(to other: String, first: String, myName: String) async throws {
        let mine = try await me()
        if try await iBlocked(other) { return }
        let name = CommunityNames.weekDone(from: mine, to: other, first: first)
        if try await db.fetch(name) != nil { return }
        let n = Nudge(from: mine, to: other, day: Nudge.weekRecordDay, kind: .week, fromName: myName)
        let record = CKRecord(recordType: CommunityType.nudge, recordID: CKRecord.ID(recordName: name))
        n.apply(to: record)
        _ = try await db.save(record)
    }

    /// Whether I already nudged them today.
    func nudged(_ other: String, today: String) async throws -> Bool {
        try await db.fetch(CommunityNames.nudge(from: try await me(), to: other, day: today)) != nil
    }

    /// Nudges and high fives sent to me, newest first, minus anyone I blocked.
    func nudgesToMe(limit: Int = 30) async throws -> [Nudge] {
        let mine = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.nudge,
                                                        filters: [.equals("to", .reference(mine))],
                                                        sortField: "createdAt", ascending: false, limit: limit))
        let blocked = try await myBlockedSet()
        return records.filter { authored($0, by: "from") }.compactMap(Nudge.init(record:))
            .filter { !blocked.contains($0.from) && $0.kind != .week }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Asks CloudKit to push an alert for an invite, an acceptance and a
    /// nudge addressed to me (no-op where the database cannot).
    func subscribeToGoalNews() async {
        guard let mine = try? await me() else { return }
        await db.ensureGoalSubscriptions(me: mine)
    }

    // MARK: - Posts

    /// One photo or video to upload, as the session's own page prepares it
    /// (`PostMediaPrep.draft(for:)`). `fileURL` is the full-resolution file
    /// (the prepared JPEG, or the exported movie); `posterURL` is a small
    /// JPEG for the feed's strip, so scrolling it never has to download a
    /// whole video, or a full-size photo, just to draw a thumbnail.
    struct DraftMedia: Equatable {
        var kind: Post.PostMedia.Kind
        /// width / height of the ORIGINAL image or video frame.
        var aspect: Double
        var fileURL: URL
        var posterURL: URL
    }

    /// The numbers a post carries, handed in by the results screen. **No
    /// score** (2026-09-23, the founders' call): it is derived from heart
    /// rate, this is the public database, and 5.1.3(ii) forbids storing
    /// personal health information in iCloud with no consent exception.
    /// Nothing measured is accepted by this signature on purpose.
    struct Draft: Equatable {
        var minutes: Int
        var streak: Int
        var technique: String?
        var caption: String
        /// Photos and videos, in the order they'll show. **nil leaves the
        /// post's existing media untouched** (an edit that only changes the
        /// caption); an EMPTY array clears it. The session's page always
        /// knows its own full list, so it passes one or the other on purpose
        /// rather than relying on the "untouched" default.
        var media: [DraftMedia]? = nil
        var practicedAt: Date
        /// The session this post is. When set, the post's record name is
        /// derived from it, so saving the same session again UPDATES its post
        /// and switching it to Only you deletes exactly that one.
        var sessionID: String? = nil
        var title: String = ""
        var sound: String? = nil
    }

    static func postID(forSession sessionID: String) -> String { "post-" + sessionID }

    /// The inverse of `postID(forSession:)`: the session a post's record name
    /// derives from, when it does. nil for a post with no session behind it
    /// (a random UUID id, e.g. one made before that rule, or one whose id is
    /// otherwise not a session's). Edit post reads this to decide whether
    /// there is a session page here to open at all.
    static func sessionID(forPost postID: String) -> UUID? {
        guard postID.hasPrefix("post-") else { return nil }
        return UUID(uuidString: String(postID.dropFirst("post-".count)))
    }

    static let captionLimit = 140
    static let titleLimit = 60

    /// Takes a session's post down (it went to Only you). No-op when it was
    /// never posted.
    func unpost(session sessionID: String) async throws {
        try await db.delete(Self.postID(forSession: sessionID))
    }

    @discardableResult
    func post(_ draft: Draft) async throws -> Post {
        let caption = String(draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.captionLimit))
        let id = draft.sessionID.map(Self.postID(forSession:)) ?? UUID().uuidString
        // Two independent round trips, run together rather than one after the
        // other (2026-09-27: posting "loaded like forever").
        async let me = me()
        async let lookup = db.fetch(id)
        let mine = try await me
        let existing = try await lookup
        guard ContentFilter.check([draft.title, draft.caption]) == .ok else { throw CommunityError.contentBlocked }
        let post = Post(id: id, author: mine, minutes: draft.minutes, streak: draft.streak,
                        technique: draft.technique, caption: caption,
                        practicedAt: draft.practicedAt,
                        createdAt: existing?["createdAt"] as? Date ?? Date(),
                        title: String(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.titleLimit)),
                        sound: draft.sound)
        let record = existing ?? CKRecord(recordType: CommunityType.post, recordID: CKRecord.ID(recordName: id))
        post.apply(to: record)
        // An update with no media (an edit that only changes the caption,
        // say) keeps whatever the post already has; the old single-photo
        // field worked the same way. A non-nil, possibly empty, array always
        // replaces all four fields together so they never drift out of sync.
        if let media = draft.media {
            record["media"] = media.map { CKAsset(fileURL: $0.fileURL) }
            record["mediaPosters"] = media.map { CKAsset(fileURL: $0.posterURL) }
            record["mediaKinds"] = media.map { $0.kind.rawValue }
            record["mediaAspects"] = media.map { $0.aspect }
        }
        let saved = try await db.save(record)
        return Post(record: saved) ?? post
    }

    /// A post by record name, mine or a friend's. nil when it does not exist.
    func post(id: String) async throws -> Post? {
        _ = try await me()   // `authored` needs the current user to recognise my own records
        guard let record = try await db.fetch(id), authored(record, by: "author") else { return nil }
        return Post(record: record)
    }

    func deletePost(_ id: String) async throws {
        try await db.delete(id)
    }

    /// Deletes every post I've authored, and nothing else Friends knows about
    /// me (my profile, my friends, my reactions all stay). Used once, the day
    /// posting was removed from the app (Melvin, 2026-09-27: "get rid of the
    /// feed, no more posting with photos/videos") to take down what people
    /// had already shared — `CommunityModel.clearMyPostsIfNeeded` calls it.
    /// Reuses the same query-then-delete `deleteEverythingOfMine` already
    /// does for posts, rather than a second implementation of it.
    func deleteMyPosts() async throws {
        try await deleteMine(CommunityType.post, field: "author", retired: true)
    }

    /// Friends' posts and mine, most recently practiced first.
    func feed(limit: Int = 50) async throws -> [Post] {
        let mine = try await me()
        let authors = try await friends() + [mine]
        return try await posts(by: authors, limit: limit)
    }

    /// One person's posts, newest first. Empty for a stranger: the feed is
    /// for friends, and a profile page shows posts only once you are one.
    func posts(by author: String, limit: Int = 50) async throws -> [Post] {
        let mine = try await me()
        if author != mine {
            let friends = try await friends()
            guard friends.contains(author) else { return [] }
        }
        return try await posts(by: [author], limit: limit)
    }

    private func posts(by authors: [String], limit: Int) async throws -> [Post] {
        guard !authors.isEmpty else { return [] }
        var query = CommunityQuery(type: CommunityType.post,
                                   filters: [.isIn("author", authors.map { .reference($0) })])
        // By when the session was sat, not when it was posted: a session
        // posted a day late still belongs on its own day.
        query.sortField = "practicedAt"
        query.ascending = false
        query.limit = limit
        return try await db.query(query)
            .filter { authored($0, by: "author") }
            .compactMap(Post.init(record:))
            .sorted { $0.practicedAt > $1.practicedAt }
    }

    // MARK: - Reactions

    func react(to postID: String) async throws {
        let mine = try await me()
        let reaction = Reaction(post: postID, author: mine)
        let record = CKRecord(recordType: CommunityType.reaction, recordID: CKRecord.ID(recordName: reaction.id))
        reaction.apply(to: record)
        _ = try await db.save(record)
    }

    func unreact(to postID: String) async throws {
        let mine = try await me()
        try await db.delete(CommunityNames.reaction(post: postID, by: mine))
    }

    /// Reactor profile names for many posts in one query, keyed by post id.
    func reactions(for postIDs: [String]) async throws -> [String: [String]] {
        guard !postIDs.isEmpty else { return [:] }
        _ = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.reaction,
                                                        filters: [.isIn("post", postIDs.map { .reference($0) })],
                                                        limit: 1000))
        let blocked = try await myBlockedSet()
        var out: [String: [String]] = [:]
        for r in records.filter({ authored($0, by: "author") }).compactMap(Reaction.init(record:))
        where !blocked.contains(r.author) {
            out[r.post, default: []].append(r.author)
        }
        return out.mapValues { $0.sorted() }
    }

    /// Who reacted to a post, as profile record names, minus anyone I blocked.
    func reactors(to postID: String) async throws -> [String] {
        _ = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.reaction,
                                                        filters: [.equals("post", .reference(postID))], limit: 500))
        let blocked = try await myBlockedSet()
        return records.filter { authored($0, by: "author") }.compactMap(Reaction.init(record:))
            .map(\.author).filter { !blocked.contains($0) }.sorted()
    }

    // MARK: - Block and report

    /// Blocks someone, privately (see the header). Ends the friendship from
    /// my side (deletes the edge I wrote, today's behaviour kept), then writes
    /// one Block record under a random name, unless I already hold one.
    ///
    /// The edge goes FIRST, so a block can never exist with my edge still
    /// standing: that edge plus theirs would read as a friendship in THEIR
    /// app, which cannot see the block.
    func block(_ other: String) async throws {
        let mine = try await me()
        guard other != mine else { return }
        try await removeFriend(other)
        // One block per pair. The record name no longer says who it is about,
        // so a second save would be a second record, not an overwrite.
        if try await iBlocked(other) { return }
        let block = Block(from: mine, to: other)
        let record = CKRecord(recordType: CommunityType.block, recordID: CKRecord.ID(recordName: block.id))
        block.apply(to: record)
        _ = try await db.save(record)
    }

    /// Deletes every block I hold on them: normally one, but an old
    /// `block-<from>-<to>` record and a newer random one would both go.
    func unblock(_ other: String) async throws {
        for block in try await myBlocks() where block.to == other {
            try await db.delete(block.id)
        }
    }

    /// Everyone I blocked, for the Blocked list.
    func blockedByMe() async throws -> [String] {
        try await myBlockedSet().sorted()
    }

    /// The ONLY read of the Block type anywhere in the app: blocks I created,
    /// by `from == me`. The Block type is readable by its creator alone, and
    /// no code here may query `to == me` or fetch another person's block. A
    /// record naming me in `from` that someone else created is dropped by
    /// `authored` (and, with creator-only read, is never returned anyway).
    private func myBlocks() async throws -> [Block] {
        let mine = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.block,
                                                        filters: [.equals("from", .reference(mine))], limit: 500))
        return records.filter { authored($0, by: "from") }
            .compactMap(Block.init(record:))
            .filter { $0.from == mine }
    }

    private func myBlockedSet() async throws -> Set<String> {
        Set(try await myBlocks().map(\.to))
    }

    /// Whether I blocked them. Never whether they blocked me: that is theirs.
    private func iBlocked(_ other: String) async throws -> Bool {
        try await myBlockedSet().contains(other)
    }

    @discardableResult
    func report(_ target: String, as type: Report.Target, reason: String) async throws -> Report {
        let mine = try await me()
        let report = Report(reporter: mine, target: target, targetType: type,
                            reason: String(reason.prefix(500)))
        let record = CKRecord(recordType: CommunityType.report, recordID: CKRecord.ID(recordName: report.id))
        report.apply(to: record)
        _ = try await db.save(record)
        return report
    }

    // MARK: - Account deletion

    /// Deletes everything I've written to the PUBLIC database: every post I
    /// authored (its photo or video goes with the record), every reaction I
    /// gave, every friend edge and block I wrote, my username reservation,
    /// and my profile. Called once, when the person deletes their 808
    /// account — App Review 5.1.1(v): deleting an account has to delete what
    /// it published, not just sign the person out of it.
    ///
    /// **Best effort, not atomic.** Every category is attempted even after
    /// an earlier one throws: a friend's feed still carrying my posts
    /// because the FIRST query failed is worse than the same feed catching
    /// up on a retry. The first error, if any, is thrown at the end so the
    /// caller knows to try again (`CommunityModel.deleteAccountData` sets a
    /// pending flag on exactly that, and a launch task keeps retrying it
    /// until a run finishes clean).
    ///
    /// **What this deliberately leaves alone:** Report records (moderation
    /// keeps them, whoever they are about), and any edge or block someone
    /// ELSE wrote pointing at me — the public database only lets a record's
    /// creator modify it, so those stay theirs to keep (and another person's
    /// block is not even readable here: `myBlocks`). A friend whose
    /// account went through this simply stops resolving afterwards:
    /// `profile(named:)` returns nil for them, which every reader of
    /// `people[id]` already treats as "unknown" rather than a crash.
    func deleteEverythingOfMine() async throws {
        let mine = try await me()
        var firstError: Error?

        do { try await deleteMine(CommunityType.post, field: "author", retired: true) }
        catch { firstError = firstError ?? error }
        do { try await deleteMine(CommunityType.reaction, field: "author", retired: true) }
        catch { firstError = firstError ?? error }
        do { try await deleteMine(CommunityType.edge, field: "from") }
        catch { firstError = firstError ?? error }
        do { try await deleteMine(CommunityType.block, field: "from") }
        catch { firstError = firstError ?? error }
        // Meditating together (2026-10-14): my halves of every goal, with the
        // days they carry, and every nudge I sent. Tolerant like the retired
        // types: a container where either type was never created has nothing
        // of mine in it to delete.
        do { try await deleteMine(CommunityType.goalMember, field: "member", retired: true) }
        catch { firstError = firstError ?? error }
        do { try await deleteMine(CommunityType.nudge, field: "from", retired: true) }
        catch { firstError = firstError ?? error }
        do {
            // The username reservation is its own record, named by the
            // handle rather than by me, so it can only be found through the
            // profile's own `username` field.
            if let record = try await db.fetch(mine), let handle = Profile(record: record)?.username, !handle.isEmpty {
                try await db.delete(CommunityNames.username(handle))
            }
        } catch { firstError = firstError ?? error }
        do {
            // The invite code's reservation (2026-10-18), found the same way.
            for code in try await db.fetch(mine).flatMap(Profile.init(record:))?.allInviteCodes ?? [] {
                try await db.delete(CommunityNames.inviteCode(code))
                codeOwners[code] = nil
            }
        } catch { firstError = firstError ?? error }
        do { try await db.delete(mine) }
        catch { firstError = firstError ?? error }
        births = [:]

        if let firstError { throw firstError }
    }

    /// Deletes every record of `type` I created whose `field` names me — the
    /// query-then-delete shape shared by four of the six steps above.
    ///
    /// `retired` is for Post and Reaction, the types the app stopped writing
    /// when posting was removed (2026-09-27). **A query of one of them that
    /// fails for any reason but the network counts as nothing to delete**
    /// (Melvin, 2026-09-29, second pass of the pre-1.1 audit). A Production
    /// container whose Post or Reaction index was never created answers
    /// every such query with an error, and before this the account-deletion
    /// flag stayed set forever, retrying at every launch a deletion that
    /// could never finish. Nothing can have been written to a type that
    /// cannot be queried, so there is nothing there to leave behind. The
    /// four live types (profile, username, edges, blocks) still fail, and
    /// still retry, on any error.
    private func deleteMine(_ type: String, field: String, retired: Bool = false) async throws {
        let mine = try await me()
        let records: [CKRecord]
        do {
            records = try await db.query(CommunityQuery(type: type, filters: [.equals(field, .reference(mine))], limit: 500))
        } catch let error where retired && !Self.isTransient(error) {
            Self.log.notice("Treating \(type, privacy: .public) as empty: its query failed with \(String(describing: error), privacy: .public)")
            return
        }
        for record in records where authored(record, by: field) {
            try await db.delete(record.recordID.recordName)
        }
    }

    private static let log = Logger(subsystem: "com.lockout.meditate808", category: "friends")

    /// Errors that say "not now" rather than "not ever": no iCloud account
    /// yet, no network, CloudKit busy or rate-limiting. Worth retrying. A
    /// missing record type or index, or any other refusal, is not.
    static func isTransient(_ error: Error) -> Bool {
        if let community = error as? CommunityError { return community == .unavailable }
        if error is URLError { return true }
        guard let ck = error as? CKError else { return false }
        switch ck.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .notAuthenticated, .accountTemporarilyUnavailable, .operationCancelled,
             .serverResponseLost:
            return true
        default:
            return false
        }
    }
}
