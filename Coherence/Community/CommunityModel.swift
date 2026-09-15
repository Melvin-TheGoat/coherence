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
    @Published private(set) var profile: Profile?
    @Published private(set) var feed: [Post] = []
    /// Profiles by record name, for everyone the feed and the lists mention.
    @Published private(set) var people: [String: Profile] = [:]
    @Published private(set) var friends: [String] = []
    @Published private(set) var incoming: [String] = []
    @Published private(set) var sent: [String] = []
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
    private let demo: Bool
    var ledger: RewardLedger?

    init(store: CommunityStore?, demo: Bool = false, ledger: RewardLedger? = nil) {
        self.store = store; self.demo = demo; self.ledger = ledger
    }

    /// The production model: CloudKit if the process holds a container,
    /// otherwise a permanently unavailable tab.
    static func live() -> CommunityModel {
        CommunityModel(store: CloudKitCommunityDatabase.ifEntitled().map { CommunityStore(database: $0) })
    }

    /// The one instance the app injects: the live CloudKit model, or the
    /// seeded demo when `PREVIEW_FRIENDS` is set (DEBUG).
    static func app(ledger: RewardLedger? = nil) -> CommunityModel {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PREVIEW_FRIENDS"] != nil {
            return CommunityModel(store: nil, demo: true, ledger: ledger)
        }
        #endif
        let model = live()
        model.ledger = ledger
        return model
    }

    var friendCount: Int { friends.count }

    /// A session finished. Stamps the profile's first session once, which is
    /// the fact the invite reward reads. Cheap after the first time: nothing
    /// is fetched when the profile already carries the date.
    func noteSessionCompleted(at date: Date) async {
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
        guard let store else { phase = .unavailable; return }
        do {
            myID = try await store.me()
            profile = try await store.myProfile()
            guard let profile, !profile.username.isEmpty else { phase = .needsUsername; return }
            try await refreshLists(store)
            phase = .ready
        } catch {
            // A missing account is the common case; anything else is shown.
            if (error as? CommunityError) == .unavailable {
                phase = .unavailable
            } else {
                phase = profile == nil ? .unavailable : .ready
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
            // The claim is done. Loading friends is a separate step whose
            // failure (e.g. an index missing in the CloudKit Console) must not
            // read as the claim failing.
            do { try await refreshLists(store) } catch { errorText = Self.plain(error) }
            return true
        } catch let e as CommunityError where e == .usernameTaken || e == .usernameInvalid {
            errorText = e == .usernameTaken ? "That name is taken. Try another." : "Letters, numbers, dots and underscores only."
            return false
        } catch {
            errorText = Self.plain(error)
            return false
        }
    }

    /// Uploads a profile photo (prepared like a post photo). Failures are
    /// shown but never undo the profile that was just created.
    func setAvatar(_ image: UIImage) async {
        guard let store, let url = PostPhoto.prepare(image) else { return }
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
        do { try await store.deletePost(id); feed.removeAll { $0.id == id } } catch { errorText = Self.plain(error) }
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

    func report(_ target: String, as kind: Report.Target, reason: String) async {
        guard let store else { return }
        do {
            try await store.report(target, as: kind, reason: reason)
            Analytics.track(.contentReported(kind: kind.rawValue))
        } catch { errorText = Self.plain(error) }
    }

    static func plain(_ error: Error) -> String {
        if let ce = error as? CommunityError { return ce.localizedDescription }
        return "Couldn't reach iCloud. " + error.localizedDescription
    }
}
