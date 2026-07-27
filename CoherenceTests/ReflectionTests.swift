import XCTest
import SwiftData
@testable import Coherence

/// Post-session reflection persistence: one row per session (upsert), and the
/// account purge removes reflections along with the rest of the user's data.
final class ReflectionTests: XCTestCase {

    private func makeContext() -> ModelContext { ModelContext(Persistence.inMemory()) }
    private func reflections(_ c: ModelContext) -> [SessionReflection] {
        (try? c.fetch(FetchDescriptor<SessionReflection>())) ?? []
    }

    func test_saveReflection_createsThenUpdatesOneRow() {
        let ctx = makeContext()
        let sid = UUID()

        SessionStore.saveReflection(sessionID: sid, rating: 7, note: "  calm  ", in: ctx)
        XCTAssertEqual(reflections(ctx).count, 1)
        XCTAssertEqual(SessionStore.reflection(for: sid, in: ctx)?.rating, 7)
        XCTAssertEqual(SessionStore.reflection(for: sid, in: ctx)?.note, "calm", "note is trimmed")

        // Saving again updates the same row, never adds a second.
        SessionStore.saveReflection(sessionID: sid, rating: 9, note: "great", in: ctx)
        XCTAssertEqual(reflections(ctx).count, 1)
        XCTAssertEqual(SessionStore.reflection(for: sid, in: ctx)?.rating, 9)
    }

    func test_purge_removesReflections() {
        let ctx = makeContext()
        let user = SessionStore.signIn(appleUserID: "A", email: nil, displayName: nil, in: ctx)
        let session = Session(userID: user.id)
        ctx.insert(session)
        SessionStore.saveReflection(sessionID: session.id, rating: 8, note: "n", in: ctx)
        let longAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        SessionStore.softDeleteCurrentUser(now: longAgo, in: ctx)

        SessionStore.purgeExpired(in: ctx)

        XCTAssertTrue(reflections(ctx).isEmpty, "reflections purged with the user's data")
    }
}
