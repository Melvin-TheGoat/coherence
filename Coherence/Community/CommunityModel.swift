import Foundation
import SwiftUI

/// The Friends tab's state: one object the screens observe, over a
/// `CommunityStore`. Every network call funnels through here so the views
/// stay declarative and the "what happens when CloudKit is unavailable"
/// answer lives in one place (`phase == .unavailable`).
@MainActor
final class CommunityModel: ObservableObject {

    enum Phase: Equatable {
        case loading
        /// No iCloud account, or a build with no CloudKit container. The tab
        /// shows an honest card and nothing else.
        case unavailable
        /// Signed in, no profile yet: the claim screen.
        case needsUsername
        case ready
    }

    @Published private(set) var phase: Phase = .loading
    /// Why `phase` is `.unavailable`, so the card can say what to do. A
    /// build with no CloudKit container (the side-by-side beta with
    /// NO_ICLOUD, a simulator) is not something the user can fix; a phone
    /// with no iCloud account is, and the card walks them through it.
    enum UnavailableReason: Equatable {
        case noContainer, noAccount
        /// iCloud answered and something else failed (a missing record type
        /// or index in this environment, a network error). Shown as what it
        /// is; telling this person to sign in to iCloud would be a lie.
        case failed(String)
    }
    @Published private(set) var unavailableReason: UnavailableReason = .noAccount
    @Published private(set) var profile: Profile?
    @Published private(set) var feed: [Post] = []
    /// Profiles by record name, for everyone the feed and the lists mention.
    @Published private(set) var people: [String: Profile] = [:]
    @Published private(set) var friends: [String] = []
    @Published private(set) var incoming: [String] = []
    @Published private(set) var sent: [String] = []
    /// People I blocked, for the Unblock list the block dialog points to.
    @Published private(set) var blocked: [String] = []
    /// Reactor profile names by post id.
    @Published private(set) var reactions: [String: [String]] = [:]
    @Published var errorText: String?

    /// The reward landing, shown once as a sheet by ContentView.
    @Published var rewardNews: RewardNews?

    struct RewardNews: Identifiable, Equatable {
        let friendName: String
        let remaining: Int
        var id: String { friendName + "\(remaining)" }
    }

    private(set) var store: CommunityStore?
    private(set) var myID: String?
    private var demo: Bool
    var ledger: RewardLedger?
    /// The earliest session on this phone, supplied by the app (the model
    /// has no SwiftData access of its own).
    var firstLocalSession: (() -> Date?)?
    /// Told when one of my posts is deleted from the feed, so the session it
    /// belonged to stops saying "Friends can see this". Receives the session
    /// id. Supplied by the app, which owns SwiftData.
    var onPostRemoved: ((UUID) -> Void)?

    init(store: CommunityStore?, demo: Bool = false, ledger: RewardLedger? = nil) {
        self.store = store; self.demo = demo; self.ledger = ledger
    }

    /// The production model: CloudKit if the process holds a container,
    /// otherwise a permanently unavailable tab.
    static func live() -> CommunityModel {
        CommunityModel(store: CloudKitCommunityDatabase.ifEntitled().map { CommunityStore(database: $0) })
    }

    /// The one instance the app injects: the live CloudKit model, or the
    /// seeded in-memory one when test mode is on (DEBUG).
    static func app(ledger: RewardLedger? = nil) -> CommunityModel {
        #if DEBUG
        if testModeWanted {
            let model = CommunityModel(store: nil, demo: true, ledger: ledger)
            model.testMode = true
            return model
        }
        #endif
        let model = live()
        model.ledger = ledger
        return model
    }

    #if DEBUG
    /// Friends against a fake database kept in memory, for a simulator with
    /// no iCloud account (Melvin, 2026-09-22: "the friends tab has been like
    /// closed off this whole time due to icloud, can you fix this so i can
    /// test it"). Everything works except leaving the device: profiles,
    /// search, requests, posts, reactions, reports.
    ///
    /// On by default in the simulator, off on a phone, and switchable in the
    /// tab. `PREVIEW_FRIENDS` still forces it on, and `=claim` leaves the
    /// handle unclaimed so the first-run screen shows.
    @Published private(set) var testMode = false
    static let testModeKey = "community.testMode.v1"

