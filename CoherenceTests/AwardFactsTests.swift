import XCTest
import SwiftData
@testable import Coherence

/// `AwardFacts.build` is the one seam where `AwardEngine`, which never
/// imports SwiftData, meets the real stored rows. A bug here would silently
/// disagree with every `AwardEngineTests` assertion, which only ever hands
/// the engine hand-built `SessionFact` values.
@MainActor
final class AwardFactsTests: XCTestCase {

    // The container is held: a ModelContext does not retain it in tests.
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() {
        super.setUp()
        container = Persistence.inMemory()
        ctx = ModelContext(container)
    }

    override func tearDown() {
        ctx = nil
        container = nil
        super.tearDown()
    }

    func test_buildJoinsStatsReflectionsAndPhotosBySessionID() {
        let started = Date().addingTimeInterval(-3600)
        let session = Session(id: UUID(), mode: "guided", frequencyID: "guided.identity",
                              startedAt: started, durationSec: 1560, source: "watch")
        ctx.insert(session)

        let stats = MeditationStats(id: UUID(), sessionID: session.id, overallScore: 0.82)
        ctx.insert(stats)

        let reflection = SessionReflection(id: UUID(), sessionID: session.id,
                                           rating: 8, note: "felt good", technique: "breathwork")
        ctx.insert(reflection)

        let photo = SessionPhoto(id: UUID(), sessionID: session.id, jpeg: Data([0x1]))
        ctx.insert(photo)

        try? ctx.save()

        let facts = AwardFacts.build(sessions: [session], stats: [stats],
                                     reflections: [reflection], photos: [photo])
        XCTAssertEqual(facts.count, 1)
        let fact = facts[0]
        XCTAssertEqual(fact.overallScore, 0.82)
        XCTAssertEqual(fact.mode, "guided")
        XCTAssertEqual(fact.soundID, "guided.identity")
        XCTAssertEqual(fact.technique, "breathwork")
        XCTAssertEqual(fact.rating, 8)
        XCTAssertTrue(fact.hasNote)
        XCTAssertTrue(fact.hasPhoto)
        XCTAssertFalse(fact.isLogged)
    }

    func test_buildLeavesFactsEmptyWhenNothingIsAttached() {
        let session = Session(id: UUID(), source: "logged")
        ctx.insert(session)
        try? ctx.save()

        let fact = AwardFacts.build(sessions: [session], stats: [], reflections: [], photos: []).first!
        XCTAssertNil(fact.overallScore)
        XCTAssertNil(fact.technique)
        XCTAssertNil(fact.rating)
        XCTAssertFalse(fact.hasNote)
        XCTAssertFalse(fact.hasPhoto)
        XCTAssertTrue(fact.isLogged)
    }

    /// A blank note must not count as having written one: the reflection
    /// card can leave a field focused, then emptied.
    func test_buildTreatsWhitespaceOnlyNotesAsNoNote() {
        let session = Session(id: UUID())
        ctx.insert(session)
        let reflection = SessionReflection(id: UUID(), sessionID: session.id, note: "   ")
        ctx.insert(reflection)
        try? ctx.save()

        let fact = AwardFacts.build(sessions: [session], stats: [], reflections: [reflection],
                                    photos: []).first!
        XCTAssertFalse(fact.hasNote)
    }

    /// A public note (what friends read) counts as a note too, even with no
    /// private one.
    func test_buildCountsAPublicNoteAsANoteToo() {
        let session = Session(id: UUID())
        ctx.insert(session)
        let reflection = SessionReflection(id: UUID(), sessionID: session.id)
        reflection.publicNote = "a good sit"
        ctx.insert(reflection)
        try? ctx.save()

        let fact = AwardFacts.build(sessions: [session], stats: [], reflections: [reflection],
                                    photos: []).first!
        XCTAssertTrue(fact.hasNote)
    }
}
