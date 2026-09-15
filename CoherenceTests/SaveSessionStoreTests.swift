import XCTest
import SwiftData
@testable import Coherence

/// Save session writes the title, the public description and who can see a
/// session onto the reflection, without touching the rating, and keeps the
/// private note separate from anything posted.
final class SaveSessionStoreTests: XCTestCase {
    private var container: ModelContainer?

    @MainActor
    private func context() -> ModelContext {
        let c = Persistence.inMemory()
        container = c
        return ModelContext(c)
    }

    @MainActor
    func test_saveSessionKeepsRatingAndSeparatesNotes() {
        let ctx = context()
        let id = UUID()
        SessionStore.saveReflection(sessionID: id, rating: 8, note: "old", technique: nil, in: ctx)
        let row = SessionStore.saveSession(sessionID: id, title: "  Roof  ", publicNote: " Cold air ",
                                           privateNote: "mind wandered at 10", visibility: "friends",
                                           technique: "guided", in: ctx)
        XCTAssertEqual(row.rating, 8, "Save session never overwrites the rating")
        XCTAssertEqual(row.title, "Roof")
        XCTAssertEqual(row.publicNote, "Cold air")
        XCTAssertEqual(row.note, "mind wandered at 10", "the private note is the reflection note")
        XCTAssertEqual(row.visibility, "friends")
        XCTAssertEqual(row.technique, "guided")
        let fetched = (try? ctx.fetch(FetchDescriptor<SessionReflection>())) ?? []
        XCTAssertEqual(fetched.count, 1, "one reflection per session")
    }

    @MainActor
    func test_sessionsSavedBeforeThisBuildArePrivate() {
        let ctx = context()
        let row = SessionStore.saveReflection(sessionID: UUID(), rating: 5, note: "", in: ctx)
        XCTAssertEqual(row.visibility, "private")
    }

    func test_defaultTitleFollowsTheHour() {
        let cal = Calendar(identifier: .gregorian)
        func at(_ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: h))! }
        XCTAssertEqual(SessionStore.defaultTitle(for: at(7), calendar: cal), "Morning meditation")
        XCTAssertEqual(SessionStore.defaultTitle(for: at(13), calendar: cal), "Afternoon meditation")
        XCTAssertEqual(SessionStore.defaultTitle(for: at(19), calendar: cal), "Evening meditation")
        XCTAssertEqual(SessionStore.defaultTitle(for: at(2), calendar: cal), "Night meditation")
    }
}

final class CreateProfileTests: XCTestCase {
    /// Offered when a handle is taken: all valid handles, all within the
    /// length limit, none equal to the taken one.
    func test_alternativesAreValidHandles() {
        for taken in ["aziz", "jordan.k", String(repeating: "a", count: Username.maxLength)] {
            let alts = CreateProfileView.alternatives(for: taken)
            XCTAssertFalse(alts.isEmpty)
            for alt in alts {
                XCTAssertEqual(Username.normalize(alt), alt, "\(alt) must already be normalised")
                XCTAssertLessThanOrEqual(alt.count, Username.maxLength)
                XCTAssertNotEqual(alt, taken)
            }
        }
    }
}
