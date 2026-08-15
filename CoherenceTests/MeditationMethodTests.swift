import XCTest
import SwiftData
@testable import Coherence

/// The how-to guide is a running list, so these guard the things that break
/// quietly when someone appends a method: duplicate ids, an unlabelled entry,
/// and the honesty rule that a practice tradition is never dressed as evidence.
final class MeditationMethodTests: XCTestCase {

    func test_idsAreUniqueAcrossMethodsAndVariants() {
        var seen = Set<String>()
        for method in MeditationMethod.all {
            XCTAssertTrue(seen.insert(method.id).inserted, "duplicate id \(method.id)")
            for variant in method.variants {
                XCTAssertTrue(seen.insert(variant.id).inserted, "duplicate id \(variant.id)")
            }
        }
        XCTAssertFalse(seen.contains(MeditationMethod.ownID),
                       "a method collides with the free-text id")
    }

    func test_everyMethodIsComplete() {
        for m in MeditationMethod.all {
            XCTAssertFalse(m.title.isEmpty, "\(m.id) has no title")
            XCTAssertFalse(m.oneLine.isEmpty, "\(m.id) has no one-liner")
            XCTAssertFalse(m.steps.isEmpty, "\(m.id) has no steps")
            XCTAssertFalse(m.purpose.isEmpty, "\(m.id) never says what it's for")
        }
    }

    /// A method with variants is logged BY variant — logging bare
    /// "Manifestation" would lose the distinction the data exists to measure.
    func test_variantsAreWhatGetsLogged() {
        let loggableIDs = Set(MeditationMethod.loggable.map(\.id))
        for m in MeditationMethod.all where !m.variants.isEmpty {
            XCTAssertFalse(loggableIDs.contains(m.id),
                           "\(m.id) is loggable as a whole despite having variants")
            for v in m.variants {
                XCTAssertTrue(loggableIDs.contains(v.id), "\(v.id) can't be logged")
            }
        }
    }

    func test_labelRoundTripsForEveryLoggableID() {
        for item in MeditationMethod.loggable {
            XCTAssertEqual(MeditationMethod.label(for: item.id), item.label)
        }
        XCTAssertEqual(MeditationMethod.label(for: MeditationMethod.ownID), "My own")
        XCTAssertNil(MeditationMethod.label(for: nil), "unreported has no label")
        XCTAssertNil(MeditationMethod.label(for: ""))
    }

    /// Nothing in the guide may claim we measure a brain state, and anything
    /// from a teacher must say it's tradition rather than evidence.
    func test_guideRespectsTheScienceLine() {
        let banned = ["proven", "clinically", "detects theta", "measures theta",
                      "beta state", "alpha state", "reddit"]
        for m in MeditationMethod.all {
            let corpus = ([m.purpose, m.origin, m.oneLine] + m.steps
                          + m.variants.map(\.body)).joined(separator: " ").lowercased()
            for word in banned {
                XCTAssertFalse(corpus.contains(word), "\(m.id) says '\(word)'")
            }
            // Any named teacher, not just the first one we happened to cite.
            // Culadasa holds a neuroscience PhD, which makes his book the most
            // tempting of the lot to dress up as evidence. It is still a book.
            let teachers = ["dispenza", "culadasa", "yates", "goddard", "doty"]
            if teachers.contains(where: { m.origin.lowercased().contains($0) }) {
                XCTAssertTrue(m.origin.contains("not peer-reviewed")
                              || m.origin.contains("not a study"),
                              "\(m.id) cites a teacher without labelling it tradition")
            }
        }
    }

    /// The picker writes through to storage and can be changed afterwards.
    func test_techniquePersistsAndIsEditable() throws {
        let ctx = ModelContext(Persistence.inMemory())
        let sid = UUID()

        _ = SessionStore.saveReflection(sessionID: sid, rating: 7, note: "calm",
                                        technique: "blueSky", in: ctx)
        XCTAssertEqual(SessionStore.reflection(for: sid, in: ctx)?.technique, "blueSky")

        // Changing it doesn't create a second row.
        _ = SessionStore.saveReflection(sessionID: sid, rating: 7, note: "calm",
                                        technique: MeditationMethod.ownID,
                                        techniqueNote: "  humming  ", in: ctx)
        let all = (try? ctx.fetch(FetchDescriptor<SessionReflection>())) ?? []
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.technique, MeditationMethod.ownID)
        XCTAssertEqual(all.first?.techniqueNote, "humming", "free text is trimmed")
    }

    /// Unreported must stay a first-class answer. Forcing a label would poison
    /// the data it exists to collect.
    func test_unreportedIsValid() throws {
        let ctx = ModelContext(Persistence.inMemory())
        let sid = UUID()
        _ = SessionStore.saveReflection(sessionID: sid, rating: 5, note: "", in: ctx)
        XCTAssertNil(SessionStore.reflection(for: sid, in: ctx)?.technique)
    }
}
