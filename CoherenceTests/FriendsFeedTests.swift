import XCTest
import CloudKit
@testable import Coherence

/// The Friends feed (2026-11-13, `mockups/friends-v3.html`): what a post
/// carries, the Logged chip, kudos, blocks, and the invite paywall's routing.
final class FriendsFeedTests: XCTestCase {

    private var db: MemoryCommunityDatabase!
    private var aziz: CommunityStore!
    private var melvin: CommunityStore!
    private let azizID = CommunityNames.profile(user: "_aziz")
    private let melvinID = CommunityNames.profile(user: "_melvin")

    override func setUp() async throws {
        db = MemoryCommunityDatabase(user: "_aziz")
        aziz = CommunityStore(database: db.acting(as: "_aziz"))
        melvin = CommunityStore(database: db.acting(as: "_melvin"))
        try await aziz.claimUsername("aziz", displayName: "Aziz")
        try await melvin.claimUsername("melvin", displayName: "Melvin")
        try await aziz.sendRequest(to: melvinID)
        try await melvin.accept(azizID)
    }

    private func draft(logged: Bool = false) -> CommunityStore.Draft {
        .init(minutes: 15, streak: 9, technique: "Silence", caption: "", media: [],
              practicedAt: Date(), title: "Before the big call", sound: "Rain", logged: logged)
    }

    // MARK: What a post carries

    func test_aPostNeverCarriesAScoreOrAnythingMeasured() async throws {
        let post = try await melvin.post(draft())
        let record = try XCTUnwrap(db.records[post.id])
        for key in record.allKeys() {
            for banned in ["score", "heart", "hr", "bpm", "breath", "stillness", "curve", "hrv"] {
                XCTAssertFalse(key.lowercased().contains(banned), "\(key) looks measured")
            }
        }
        XCTAssertTrue(Post.fields.contains("logged"))
    }

    func test_loggedRoundTripsAndPicksTheChip() async throws {
        let logged = try await melvin.post(draft(logged: true))
        let timed = try await melvin.post(draft(logged: false))
        let feed = try await aziz.feed()
        XCTAssertEqual(feed.first { $0.id == logged.id }?.logged, true)
        XCTAssertEqual(feed.first { $0.id == timed.id }?.logged, false)
        XCTAssertEqual(PostChip.label(logged: true), "Logged")
        XCTAssertEqual(PostChip.label(logged: false), "✓ Timed in 808")
    }

    // MARK: Kudos

    func test_oneKudosPerPersonAndPickingAnotherReplacesIt() async throws {
        let post = try await melvin.post(draft())
        try await aziz.react(to: post.id, emoji: "🔥")
        try await aziz.react(to: post.id, emoji: "✨")
        let all = try await melvin.reactions(for: [post.id])
        XCTAssertEqual(all[post.id]?.count, 1)
        XCTAssertEqual(all[post.id]?.first?.emoji, "✨")
    }

    func test_kudosOutsideTheFourReadAsThePrayer() {
        XCTAssertEqual(Kudos.sanitized("💩"), "🙏")
        XCTAssertEqual(Kudos.sanitized(nil), "🙏")
        XCTAssertEqual(Kudos.sanitized("🧘"), "🧘")
        XCTAssertEqual(Reaction(post: "p", author: "a", emoji: "anything").emoji, "🙏")
    }

    func test_kudosLineNamesPeople() {
        XCTAssertEqual(KudosLine.text(names: ["Aziz", "Melvin"], mine: true, isMyPost: false), "You, Aziz and Melvin")
        XCTAssertEqual(KudosLine.text(names: [], mine: false, isMyPost: true), "No kudos yet")
        XCTAssertEqual(KudosLine.text(names: ["A", "B", "C", "D"], mine: false, isMyPost: false), "A, B and 2 others")
    }

    // MARK: Blocks

    func test_aBlockedPersonsPostsNeverReachTheFeed() async throws {
        _ = try await melvin.post(draft())
        let before = try await aziz.feed()
        XCTAssertEqual(before.count, 1)
        try await aziz.block(melvinID)
        let after = try await aziz.feed()
        XCTAssertTrue(after.isEmpty)
        let theirs = try await aziz.posts(by: melvinID)
        XCTAssertTrue(theirs.isEmpty)
    }

    func test_aBlockedPersonsKudosAreNotCounted() async throws {
        let mine = try await aziz.post(draft())
        try await melvin.react(to: mine.id, emoji: "🔥")
        try await aziz.block(melvinID)
        let all = try await aziz.reactions(for: [mine.id])
        XCTAssertTrue((all[mine.id] ?? []).isEmpty)
    }

    func test_strangersSeeNoPosts() async throws {
        let stranger = CommunityStore(database: db.acting(as: "_stranger"))
        try await stranger.claimUsername("stranger", displayName: "S")
        _ = try await melvin.post(draft())
        let feed = try await stranger.feed()
        XCTAssertTrue(feed.isEmpty)
    }

    // MARK: The feed's helpers