    static var testModeWanted: Bool {
        if ProcessInfo.processInfo.environment["PREVIEW_FRIENDS"] != nil { return true }
        #if targetEnvironment(simulator)
        let byDefault = true
        #else
        let byDefault = false
        #endif
        return UserDefaults.standard.object(forKey: testModeKey) as? Bool ?? byDefault
    }

    func setTestMode(_ on: Bool) async {
        testMode = on
        UserDefaults.standard.set(on, forKey: Self.testModeKey)
        demo = on
        store = on ? nil : CloudKitCommunityDatabase.ifEntitled().map { CommunityStore(database: $0) }
        profile = nil
        myID = nil
        phase = .loading
        await load()
    }
    #endif

    var friendCount: Int { friends.count }

    /// My own following and followers, from the lists already loaded: the
    /// edges I wrote are my friends plus the requests I have sent, and the
    /// edges written at me are my friends plus the requests I have not
    /// answered. No query (Melvin, 2026-09-18: "a follower/following for
    /// each profile").
    var follow: (followers: Int, following: Int) {
        (friends.count + incoming.count, friends.count + sent.count)
    }

    /// Someone else's counts, fetched once per profile and cached so a
    /// profile page opened twice does not query twice.
    @Published private(set) var followCounts: [String: (followers: Int, following: Int)] = [:]

    /// The people behind one of the two numbers, cached the same way. For my
    /// own id the lists are already loaded, so this is free.
    func follows(_ list: FollowList) async -> [String] {
        if list.person == myID {
            let ids = list.which == .followers ? friends + incoming : friends + sent
            await cacheIfNeeded(Set(ids))
            return ids.sorted()
        }
        guard let store, phase == .ready,
              let both = try? await store.follows(of: list.person) else { return [] }
        let ids = list.which == .followers ? both.followers : both.following
        followCounts[list.person] = (both.followers.count, both.following.count)
        await cacheIfNeeded(Set(ids))
        return ids
    }

    private func cacheIfNeeded(_ names: Set<String>) async {
        try? await cache(names: names)
    }

    func loadFollowCounts(_ id: String) async {
        guard let store, phase == .ready, followCounts[id] == nil else { return }
        guard let counts = try? await store.followCounts(of: id) else { return }
        followCounts[id] = counts
    }

    /// A session finished. Stamps the profile's first session once, which is
    /// the fact the invite reward reads. Cheap after the first time: nothing
    /// is fetched when the profile already carries the date.
    func noteSessionCompleted(at date: Date) async {
        // Launch's load may still be running when a results screen opens;
        // skipping then would lose the one fact the invite reward reads.
        if phase == .loading { await load() }
        guard let store, phase == .ready, let profile, profile.firstSessionAt == nil else { return }
        try? await store.markFirstSession(at: date)
        self.profile = try? await store.myProfile()
    }

    // MARK: - Loading

    func load() async {
        #if DEBUG
        // `PREVIEW_FRIENDS=1`: a seeded in-memory database, so the tab can be
        // reviewed on a simulator with no iCloud account.
        if demo, store == nil { store = await DemoCommunity.store() }
        #endif
        guard let store else { unavailableReason = .noContainer; phase = .unavailable; return }
        unavailableReason = .noAccount
        do {
            myID = try await store.me()
            profile = try await store.myProfile()
            guard let profile, !profile.username.isEmpty else { phase = .needsUsername; return }
            try await refreshLists(store)
            phase = .ready
        } catch {
            // A missing account is the common case. Anything else, before a
            // profile exists, is a failure the card states plainly; with a
            // profile the tab stays usable and the error is an alert.
            if (error as? CommunityError) == .unavailable {
                unavailableReason = .noAccount
                phase = .unavailable
            } else if profile == nil {
                unavailableReason = .failed(Self.plain(error))
                phase = .unavailable
            } else {
                phase = .ready
                errorText = Self.plain(error)
            }
        }
    }

    func refresh() async {
        guard let store, phase == .ready else { return }
        do { try await refreshLists(store) } catch { errorText = Self.plain(error) }
    }

