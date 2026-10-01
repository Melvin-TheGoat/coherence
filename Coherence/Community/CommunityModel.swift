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
    /// People I blocked, for the Unblock list the block dialog points to, and
    /// so a person page opened for one of them shows nothing of theirs.
    /// Loaded with every list refresh. Only ever MY blocks: nobody else's are
    /// readable (see `CommunityStore`'s header).
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
    /// Every local session's start and length (all sources: Watch, phone,
    /// hand-logged), for the practice stats published on my profile
    /// (`syncPracticeStats`). Supplied by the app, which owns SwiftData.
    var allSessions: (() -> [(startedAt: Date, durationSec: Int)])?
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
        guard let store, phase == .ready, followCounts[id] == nil, !isBlocked(id) else { return }
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

    // MARK: - Practice stats

    /// The stats last written, so a foreground tick with nothing new to say
    /// costs no network call.
    private var lastSyncedPracticeStats: PracticeStats?
    /// The last time a sync was ATTEMPTED (whether or not it changed
    /// anything), for the "at most every few minutes" foreground gate.
    private var lastPracticeStatsAttemptAt: Date?

    /// Publishes how often I meditate (sessions and minutes this week, the
    /// streak, the total, and my last sit), computed from every local
    /// session. A no-op when Friends is off, when there is no profile yet
    /// (`.needsUsername`/`.unavailable`/`.loading`), or when the app never
    /// gave this model a way to read its sessions.
    ///
    /// `force` skips the "at most every few minutes" gate, for the moment a
    /// session actually lands (`SessionCoordinator.onSessionSaved`,
    /// `SessionSetupView.saveLog`); a plain app-foreground tick keeps it, so
    /// coming back to the app a dozen times an hour costs one write at most.
    func syncPracticeStats(force: Bool = false) async {
        // A claimed handle, not just a ready tab: Friends is optional
        // (Melvin, 2026-09-29), and nothing about how often somebody
        // meditates is published for a person who never made a profile.
        guard FeatureFlags.friends, let store, phase == .ready, hasProfile, let allSessions else { return }
        // Nothing while the person who made this profile has signed out or
        // deleted their account (`publishingPausedKey`), and nothing while a
        // deletion is unfinished: a save now would put back the profile
        // record the deletion is taking down (the save is an upsert).
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.publishingPausedKey),
              !defaults.bool(forKey: Self.pendingDeletionKey) else { return }
        if !force, let last = lastPracticeStatsAttemptAt, Date().timeIntervalSince(last) < 180 { return }
        lastPracticeStatsAttemptAt = Date()
        let stats = PracticeStats.compute(from: allSessions())
        guard stats != lastSyncedPracticeStats else { return }
        guard let updated = try? await store.updatePracticeStats(stats) else { return }
        lastSyncedPracticeStats = stats
        profile = updated
        people[updated.id] = updated
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
            // An account deletion that has not finished yet: finish it before
            // anything else, and never show the profile it is taking down
            // (Melvin, 2026-09-29). Without this, Friends and Profile went on
            // showing the deleted @username, and onboarding's profile step
            // opened on it in Edit mode.
            if UserDefaults.standard.bool(forKey: Self.pendingDeletionKey) {
                do {
                    try await store.deleteEverythingOfMine()
                    UserDefaults.standard.removeObject(forKey: Self.pendingDeletionKey)
                } catch {
                    profile = nil
                    phase = .needsUsername
                    return
                }
            }
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
        async let b = store.blockedByMe()
        let (fr, inc, sn, bl) = try await (f, i, s, b)
        friends = fr; incoming = inc; sent = sn; blocked = bl
        // Anything cached about them from before the block goes too.
        for id in bl { forgetBlockedPerson(id) }
        // No feed and no reactions any more (Melvin, 2026-09-29). Posting was
        // removed on 2026-09-27, but every open of Friends still queried the
        // Post and Reaction types, and in a Production container where either
        // type or its index is missing that query fails and the whole tab
        // reads as broken. `clearMyPostsIfNeeded` still takes down anything
        // already shared, on its own path.
        try await cache(names: Set(fr + inc + sn))
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

    /// A claimed handle. Friends is optional (Melvin, 2026-09-29), and
    /// everything that reaches another person (search, requests, published
    /// practice stats) waits for a profile first.
    var hasProfile: Bool { !(profile?.username ?? "").isEmpty }

    /// Loads one profile into the cache (a profile page opened for someone
    /// the lists never mentioned).
    func loadPerson(_ id: String) async {
        guard people[id] == nil, let store, let p = try? await store.profile(named: id) else { return }
        people[id] = p
    }

    // MARK: - Username

    enum Availability: Equatable {
        case available, taken, invalid
        /// A handle the handle filter refuses (guideline 1.2).
        case notAllowed
        /// The check itself failed. Shown on screen; never swallowed (the
        /// first version turned every iCloud error into a silently disabled
        /// button).
        case failed(String)
    }

    func availability(of handle: String) async -> Availability {
        guard let store else { return .failed(CommunityError.unavailable.localizedDescription) }
        guard let normalized = Username.normalize(handle) else { return .invalid }
        // The handle this person already holds is always theirs to keep, even
        // one claimed before the filters below existed (2026-09-30).
        if normalized == profile?.username { return .available }
        // Decided on the phone, before any network: an offensive handle is
        // refused outright, and a reserved one ("admin", "otto", "808
        // support") reads as taken, which is what it is (Melvin, 2026-09-29).
        switch ContentFilter.checkHandle(normalized) {
        case .blocked: return .notAllowed
        case .reserved: return .taken
        case .ok: break
        }
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
            // A new profile after a deleted account is a fresh start: an
            // unfinished deletion retrying at the next launch would take
            // this profile down with the old one.
            UserDefaults.standard.removeObject(forKey: Self.pendingDeletionKey)
            // Somebody claimed or saved a profile: it is theirs, and how often
            // they meditate may be published again.
            UserDefaults.standard.removeObject(forKey: Self.publishingPausedKey)
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

    /// Takes the published profile photo down (Melvin, 2026-09-29: "Remove
    /// photo" on Edit profile used to clear only the local pick, so the
    /// photo everyone else saw stayed up). Everyone sees the empty person
    /// after this.
    func clearAvatar() async {
        guard let store, hasProfile else { return }
        do {
            profile = try await store.setAvatar(nil)
            if let profile { people[profile.id] = profile }
        } catch { errorText = Self.plain(error) }
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
        guard let store, hasProfile else { return nil }
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
        guard hasProfile else { errorText = CommunityError.noProfile.localizedDescription; return }
        do {
            try await store.sendRequest(to: id)
            Analytics.track(.friendRequestSent)
            try await refreshLists(store)
        } catch { errorText = Self.plain(error) }
    }

    func accept(_ id: String) async {
        guard let store else { return }
        guard hasProfile else { errorText = CommunityError.noProfile.localizedDescription; return }
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

    /// Sessions whose post is still uploading, so the feed can say so.
    @Published private(set) var uploading: [String] = []

    /// Posts without holding the screen that asked (Melvin, 2026-09-27:
    /// Friends "loaded like forever before actually posting"). The session
    /// page used to wait for every photo and video to reach iCloud, up to
    /// ten items of which a video can be 40 MB, before it closed. Now it
    /// closes at once: the files are prepared off the main actor, the upload
    /// runs here (this model outlives the page), iOS is asked for time to
    /// finish if the person leaves the app, and the feed shows a "Posting"
    /// line meanwhile. A failure lands in `errorText`, which the Friends tab
    /// shows, and `onFailure` lets the caller undo what it recorded.
    func postInBackground(_ draft: CommunityStore.Draft, media: [PostMediaPrep.Source],
                          onFailure: @escaping @MainActor () -> Void) {
        let key = draft.sessionID ?? UUID().uuidString
        uploading.append(key)
        var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask(withName: "808 post") {
            UIApplication.shared.endBackgroundTask(background)
            background = .invalid
        }
        Task { @MainActor in
            let prepared = await Task.detached(priority: .userInitiated) {
                media.compactMap(PostMediaPrep.draft(from:))
            }.value
            var full = draft
            full.media = prepared
            let ok = await post(full)
            uploading.removeAll { $0 == key }
            if !ok { onFailure() }
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
    }

    func post(_ draft: CommunityStore.Draft) async -> Bool {
        guard let store else { return false }
        do {
            let p = try await store.post(draft)
            feed = Self.placing(p, in: feed)
            return true
        } catch { errorText = Self.plain(error); return false }
    }

    /// Where a saved post goes in the feed without waiting for a reload: in
    /// its own place when it is already there (an edit, which keeps its
    /// date), otherwise among the rest by when it was practiced, which is the
    /// order `CommunityStore.feed` returns. Inserting at the top instead sent
    /// an edited post, or a session shared days later, above posts practiced
    /// after it until the next refresh.
    static func placing(_ post: Post, in feed: [Post]) -> [Post] {
        var out = feed
        if let i = out.firstIndex(where: { $0.id == post.id }) {
            out[i] = post
        } else {
            let at = out.firstIndex { $0.practicedAt < post.practicedAt } ?? out.endIndex
            out.insert(post, at: at)
        }
        return out
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
            }
        } catch {
            reactions[postID] = was ? list + [myID] : list.filter { $0 != myID }
            errorText = Self.plain(error)
        }
    }

    // MARK: - Block and report

    /// Blocks someone. Private and one-sided: they are not told, and from
    /// now on this phone shows nothing of theirs (see `CommunityStore`).
    func block(_ id: String) async {
        guard let store else { return }
        do {
            try await store.block(id)
            Analytics.track(.userBlocked)
            if !blocked.contains(id) { blocked = (blocked + [id]).sorted() }
            forgetBlockedPerson(id)
            try await refreshLists(store)
        } catch { errorText = Self.plain(error) }
    }

    func isBlocked(_ id: String) -> Bool { blocked.contains(id) }

    /// Keeps only a blocked person's name (for the Blocked list): their
    /// photo, practice summary and follow counts, cached from before the
    /// block, are dropped so no screen can show them.
    private func forgetBlockedPerson(_ id: String) {
        if let p = people[id] { people[id] = CommunityStore.nameOnly(p) }
        followCounts[id] = nil
    }

    func loadBlocked() async {
        guard let store else { return }
        do {
            blocked = try await store.blockedByMe()
            for id in blocked { forgetBlockedPerson(id) }
            try await cache(names: Set(blocked))
        } catch { errorText = Self.plain(error) }
    }

    func unblock(_ id: String) async {
        guard let store else { return }
        do {
            try await store.unblock(id)
            blocked.removeAll { $0 == id }
            // The name-only copy goes, so their page loads them in full again.
            people[id] = nil
            try await refreshLists(store)
        } catch { errorText = Self.plain(error) }
    }

    func report(_ target: String, as kind: Report.Target, reason: String) async {
        guard let store else { return }
        do {
            let report = try await store.report(target, as: kind, reason: reason)
            // Test mode reports a seeded, fake person into the in-memory
            // database: emailing the real inbox about it is noise (2026-09-30).
            if !testMode {
                ReportClient.send(reportID: report.id, target: target, kind: kind.rawValue, reason: reason)
            }
            Analytics.track(.contentReported(kind: kind.rawValue))
        } catch { errorText = Self.plain(error) }
    }

    // MARK: - Signing out and deleting the account

    /// Set when the person on this phone signs out of 808 or deletes their
    /// account; cleared when somebody claims or saves a profile, keeps the
    /// one they have on onboarding's profile step, or opens Friends with one
    /// (`resumePublishing`). While it is set, nothing about how often anybody
    /// meditates is published (Melvin, 2026-09-29).
    ///
    /// Stored, not held in memory, because a Friends profile belongs to the
    /// phone's iCloud account, not to the 808 account: signing out of 808
    /// leaves it loadable, and the app loads Friends and publishes practice
    /// stats at every launch and every return to the foreground. A flag that
    /// died with the process would have started publishing again, for a
    /// person who had signed out, the next time the app opened on onboarding.
    static let publishingPausedKey = "community.practiceStatsPaused.v1"

    /// UserDefaults key for a Friends deletion that has not finished
    /// (offline, no iCloud, a network blip at exactly the wrong moment, or
    /// simply still running). Not `private`, like `testModeKey` above:
    /// `retryPendingDeletion` reads it from a fresh launch and a test needs
    /// to see it too.
    static let pendingDeletionKey = "community.pendingAccountDeletion.v1"

    /// Everything this model holds about the person who just left, dropped
    /// at once (Melvin, 2026-09-29, second pass of the pre-1.1 audit). It
    /// used to survive both sign-out and Delete account: Friends and Profile
    /// kept showing the old @username, onboarding's profile step opened in
    /// Edit mode on it, and practice stats kept publishing to it.
    ///
    /// Also forgets, on this phone, that anybody agreed to the community
    /// rules or saw the Friends intro: the next person to use the phone
    /// agrees for themselves.
    private func forgetThisPerson() {
        profile = nil
        myID = nil
        feed = []
        people = [:]
        friends = []
        incoming = []
        sent = []
        blocked = []
        reactions = [:]
        followCounts = [:]
        rewardNews = nil
        errorText = nil
        lastSyncedPracticeStats = nil
        lastPracticeStatsAttemptAt = nil
        phase = .loading
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.publishingPausedKey)
        defaults.removeObject(forKey: CreateProfileView.rulesAcceptedKey)
        defaults.removeObject(forKey: FriendsIntroView.shownKey)
    }

    /// The person signed out of 808. Their Friends profile stays in iCloud
    /// (it is the iCloud account's, and they may sign back in), but this
    /// phone stops showing it and stops publishing to it until someone
    /// takes it up again (`publishingPausedKey`).
    func signedOut() {
        forgetThisPerson()
    }

    /// Lifts `publishingPausedKey`: the person on this phone has taken their
    /// profile up again (kept it on onboarding's profile step, or opened
    /// Friends with it). A claim lifts it too, inside `claim`.
    func resumePublishing() {
        guard UserDefaults.standard.bool(forKey: Self.publishingPausedKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.publishingPausedKey)
        Task { await syncPracticeStats(force: true) }
    }

    /// Deletes everything I've written to Friends: my profile, my posts, my
    /// reactions, my friend edges and blocks, my username. Called once, when
    /// the person deletes their 808 account (App Review 5.1.1(v) — deleting
    /// an account must delete what it published, not just sign the person
    /// out locally).
    ///
    /// Runs against whatever store this model already holds, so it reaches
    /// the in-memory database in test mode and the real CloudKit one
    /// otherwise. Gated on `FeatureFlags.friends` explicitly: `store` is set
    /// whenever the process holds a CloudKit container, whether or not
    /// Friends itself is switched on in THIS build, and a build that never
    /// turned it on has nothing to clean up.
    ///
    /// Best effort, and resumable: the pending flag is set BEFORE the first
    /// request and cleared only when a run finishes clean, so a failure, a
    /// kill mid-way, or a `load()` that races this one all see a deletion
    /// still owed. `load()` finishes it the next time Friends loads, and
    /// `retryPendingDeletion()` (from `CoherenceApp`'s launch task) at every
    /// later launch until one run finishes clean.
    func deleteAccountData() async {
        forgetThisPerson()
        guard FeatureFlags.friends else { return }
        UserDefaults.standard.set(true, forKey: Self.pendingDeletionKey)
        // No store yet this launch (iCloud unavailable, or not loaded): the
        // request stays remembered rather than dropped, and a later launch
        // that reaches iCloud deletes whatever is there.
        guard let store else { return }
        do {
            try await store.deleteEverythingOfMine()
            UserDefaults.standard.removeObject(forKey: Self.pendingDeletionKey)
        } catch {
            // Still pending: `load()` and the next launch try again. (A
            // profile claimed meanwhile has already cleared the flag, and is
            // not taken down by a retry.)
        }
    }

    /// Retries a Friends deletion an earlier launch could not finish. A
    /// no-op almost always, since the flag is normally clear. Builds its own
    /// store rather than waiting on an instance's `load()` — the same reason
    /// `WaitlistClient.flush()` does its own thing on launch — and, like
    /// every other entry point into CloudKit here, goes through
    /// `ifEntitled()` so it never constructs a container the process does
    /// not hold (see CLAUDE.md, "THE BETA CRASHED ON LAUNCH A THIRD TIME": a
    /// guessed or unheld container is what crashed the app on launch three
    /// times).
    static func retryPendingDeletion() async {
        guard FeatureFlags.friends, UserDefaults.standard.bool(forKey: pendingDeletionKey) else { return }
        guard let db = CloudKitCommunityDatabase.ifEntitled() else { return }
        do {
            try await CommunityStore(database: db).deleteEverythingOfMine()
            UserDefaults.standard.removeObject(forKey: pendingDeletionKey)
        } catch {
            // Still pending. The next launch tries again.
        }
    }

    // MARK: - Posting removed

    /// UserDefaults key for the one-time cleanup that removes every post
    /// this person had already shared, from the day posting was removed
    /// (Melvin, 2026-09-27: "get rid of the feed, no more posting with
    /// photos/videos ... big privacy policy change"). Not `private`, like
    /// `pendingDeletionKey` above: a test needs to see it too.
    static let postsClearedKey = "community.postsCleared.v1"

    /// Deletes every post I've already shared, once. Silent on purpose:
    /// nobody needs telling that a feed which no longer exists in the app
    /// also stopped existing on the server. Retried on a later launch (from
    /// `CoherenceApp`'s launch task) if this one can't reach iCloud, the same
    /// pattern as `retryPendingDeletion`.
    ///
    /// Runs against whatever store this model already holds (real CloudKit,
    /// or the in-memory one in test mode), so it needs no store of its own.
    /// A profile is not required — `me()` only needs an iCloud account — so
    /// this can run even for someone who never claimed a username.
    func clearMyPostsIfNeeded() async {
        guard FeatureFlags.friends, !UserDefaults.standard.bool(forKey: Self.postsClearedKey) else { return }
        guard let store else { return }
        do {
            try await store.deleteMyPosts()
            UserDefaults.standard.set(true, forKey: Self.postsClearedKey)
        } catch {
            // No iCloud account, no network, or a query missing an index in
            // this environment: retried on the next launch.
        }
    }

    static func plain(_ error: Error) -> String {
        if let ce = error as? CommunityError { return ce.localizedDescription }
        return "Couldn't reach iCloud. " + error.localizedDescription
    }
}