    func test_feedGroupsByDayNewestFirst() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let p = { (h: Double) in Post(author: "a", minutes: 1, streak: 1, practicedAt: now.addingTimeInterval(-h * 3600)) }
        // now is 08:00 UTC: 1 and 2 hours ago are today, 20 is yesterday.
        let days = FeedDays.group([p(20), p(1), p(2)], now: now, calendar: cal)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.first?.title, "Today")
        XCTAssertEqual(days.first?.posts.count, 2)
        XCTAssertEqual(days.last?.title, "Yesterday")
    }

    func test_yourTurnOnlyWhenTheyWentAndIHaveNot() {
        let today = "2026-11-13"
        func goal(mine: [String], theirs: [String], state: GoalPair.State = .active) -> GoalPair {
            GoalPair(id: "g", partner: "p", target: 4, startDay: "2026-11-10", state: state,
                     myDays: mine.map { GoalDay(day: $0, minutes: 10) },
                     theirDays: theirs.map { GoalDay(day: $0, minutes: 10) },
                     invitedByMe: true, createdAt: Date())
        }
        XCTAssertNotNil(YourTurn.pick([goal(mine: [], theirs: [today])], today: today))
        XCTAssertNil(YourTurn.pick([goal(mine: [today], theirs: [today])], today: today))
        XCTAssertNil(YourTurn.pick([goal(mine: [], theirs: [])], today: today))
        XCTAssertNil(YourTurn.pick([goal(mine: [], theirs: [today], state: .waitingForMe)], today: today))
    }

    func test_feedBadgeGlowsOnlyForRecentPractice() {
        let now = Date()
        XCTAssertFalse(FeedBadge.glowing(lastSessionAt: nil, now: now))
        let recent = now.addingTimeInterval(-3600)
        XCTAssertTrue(FeedBadge.glowing(lastSessionAt: recent, now: now))
        XCTAssertEqual(FeedBadge.stage(sessions7d: 7, lastSessionAt: recent, now: now), 7)
        XCTAssertEqual(FeedBadge.stage(sessions7d: 0, lastSessionAt: now.addingTimeInterval(-5 * 86_400), now: now), 2)
    }

    /// The slam's landmarks: huge at the start, at the row on impact,
    /// squashed just after, settled and gone at the end.
    func test_slamLandsOnTheRow() {
        let from = CGPoint(x: 200, y: 300), to = CGPoint(x: 60, y: 700)
        let hang = SlamFrame.at(t: KudosSlam.hang - 0.01, from: from, to: to)
        XCTAssertEqual(hang.point, from)
        XCTAssertGreaterThan(hang.scale, 3)
        let impact = SlamFrame.at(t: KudosSlam.impact + 0.01, from: from, to: to)
        XCTAssertEqual(impact.point, to)
        XCTAssertGreaterThan(impact.squashX, 1)
        XCTAssertLessThan(impact.squashY, 1)
        let done = SlamFrame.at(t: KudosSlam.done, from: from, to: to)
        XCTAssertEqual(done.opacity, 0, accuracy: 0.001)
    }

    // MARK: The invite paywall

    func test_invitePaywallOnlyWithAnInviteAndTheFreeMonth() {
        let who = PendingInvite(code: "AZIZK7QX4", inviter: "x", name: "Aziz", username: "aziz")
        XCTAssertEqual(InviteOffer.inviter(pending: who, joined: nil, productLoaded: true, freeDays: 30), who)
        XCTAssertNil(InviteOffer.inviter(pending: nil, joined: nil, productLoaded: true, freeDays: 30),
                     "no code, the normal paywall")
        XCTAssertNil(InviteOffer.inviter(pending: who, joined: nil, productLoaded: false, freeDays: 30),
                     "no product in App Store Connect yet, the normal paywall")
        XCTAssertNil(InviteOffer.inviter(pending: who, joined: nil, productLoaded: true, freeDays: nil),
                     "already had a trial, no gift to promise")
    }

    func test_theInviteProductIsNeverRequiredToSell() {
        XCTAssertFalse(Store.ProductID.core.contains(Store.ProductID.monthInvite))
        XCTAssertTrue(Store.ProductID.all.contains(Store.ProductID.monthInvite))
        XCTAssertFalse(SubscriptionPlan.cards(selecting: .monthly).contains(.monthInvite))
    }

    /// Choices only, never a title, a name or anything measured.
    func test_feedEventsCarryChoicesOnly() {
        typealias E = Analytics.Event
        let cases: [(E, String, [String])] = [
            (.postCreated(hasPhoto: true, logged: false), "post_created", ["has_photo", "logged"]),
            (.kudosGiven(emoji: "🔥", via: "double_tap"), "kudos_given", ["emoji", "via"]),
            (.postReported, "post_reported", []),
            (.invitePaywallViewed, "invite_paywall_viewed", []),
        ]
        for (event, name, keys) in cases {
            XCTAssertEqual(event.name, name)
            XCTAssertEqual(Set(event.properties.keys), Set(keys), name)
        }
    }

    func test_inviteMessageSaysTheFreeMonth() {
        let text = InviteCode.message(for: "AZIZK7QX4")
        XCTAssertTrue(text.hasPrefix("Meditate with me on 808. Use my code for a free month: AZIZ-K7QX4"))
        XCTAssertFalse(text.contains("\u{2014}"))
    }
}