    private func refreshLists(_ store: CommunityStore) async throws {
        async let f = store.friends()
        async let i = store.incomingRequests()
        async let s = store.sentRequests()
        let (fr, inc, sn) = try await (f, i, s)
        friends = fr; incoming = inc; sent = sn
        let posts = try await store.feed(limit: 40)
        feed = posts
        reactions = try await store.reactions(for: posts.map(\.id))
        try await cache(names: Set(fr + inc + sn + posts.map(\.author) + reactions.values.flatMap { $0 }))
        try await checkRewards(store)
    }

    /// Bring a friend, see the evidence (`InviteReward`). Runs after every
    /// list refresh; pays out once per friend, from facts on public records.
    private func checkRewards(_ store: CommunityStore) async throws {
        guard let ledger else { return }
        let facts = try await store.friendFacts()
        for id in InviteReward.newlyRewardable(facts, alreadyRewarded: ledger.rewardedFriends) {
            guard let remaining = ledger.grant(forFriend: id) else { continue }
            Analytics.track(.inviteRewarded)
            let name = people[id]?.displayName ?? ""
            rewardNews = RewardNews(friendName: name.isEmpty ? "A friend you invited" : name, remaining: remaining)
        }
    }

    private func cache(names: Set<String>) async throws {
        guard let store else { return }
        let missing = names.filter { people[$0] == nil }
        for p in try await store.profiles(named: Array(missing)) { people[p.id] = p }
    }

    func person(_ id: String) -> Profile? { people[id] }

    /// Loads one profile into the cache (a profile page opened for someone
    /// the lists never mentioned).
    func loadPerson(_ id: String) async {
        guard people[id] == nil, let store, let p = try? await store.profile(named: id) else { return }
        people[id] = p
    }

    // MARK: - Username

    enum Availability: Equatable {
        case available, taken, invalid
        /// The check itself failed. Shown on screen; never swallowed (the
        /// first version turned every iCloud error into a silently disabled
        /// button).
        case failed(String)
    }

    func availability(of handle: String) async -> Availability {
        guard let store else { return .failed(CommunityError.unavailable.localizedDescription) }
        guard Username.normalize(handle) != nil else { return .invalid }
        do {
            return try await store.isUsernameAvailable(handle) ? .available : .taken
        } catch {
            return .failed(Self.plain(error))
        }
    }

    /// True on success. The claimed handle is returned through `profile`.
    func claim(_ handle: String, displayName: String) async -> Bool {
        guard let store else { return false }
        do {
            profile = try await store.claimUsername(handle, displayName: displayName)
            Analytics.track(.usernameClaimed)
            phase = .ready
            // Sessions sat before the profile existed (the onboarding demo,
            // weeks of practice before 1.1) still count as a first session
            // for whoever invited this person.
            if let first = firstLocalSession?() { await noteSessionCompleted(at: first) }
            // The claim is done. Loading friends is a separate step whose
            // failure (e.g. an index missing in the CloudKit Console) must not
            // read as the claim failing.
            do { try await refreshLists(store) } catch { errorText = Self.plain(error) }
            return true
        } catch let e as CommunityError where e == .usernameTaken || e == .usernameInvalid || e == .contentBlocked {
            errorText = e == .usernameTaken ? "That name is taken. Try another." : e.localizedDescription
            return false
        } catch {
            errorText = Self.plain(error)
            return false
        }
    }

    /// Uploads a profile photo (prepared like a post photo). Failures are
    /// shown but never undo the profile that was just created.
    func setAvatar(_ image: UIImage) async {
        guard let store else { return }
        guard await PhotoScreen.check(image) != .sensitive else {
            errorText = CommunityError.photoBlocked.localizedDescription
            return
        }
        guard let url = PostPhoto.prepare(image) else { return }
        do {
            profile = try await store.setAvatar(url)
            if let profile { people[profile.id] = profile }
        } catch { errorText = Self.plain(error) }
    }

    // MARK: - People

    func search(_ handle: String) async -> Profile? {
        guard let store else { return nil }
        let found = try? await store.search(username: handle)
        if let found { people[found.id] = found }
        return found
    }

    func relationship(with id: String) async -> CommunityStore.Relationship {
        guard let store else { return .none }
        return (try? await store.relationship(with: id)) ?? .none
    }

