import XCTest
import SwiftData
@testable import Coherence

/// Phase-7 account lifecycle: sign-out preserves data, soft-delete stamps
/// `deletedAt`, the 30-day purge removes expired users + their rows (but not
/// recently-deleted ones), and signing back in reactivates.
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
        let longAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        SessionStore.softDeleteCurrentUser(now: longAgo, in: ctx)

        SessionStore.purgeExpired(in: ctx)

        XCTAssertTrue(users(ctx).isEmpty, "expired user hard-deleted")
        XCTAssertTrue(sessions(ctx).isEmpty, "FK'd sessions gone")
        XCTAssertTrue(stats(ctx).isEmpty, "FK'd stats gone")
    }

    func test_purge_keepsRecentlyDeletedUser() {
        let ctx = makeContext()
        _ = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)
        SessionStore.softDeleteCurrentUser(now: Date(), in: ctx)   // just now

        SessionStore.purgeExpired(in: ctx)

        XCTAssertEqual(users(ctx).count, 1, "within the 30-day window, keep it")
    }

    func test_signInAgain_reactivatesSoftDeletedUser() {
        let ctx = makeContext()
        _ = SessionStore.signIn(appleUserID: "A", email: "a@b.com", displayName: "A", in: ctx)
        SessionStore.softDeleteCurrentUser(in: ctx)

        let restored = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)

        XCTAssertNil(restored.deletedAt, "signing back in clears the pending delete")
        XCTAssertEqual(users(ctx).count, 1)
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

        let longAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        SessionStore.softDeleteCurrentUser(now: longAgo, in: ctx)
        SessionStore.purgeExpired(in: ctx)

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

