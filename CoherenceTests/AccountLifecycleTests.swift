import XCTest
import SwiftData
@testable import Coherence

/// Account lifecycle: sign-out preserves data; Delete account removes every
/// row of the person's at once (2026-09-29, App Review 5.1.1(v)) and signing
/// back in finds nothing to restore; the 30-day purge still clears the
/// soft-deleted rows older builds left on phones.
final class AccountLifecycleTests: XCTestCase {

    private func makeContext() -> ModelContext { ModelContext(Persistence.inMemory()) }
    private func users(_ c: ModelContext) -> [User] { (try? c.fetch(FetchDescriptor<User>())) ?? [] }
    private func sessions(_ c: ModelContext) -> [Session] { (try? c.fetch(FetchDescriptor<Session>())) ?? [] }
    private func stats(_ c: ModelContext) -> [MeditationStats] { (try? c.fetch(FetchDescriptor<MeditationStats>())) ?? [] }

    private func seedSession(userID: UUID, in c: ModelContext) {
        let s = Session(userID: userID)
        c.insert(s)
        c.insert(MeditationStats(sessionID: s.id))
        try? c.save()
    }

    func test_signOut_preservesDataButRegatesOnboarding() {
        let ctx = makeContext()
        let user = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)
        seedSession(userID: user.id, in: ctx)

        SessionStore.signOut(in: ctx)