    func request(_ id: String) async {
        guard let store else { return }
        do {
            try await store.sendRequest(to: id)
            Analytics.track(.friendRequestSent)
            try await refreshLists(store)
        } catch { errorText = Self.plain(error) }
    }

    func accept(_ id: String) async {
        guard let store else { return }
        do {
            try await store.accept(id)
            Analytics.track(.friendAccepted)
            try await refreshLists(store)
        } catch { errorText = Self.plain(error) }
    }

    func remove(_ id: String) async {
        guard let store else { return }
        do { try await store.removeFriend(id); try await refreshLists(store) } catch { errorText = Self.plain(error) }
    }

    func posts(by id: String) async -> [Post] {
        guard let store else { return [] }
        return (try? await store.posts(by: id)) ?? []
    }

    // MARK: - Posts and reactions

    func post(_ draft: CommunityStore.Draft) async -> Bool {
        guard let store else { return false }
        do {
            let p = try await store.post(draft)
            Analytics.track(.postCreated(photo: draft.photoURL != nil))
            feed.removeAll { $0.id == p.id }
            feed.insert(p, at: 0)
            return true
        } catch { errorText = Self.plain(error); return false }
    }

    /// The post for a session, if it was shared.
    func post(forSession sessionID: UUID) async -> Post? {
        guard let store else { return nil }
        return try? await store.post(id: CommunityStore.postID(forSession: sessionID.uuidString))
    }

    /// Takes a session's post down (it went to Only you).
    func unpost(session sessionID: UUID) async {
        guard let store else { return }
        let id = CommunityStore.postID(forSession: sessionID.uuidString)
        do { try await store.unpost(session: sessionID.uuidString); feed.removeAll { $0.id == id } }
        catch { errorText = Self.plain(error) }
    }

    func deletePost(_ id: String) async {
        guard let store else { return }
        do {
            try await store.deletePost(id)
            feed.removeAll { $0.id == id }
            if id.hasPrefix("post-"), let session = UUID(uuidString: String(id.dropFirst(5))) {
                onPostRemoved?(session)
            }
        } catch { errorText = Self.plain(error) }
    }

    func hasReacted(to postID: String) -> Bool {
        guard let myID else { return false }
        return reactions[postID]?.contains(myID) ?? false
    }

    func toggleReaction(_ postID: String) async {
        guard let store, let myID else { return }
        let was = hasReacted(to: postID)
        // Optimistic: the tap should feel instant.
        var list = reactions[postID] ?? []
        if was { list.removeAll { $0 == myID } } else { list.append(myID) }
        reactions[postID] = list
        do {
            if was { try await store.unreact(to: postID) } else {
                try await store.react(to: postID)
                Analytics.track(.reactionGiven)
            }
        } catch {
            reactions[postID] = was ? list + [myID] : list.filter { $0 != myID }
            errorText = Self.plain(error)
        }
    }

    // MARK: - Block and report

    func block(_ id: String) async {
        guard let store else { return }
        do {
            try await store.block(id)
            Analytics.track(.userBlocked)
            try await refreshLists(store)
        } catch { errorText = Self.plain(error) }
    }

    func loadBlocked() async {
        guard let store else { return }
        do {
            blocked = try await store.blockedByMe()
            try await cache(names: Set(blocked))
        } catch { errorText = Self.plain(error) }
    }

    func unblock(_ id: String) async {
        guard let store else { return }
        do {
            try await store.unblock(id)
            blocked.removeAll { $0 == id }
            try await refreshLists(store)
        } catch { errorText = Self.plain(error) }
    }

    func report(_ target: String, as kind: Report.Target, reason: String) async {
        guard let store else { return }
        do {
            let report = try await store.report(target, as: kind, reason: reason)
            ReportClient.send(reportID: report.id, target: target, kind: kind.rawValue, reason: reason)
            Analytics.track(.contentReported(kind: kind.rawValue))
        } catch { errorText = Self.plain(error) }
    }

    static func plain(_ error: Error) -> String {
        if let ce = error as? CommunityError { return ce.localizedDescription }
        return "Couldn't reach iCloud. " + error.localizedDescription
    }
}
