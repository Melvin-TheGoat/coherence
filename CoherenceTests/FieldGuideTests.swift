import XCTest
@testable import Coherence

/// The Field Guide's contract is editorial, so these tests guard the editorial
/// rules — the ones that are easy to break later with a well-meaning edit.
final class FieldGuideTests: XCTestCase {

    func test_fiveStepsInOrder() {
        XCTAssertEqual(FieldGuide.steps.map(\.id), [1, 2, 3, 4, 5])
    }

    /// Each guide step maps to a real movement of the in-session cue timeline,
    /// so the thing you read beforehand is the thing you're walked through.
    func test_everyStepMapsToTheInSessionScript() {
        let scriptSteps = Set(StructuredScript.Step.allCases)
        for step in FieldGuide.steps {
            XCTAssertTrue(scriptSteps.contains(step.scriptStep),
                          "step \(step.id) points at a movement the script doesn't have")
        }
    }

    /// Every DOI must look like a DOI. A citation nobody can check is worse
    /// than no citation.
    func test_everyCitationCarriesAPlausibleDOI() {
        for c in FieldGuide.allCitations {
            XCTAssertTrue(c.doi.hasPrefix("10."), "\(c.authors): '\(c.doi)' isn't a DOI")
            XCTAssertTrue(c.doi.contains("/"), "\(c.authors): '\(c.doi)' isn't a DOI")
            XCTAssertFalse(c.title.isEmpty)
            XCTAssertFalse(c.venue.isEmpty)
        }
    }

    /// THE rule this section exists for: teachers and traditions are never
    /// presented as citations. Goddard, Maltz, Proctor and Dispenza may appear
    /// as sources; they may not appear in the peer-reviewed list.
    func test_lineageIsNeverPresentedAsEvidence() {
        let teachers = ["goddard", "maltz", "proctor", "dispenza", "doty"]
        for c in FieldGuide.allCitations {
            let authors = c.authors.lowercased()
            for teacher in teachers {
                XCTAssertFalse(authors.contains(teacher),
                               "\(teacher) appears as a peer-reviewed citation")
            }
        }
    }

    /// A step may legitimately have no measured evidence — but then it must not
    /// pretend otherwise, and the prose has to admit it.
    func test_stepsWithoutCitationsSaySoPlainly() {
        for step in FieldGuide.steps where step.citations.isEmpty {
            let prose = step.measured.lowercased()
            XCTAssertTrue(prose.contains("not") || prose.contains("honestly"),
                          "step \(step.id) has no citations but doesn't admit it")
        }
    }

    /// Nothing in the guide may claim 808 measures a brain state.
    func test_guideNeverClaimsWeMeasureTheBrain() {
        let banned = ["we measure your brain", "detects theta", "measures theta",
                      "probability you entered"]
        var corpus = FieldGuide.intro
        for step in FieldGuide.steps {
            corpus += step.measured + step.technique + step.oneLine + step.doThis.joined()
        }
        let text = corpus.lowercased()
        for phrase in banned {
            XCTAssertFalse(text.contains(phrase), "guide claims: \(phrase)")
        }
    }

    /// The three headline findings Melvin asked for are actually present.
    func test_introNamesTheThreeFindings() {
        let intro = FieldGuide.intro.lowercased()
        for term in ["gray matter", "neuroplasticity", "default mode network"] {
            XCTAssertTrue(intro.contains(term), "intro never mentions \(term)")
        }
    }

    func test_everyStepHasSomethingToDo() {
        for step in FieldGuide.steps {
            XCTAssertFalse(step.doThis.isEmpty, "step \(step.id) has no instructions")
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.oneLine.isEmpty)
        }
    }
}