        XCTAssertEqual(users(ctx).count, 1)
        XCTAssertEqual(sessions(ctx).count, 1, "sign-out keeps sessions")
        let prefs = (try? ctx.fetch(FetchDescriptor<Preferences>())) ?? []
        XCTAssertFalse(prefs.contains { $0.onboardingComplete }, "sign-out re-gates onboarding")
    }

    // MARK: - Legacy soft-deleted rows, which older builds left on phones

    func test_softDelete_stampsDeletedAt() {
        let ctx = makeContext()
        _ = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)
        SessionStore.softDeleteCurrentUser(in: ctx)
        XCTAssertNotNil(users(ctx).first?.deletedAt)
    }

    func test_purge_removesUserDeletedOver30DaysAgo_withData() {
        let ctx = makeContext()
        let user = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)
        seedSession(userID: user.id, in: ctx)
        let sid = sessions(ctx)[0].id
        SessionStore.saveReflection(sessionID: sid, rating: 7, note: "n", in: ctx)
        _ = SessionStore.savePhoto(sessionID: sid, jpeg: Data([1]), thumbnail: Data([2]), in: ctx)
        let longAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        // What a build before 2026-09-29 left behind.
        SessionStore.softDeleteCurrentUser(now: longAgo, in: ctx)

        SessionStore.purgeExpired(in: ctx)

        XCTAssertTrue(users(ctx).isEmpty, "expired user hard-deleted")
        XCTAssertTrue(sessions(ctx).isEmpty, "FK'd sessions gone")
        XCTAssertTrue(stats(ctx).isEmpty, "FK'd stats gone")
        XCTAssertEqual(count(SessionReflection.self, ctx), 0)
        XCTAssertEqual(count(SessionPhoto.self, ctx), 0)
        XCTAssertEqual(count(Preferences.self, ctx), 0)
    }

    func test_purge_keepsRecentlyDeletedUser() {
        let ctx = makeContext()
        _ = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)
        SessionStore.softDeleteCurrentUser(now: Date(), in: ctx)   // just now

        SessionStore.purgeExpired(in: ctx)

        XCTAssertEqual(users(ctx).count, 1, "within the 30-day window, keep it")
    }

    // MARK: - Delete account is immediate (2026-09-29)

    private func freshDefaults() -> UserDefaults {
        let name = "AccountLifecycleTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func count<T: PersistentModel>(_ type: T.Type, _ c: ModelContext) -> Int {
        (try? c.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    func test_deleteAccount_removesEveryRowAtOnce() {
        let ctx = makeContext()
        let user = SessionStore.signIn(appleUserID: "A", email: "a@b.com", displayName: "A", in: ctx)
        seedSession(userID: user.id, in: ctx)
        let s = Session(userID: user.id)
        ctx.insert(s)
        ctx.insert(MeditationStats(sessionID: s.id))
        SessionStore.saveReflection(sessionID: s.id, rating: 8, note: "calm", in: ctx)
        _ = SessionStore.savePhoto(sessionID: s.id, jpeg: Data([1]), thumbnail: Data([2]), in: ctx)
        // What an older install can also hold: a stray bootstrap with its own
        // session, and rows nobody owns.
        let stray = User(appleUserID: "")
        ctx.insert(stray)
        seedSession(userID: stray.id, in: ctx)
        let orphan = Session(userID: nil)
        ctx.insert(orphan)
        ctx.insert(MeditationStats(sessionID: UUID()))
        try? ctx.save()

        SessionStore.deleteAccountNow(in: ctx, defaults: freshDefaults())

        XCTAssertEqual(count(User.self, ctx), 0, "every account row, signed in or bootstrap")
        XCTAssertEqual(count(Preferences.self, ctx), 0)
        XCTAssertEqual(count(Session.self, ctx), 0, "every session, owned or not")
        XCTAssertEqual(count(MeditationStats.self, ctx), 0, "the device-local measurements too")
        XCTAssertEqual(count(SessionReflection.self, ctx), 0)
        XCTAssertEqual(count(SessionPhoto.self, ctx), 0)
    }

    func test_deleteAccount_keepsTheBuiltInTracks() {
        let ctx = makeContext()
        TrackSeeder.seedIfNeeded(in: ctx)
        let tracks = count(MeditationTrack.self, ctx)
        _ = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)

        SessionStore.deleteAccountNow(in: ctx, defaults: freshDefaults())

        XCTAssertEqual(count(MeditationTrack.self, ctx), tracks, "the catalog is the app's, not the person's")
    }

    /// Replaces the old "signing back in within 30 days restores it": there
    /// is no window any more, and nothing to restore.
    func test_signInAgainAfterDelete_startsAnEmptyAccount() {
        let ctx = makeContext()
        let old = SessionStore.signIn(appleUserID: "A", email: "a@b.com", displayName: "A", in: ctx)
        seedSession(userID: old.id, in: ctx)
        SessionStore.deleteAccountNow(in: ctx, defaults: freshDefaults())

        let again = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)

        XCTAssertNotEqual(again.id, old.id, "a new account, not the deleted one")
        XCTAssertNil(again.displayName, "nothing of the old account comes back")
        XCTAssertEqual(users(ctx).count, 1)
        XCTAssertTrue(sessions(ctx).isEmpty)
    }

    func test_deleteAccount_thenStartingOver_writesToAFreshAccount() {
        let ctx = makeContext()
        let first = SessionStore.currentUser(in: ctx)
        seedSession(userID: first.id, in: ctx)
        SessionStore.deleteAccountNow(in: ctx, defaults: freshDefaults())

        let next = SessionStore.currentUser(in: ctx)
        let kept = SessionStore.persistPhoneSession(id: UUID(), startedAt: Date(), mode: "silence",
                                                    durationSec: 600, in: ctx)

        XCTAssertNotEqual(next.id, first.id)
        XCTAssertEqual(sessions(ctx).map(\.id), [kept?.id].compactMap { $0 })
        XCTAssertEqual(kept?.userID, next.id)
    }

    func test_deleteAccount_forgetsThePersonsBookkeeping_notTheDevices() {
        let d = freshDefaults()
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400 * 40)
        d.set(["streak3", "first"], forKey: "awardsAnnounced.v1")
        d.set(yesterday, forKey: "awardsLastCheck.v1")
        d.set(2, forKey: "awardsCatalogVersion.v1")
        d.set(yesterday, forKey: OttoAura.glowStartKey)
        PendingSave.set(UUID(), in: d)
        SessionDetails.set(UUID(), in: d)
        d.set(Data([1]), forKey: OnboardingResume.key)
        d.set(true, forKey: OnboardingResume.reviewAskedKey)
        d.set(true, forKey: OnboardingHandoff.key)
        // The device's, not the person's.
        d.set(true, forKey: "paywall.firstSessionShown.v1")
        d.set(true, forKey: "community.pendingAccountDeletion.v1")
        d.set("rain", forKey: "sessionSoundID")

        SessionStore.deleteAccountNow(now: now, in: makeContext(), defaults: d)

        XCTAssertNil(d.stringArray(forKey: "awardsAnnounced.v1"), "the next person's awards announce")
        XCTAssertEqual(d.object(forKey: "awardsLastCheck.v1") as? Date, now,
                       "the watermark moves to the deletion, so no award is swallowed as backfill")
        XCTAssertEqual(d.integer(forKey: "awardsCatalogVersion.v1"), 2)
        XCTAssertEqual(OttoAura.glowStart(defaults: d), Calendar.current.startOfDay(for: now),
                       "the glow starts over today")
        XCTAssertNil(PendingSave.read(now: now, in: d))
        XCTAssertNil(SessionDetails.read(in: d))
        XCTAssertNil(d.object(forKey: OnboardingResume.key))
        XCTAssertNil(d.object(forKey: OnboardingResume.reviewAskedKey))
        XCTAssertNil(d.object(forKey: OnboardingHandoff.key))
        XCTAssertTrue(d.bool(forKey: "paywall.firstSessionShown.v1"), "paywall state is not the person's")
        XCTAssertTrue(d.bool(forKey: "community.pendingAccountDeletion.v1"), "the Friends retry must survive")
        XCTAssertEqual(d.string(forKey: "sessionSoundID"), "rain")
    }

    // MARK: - Who owns a session (2026-09-29, the pre-1.1 audit)

    /// Through the real save path, not a hand-made `Session(userID:)`: that
    /// is how the old tests missed a session filed under a stray bootstrap
    /// row, which Delete account then never reached.
    func test_sessionSavedAfterSignIn_isDeletedWithTheAccount() {
        let ctx = makeContext()
        let user = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)
        let saved = SessionStore.persistPhoneSession(id: UUID(), startedAt: Date(), mode: "silence",
                                                     durationSec: 600, in: ctx)
        XCTAssertEqual(saved?.userID, user.id, "a session belongs to the signed-in account")

        SessionStore.deleteAccountNow(in: ctx, defaults: freshDefaults())

        XCTAssertTrue(sessions(ctx).isEmpty, "Delete account reaches every session")
    }

    func test_strayBootstrapSessions_areAdoptedByTheSignedInAccount() {
        let ctx = makeContext()
        let user = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)
        // What an install that signed in before the fix holds: a second
        // bootstrap row owning a session.
        let stray = User(appleUserID: "")
        ctx.insert(stray)
        seedSession(userID: stray.id, in: ctx)

        SessionStore.repairOwnership(in: ctx)

        XCTAssertEqual(sessions(ctx).map(\.userID), [user.id])
    }

    func test_deleteWithoutSigningIn_newSessionsSurviveThePurge() {
        let ctx = makeContext()
        let first = SessionStore.currentUser(in: ctx)
        seedSession(userID: first.id, in: ctx)
        let longAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        SessionStore.softDeleteCurrentUser(now: longAgo, in: ctx)

        // Starting over after deleting: a fresh bootstrap, never the deleted one.
        let next = SessionStore.currentUser(in: ctx)
        XCTAssertNotEqual(next.id, first.id)
        let kept = SessionStore.persistPhoneSession(id: UUID(), startedAt: Date(), mode: "silence",
                                                    durationSec: 600, in: ctx)
        SessionStore.purgeExpired(in: ctx)

        XCTAssertEqual(sessions(ctx).map(\.id), [kept?.id].compactMap { $0 },
                       "the deleted account's session goes, the new one stays")
    }

    func test_signIn_neverAdoptsADeletedBootstrap() {
        let ctx = makeContext()
        let old = SessionStore.currentUser(in: ctx)
        SessionStore.softDeleteCurrentUser(in: ctx)

        let user = SessionStore.signIn(appleUserID: "B", email: nil, displayName: nil, in: ctx)

        XCTAssertNotEqual(user.id, old.id)
        XCTAssertNotNil(users(ctx).first { $0.id == old.id }?.deletedAt, "the deleted row stays deleted")
    }

    /// An account deleted under 1.0 stamped only the signed-in row; the stray
    /// bootstrap made while it was signed in must go with it.
    func test_accountDeletedUnderOldBuild_takesItsStrayRowWithIt() {
        let ctx = makeContext()
        let user = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)
        let stray = User(appleUserID: "")
        ctx.insert(stray)
        seedSession(userID: stray.id, in: ctx)
        let longAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        stray.createdAt = Calendar.current.date(byAdding: .day, value: -45, to: Date())!
        user.deletedAt = longAgo              // what the old softDelete did
        try? ctx.save()

        SessionStore.repairOwnership(in: ctx)
        SessionStore.purgeExpired(in: ctx)

        XCTAssertTrue(sessions(ctx).isEmpty, "the stray row's sessions go with the deleted account")
    }
}

