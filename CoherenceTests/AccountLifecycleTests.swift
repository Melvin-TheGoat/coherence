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
}
