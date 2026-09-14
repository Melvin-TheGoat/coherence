import Foundation
import CloudKit

/// Everything the Friends tab and the post composer do, over any
/// `CommunityDatabase`. No UI, no SwiftData; callers pass in what they know
/// (display name, the session's numbers) and get value types back.
///
/// Identity: the iCloud user record name, read once per store. The profile
/// record name is derived from it, so "me" is always `CommunityNames
/// .profile(user:)` and never needs a lookup.
///
/// Blocks are honoured on every read and write that could cross one: a blocked
/// person's posts, requests and profile vanish for the blocker, and the blocked
/// person cannot send a request to, react to, or view the blocker. Both
/// directions, because a block record is public and readable by both sides.
actor CommunityStore {
    private let db: CommunityDatabase
    private var cachedUser: String?

    init(database: CommunityDatabase) { self.db = database }

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
        return owner == nil || owner == mine
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

        switch try await holder(of: handle) {
        case .some(let owner) where owner != mine:
            throw CommunityError.usernameTaken
        case .some:
            break   // already mine
        case .none:
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
        let saved = try await db.save(record)

        if !previous.isEmpty, previous != handle {
            try? await db.delete(CommunityNames.username(previous))
        }
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

    // MARK: - Finding people

    func profile(named recordName: String) async throws -> Profile? {
        let mine = try await me()
        if recordName != mine, try await isBlocked(between: mine, and: recordName) { return nil }
        guard let record = try await db.fetch(recordName) else { return nil }
        return Profile(record: record)
    }

    func search(username raw: String) async throws -> Profile? {
        guard let handle = Username.normalize(raw), let owner = try await holder(of: handle) else { return nil }
        guard let record = try await db.fetch(owner), let profile = Profile(record: record),
              profile.username == handle else { return nil }
        let mine = try await me()
        if profile.id != mine, try await isBlocked(between: mine, and: profile.id) { return nil }
        return profile
    }

    func profiles(named names: [String]) async throws -> [Profile] {
        guard !names.isEmpty else { return [] }
        var out: [Profile] = []
        for name in names {
            if let record = try await db.fetch(name), let p = Profile(record: record) { out.append(p) }
        }
        return out
    }

    // MARK: - Friends

    enum Relationship: Equatable { case none, requested, incoming, friends }

    /// Edges I wrote (my requests and my half of every friendship).
    private func edgesFromMe() async throws -> Set<String> {
        let mine = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.edge,
                                                        filters: [.equals("from", .reference(mine))], limit: 500))
        return Set(records.compactMap(FriendEdge.init(record:)).map(\.to))
    }

    /// Edges written towards me (requests to me and their half of friendships).
    private func edgesToMe() async throws -> Set<String> {
        let mine = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.edge,
                                                        filters: [.equals("to", .reference(mine))], limit: 500))
        return Set(records.compactMap(FriendEdge.init(record:)).map(\.from))
    }

    func relationship(with other: String) async throws -> Relationship {
        let out = try await edgesFromMe().contains(other)
        let back = try await edgesToMe().contains(other)
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
        let sent = Dictionary(out.compactMap(FriendEdge.init(record:)).map { ($0.to, $0.createdAt) },
                              uniquingKeysWith: { a, _ in a })
        let received = Dictionary(inn.compactMap(FriendEdge.init(record:)).map { ($0.from, $0.createdAt) },
                                  uniquingKeysWith: { a, _ in a })
        var facts: [InviteReward.FriendFact] = []
        for id in try await friends() {
            guard let mineAt = sent[id], let theirsAt = received[id] else { continue }
            let profile = try await db.fetch(id).flatMap(Profile.init(record:))
            facts.append(.init(id: id, iAskedFirst: mineAt < theirsAt,
                               hasFirstSession: profile?.firstSessionAt != nil))
        }
        return facts
    }

    /// Profile record names of everyone with edges in BOTH directions, minus
    /// anyone blocked either way.
    func friends() async throws -> [String] {
        let mutual = try await edgesFromMe().intersection(edgesToMe())
        let blocked = try await blockedEitherWay()
        return mutual.subtracting(blocked).sorted()
    }

    /// People who asked me and whom I have not answered.
    func incomingRequests() async throws -> [String] {
        let pending = try await edgesToMe().subtracting(edgesFromMe())
        let blocked = try await blockedEitherWay()
        return pending.subtracting(blocked).sorted()
    }

    /// People I asked who have not answered.
    func sentRequests() async throws -> [String] {
        let pending = try await edgesFromMe().subtracting(edgesToMe())
        return pending.sorted()
    }

    /// Ask, or accept: both are "write my edge towards them". Refused across
    /// a block in either direction.
    func sendRequest(to other: String) async throws {
        let mine = try await me()
        guard other != mine else { return }
        if try await isBlocked(between: mine, and: other) { throw CommunityError.blocked }
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

    // MARK: - Posts

    /// The numbers a post carries, handed in by the results screen. Nothing
    /// measured beyond the score is accepted by this signature on purpose.
    struct Draft: Equatable {
        var score: Int
        var minutes: Int
        var streak: Int
        var technique: String?
        var caption: String
        var photoURL: URL?
        var practicedAt: Date
        /// The session this post is. When set, the post's record name is
        /// derived from it, so saving the same session again UPDATES its post
        /// and switching it to Only you deletes exactly that one.
        var sessionID: String? = nil
        var title: String = ""
        var sound: String? = nil
    }

    static func postID(forSession sessionID: String) -> String { "post-" + sessionID }

    static let captionLimit = 140
    static let titleLimit = 60

    /// Takes a session's post down (it went to Only you). No-op when it was
    /// never posted.
    func unpost(session sessionID: String) async throws {
        try await db.delete(Self.postID(forSession: sessionID))
    }

    @discardableResult
    func post(_ draft: Draft) async throws -> Post {
        let mine = try await me()
        let caption = String(draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.captionLimit))
        let id = draft.sessionID.map(Self.postID(forSession:)) ?? UUID().uuidString
        let existing = try await db.fetch(id)
        let post = Post(id: id, author: mine, score: draft.score, minutes: draft.minutes, streak: draft.streak,
                        technique: draft.technique, caption: caption, photoURL: draft.photoURL,
                        practicedAt: draft.practicedAt,
                        createdAt: existing?["createdAt"] as? Date ?? Date(),
                        title: String(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.titleLimit)),
                        sound: draft.sound)
        let record = existing ?? CKRecord(recordType: CommunityType.post, recordID: CKRecord.ID(recordName: id))
        // An update keeps a photo it already has unless a new one is given.
        let keptPhoto = draft.photoURL == nil ? record["photo"] : nil
        post.apply(to: record)
        if let keptPhoto { record["photo"] = keptPhoto }
        let saved = try await db.save(record)
        return Post(record: saved) ?? post
    }

    func deletePost(_ id: String) async throws {
        try await db.delete(id)
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
        return try await db.query(query).compactMap(Post.init(record:)).sorted { $0.practicedAt > $1.practicedAt }
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
        let records = try await db.query(CommunityQuery(type: CommunityType.reaction,
                                                        filters: [.isIn("post", postIDs.map { .reference($0) })],
                                                        limit: 1000))
        var out: [String: [String]] = [:]
        for r in records.compactMap(Reaction.init(record:)) { out[r.post, default: []].append(r.author) }
        return out.mapValues { $0.sorted() }
    }

    /// Who reacted to a post, as profile record names.
    func reactors(to postID: String) async throws -> [String] {
        let records = try await db.query(CommunityQuery(type: CommunityType.reaction,
                                                        filters: [.equals("post", .reference(postID))], limit: 500))
        return records.compactMap(Reaction.init(record:)).map(\.author).sorted()
    }

    // MARK: - Block and report

    func block(_ other: String) async throws {
        let mine = try await me()
        guard other != mine else { return }
        let block = Block(from: mine, to: other)
        let record = CKRecord(recordType: CommunityType.block, recordID: CKRecord.ID(recordName: block.id))
        block.apply(to: record)
        _ = try await db.save(record)
        // A block ends the friendship from my side too.
        try await removeFriend(other)
    }

    func unblock(_ other: String) async throws {
        let mine = try await me()
        try await db.delete(CommunityNames.block(from: mine, to: other))
    }

    func blockedByMe() async throws -> [String] {
        let mine = try await me()
        let records = try await db.query(CommunityQuery(type: CommunityType.block,
                                                        filters: [.equals("from", .reference(mine))], limit: 500))
        return records.compactMap(Block.init(record:)).map(\.to).sorted()
    }

    private func blockedEitherWay() async throws -> Set<String> {
        let mine = try await me()
        let out = try await db.query(CommunityQuery(type: CommunityType.block,
                                                    filters: [.equals("from", .reference(mine))], limit: 500))
        let inn = try await db.query(CommunityQuery(type: CommunityType.block,
                                                    filters: [.equals("to", .reference(mine))], limit: 500))
        return Set(out.compactMap(Block.init(record:)).map(\.to) + inn.compactMap(Block.init(record:)).map(\.from))
    }

    private func isBlocked(between a: String, and b: String) async throws -> Bool {
        if try await db.fetch(CommunityNames.block(from: a, to: b)) != nil { return true }
        if try await db.fetch(CommunityNames.block(from: b, to: a)) != nil { return true }
        return false
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
}
