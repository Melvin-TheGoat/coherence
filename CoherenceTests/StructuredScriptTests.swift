import XCTest
@testable import Coherence

/// The structured (non-narrated) guidance arc. What matters: the five movements
/// survive at every session length, cues never stack up faster than someone
/// with their eyes shut can follow, and the arc stays in order.
final class StructuredScriptTests: XCTestCase {

    func test_everyStepAppears_evenOnAShortSession() {
        for minutes in [2, 5, 10, 15, 25] {
            let cues = StructuredScript.cues(forDurationSec: Double(minutes) * 60)
            let steps = Set(cues.map(\.step))
            XCTAssertEqual(steps.count, StructuredScript.Step.allCases.count,
                           "a \(minutes)-minute session lost a step")
        }
    }

    func test_stepsRunInOrder() {
        let cues = StructuredScript.cues(forDurationSec: 15 * 60)
        let order = StructuredScript.Step.allCases
        var lastIndex = -1
        for cue in cues {
            let i = order.firstIndex(of: cue.step)!
            XCTAssertGreaterThanOrEqual(i, lastIndex, "steps came out of order at \(cue.text)")
            lastIndex = i
        }
    }

    func test_cuesAreChronological() {
        let cues = StructuredScript.cues(forDurationSec: 10 * 60)
        XCTAssertEqual(cues.map(\.at), cues.map(\.at).sorted())
    }

    /// A long session should get the full text; a short one gets the openers.
    func test_longerSessionsCarryMoreLines() {
        let short = StructuredScript.cues(forDurationSec: 2 * 60)
        let long = StructuredScript.cues(forDurationSec: 25 * 60)
        XCTAssertGreaterThan(long.count, short.count)
        XCTAssertGreaterThanOrEqual(short.count, StructuredScript.Step.allCases.count,
                                    "even a 2-minute sit keeps one cue per step")
    }

    /// Everything fits inside the session — a cue arriving after the end would
    /// never be seen.
    func test_noCueLandsAfterTheSessionEnds() {
        let total = 8.0 * 60
        for cue in StructuredScript.cues(forDurationSec: total) {
            XCTAssertLessThan(cue.at, total)
        }
    }

    func test_cueLookupReturnsTheMostRecentDue() {
        let cues = StructuredScript.cues(forDurationSec: 10 * 60)
        XCTAssertNil(StructuredScript.cue(at: -1, in: cues))
        XCTAssertEqual(StructuredScript.cue(at: cues[0].at, in: cues), cues[0])
        // Just before the second cue we should still be showing the first.
        let justBefore = cues[1].at - 0.01
        XCTAssertEqual(StructuredScript.cue(at: justBefore, in: cues), cues[0])
        // Past the end, the last cue stays up.
        XCTAssertEqual(StructuredScript.cue(at: 9_999, in: cues), cues.last)
    }

    func test_zeroDurationProducesNothing() {
        XCTAssertTrue(StructuredScript.cues(forDurationSec: 0).isEmpty)
    }
}
