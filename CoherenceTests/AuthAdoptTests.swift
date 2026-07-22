import XCTest
import SwiftData
@testable import Coherence

/// Phase-7 account-matching correctness: first sign-in must ADOPT the bootstrap
/// User (so pre-account sessions + streak survive), a returning sign-in must match
/// the same User, and neither may ever create a duplicate.
final class AuthAdoptTests: XCTestCase {

    private func makeContext() -> ModelContext {
        ModelContext(Persistence.inMemory())
    }

    private func users(_ ctx: ModelContext) -> [User] {
        (try? ctx.fetch(FetchDescriptor<User>())) ?? []
    }

    private func onboarded(_ ctx: ModelContext) -> Bool {
        ((try? ctx.fetch(FetchDescriptor<Preferences>())) ?? []).contains { $0.onboardingComplete }
    }

    func test_signIn_adoptsBootstrapUser() {
        let ctx = makeContext()
        let bootstrapID = SessionStore.currentUser(in: ctx).id   // creates bootstrap + prefs

        let user = SessionStore.signIn(appleUserID: "APPLE_1", email: "mel@x.com", displayName: "Mel", in: ctx)

        XCTAssertEqual(user.id, bootstrapID, "should adopt the bootstrap row, not create a second User")
        XCTAssertEqual(user.appleUserID, "APPLE_1")
        XCTAssertEqual(user.email, "mel@x.com")
        XCTAssertEqual(users(ctx).count, 1)
        XCTAssertTrue(onboarded(ctx))
    }

    func test_signIn_matchesExistingUserOnSecondSignIn() {
        let ctx = makeContext()
        _ = SessionStore.currentUser(in: ctx)
        let first = SessionStore.signIn(appleUserID: "APPLE_1", email: "mel@x.com", displayName: "Mel", in: ctx)
        // Apple omits name/email on subsequent sign-ins — pass nil; identity must persist.
        let second = SessionStore.signIn(appleUserID: "APPLE_1", email: nil, displayName: nil, in: ctx)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.email, "mel@x.com", "existing email must not be wiped by a later nil")
        XCTAssertEqual(users(ctx).count, 1)
    }

    func test_signIn_createsWhenNoBootstrap() {
        let ctx = makeContext()
        let user = SessionStore.signIn(appleUserID: "APPLE_2", email: nil, displayName: nil, in: ctx)

        XCTAssertEqual(user.appleUserID, "APPLE_2")
        XCTAssertEqual(users(ctx).count, 1)
        XCTAssertTrue(onboarded(ctx))
    }

    func test_completeOnboardingWithoutSignIn_keepsBootstrap() {
        let ctx = makeContext()
        SessionStore.completeOnboardingWithoutSignIn(in: ctx)

        XCTAssertEqual(users(ctx).count, 1)
        XCTAssertEqual(users(ctx).first?.appleUserID, "", "dev skip must leave the row a bootstrap")
        XCTAssertTrue(onboarded(ctx))
    }
}
