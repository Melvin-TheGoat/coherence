import XCTest
@testable import Coherence

/// The spoken verdict is rules over measured numbers — no AI, no network.
/// These lock the contract that matters: every sentence states something the
/// signals actually show, and a weak session is coached honestly, never shamed.
final class VerdictEngineTests: XCTestCase {

    func test_strongSession_namesEverySignal() {
        let v = VerdictEngine.verdict(for: .init(
            overallScore: 0.81, stillnessScore: 0.88, hrDecline: 11,
            meanBreathingRate: 5.8, resonanceMatchScore: 0.72, bellyBreathing: true))
        XCTAssertEqual(v.headline, "Your practice landed.")
        XCTAssertTrue(v.sentence.contains("11 beats"), v.sentence)
        XCTAssertTrue(v.sentence.contains("resonance"), v.sentence)
        XCTAssertTrue(v.sentence.contains("still"), v.sentence)
    }

    func test_restlessSession_isHonestNotHarsh() {
        let v = VerdictEngine.verdict(for: .init(
            overallScore: 0.2, stillnessScore: 0.3, hrDecline: -8, bellyBreathing: false)
        )
        XCTAssertEqual(v.headline, "A restless one — that happens.")
        XCTAssertTrue(v.sentence.contains("restless"), v.sentence)
        // No shame words, and never a claim the numbers don't support.
        XCTAssertFalse(v.sentence.lowercased().contains("fail"))
        XCTAssertFalse(v.sentence.contains("resonance"))
    }

    func test_noSignals_neverInventsAClaim() {
        let v = VerdictEngine.verdict(for: .init(overallScore: 0.3))
        XCTAssertFalse(v.sentence.isEmpty)
        XCTAssertTrue(v.sentence.contains("streak") || v.sentence.contains("faint"), v.sentence)
    }

    /// A Regular session has no breath signal — the verdict must not mention one
    /// even if stale rate values were somehow present.
    func test_regularSession_neverClaimsBreath() {
        let v = VerdictEngine.verdict(for: .init(
            overallScore: 0.7, stillnessScore: 0.9, hrDecline: 6,
            meanBreathingRate: 5.5, resonanceMatchScore: 0.9, bellyBreathing: false))
        XCTAssertFalse(v.sentence.contains("resonance"), v.sentence)
        XCTAssertFalse(v.sentence.contains("breath"), v.sentence)
    }

    func test_hrReading_readsStartToEnd() {
        XCTAssertEqual(VerdictEngine.hrReading(start: 74.4, end: 62.6), "74 → 63 bpm")
        XCTAssertNil(VerdictEngine.hrReading(start: nil, end: 63))
    }

    func test_stillnessReading_findsWhenItSettled() {
        // Crosses 0.8 at index 6 with hop 5 s → minute 0.5 → rounds to "min 1".
        let points = [0.2, 0.3, 0.4, 0.55, 0.7, 0.75, 0.82, 0.9, 0.88, 0.91]
        XCTAssertEqual(VerdictEngine.stillnessReading(points: points, hopSec: 5), "settled by min 1")
    }

    func test_stillnessReading_restlessThroughout() {
        let points = [0.2, 0.3, 0.25, 0.4, 0.31, 0.28]
        XCTAssertEqual(VerdictEngine.stillnessReading(points: points, hopSec: 5), "restless throughout")
    }

    func test_breathReading_callsOutResonance() {
        XCTAssertEqual(VerdictEngine.breathReading(meanRate: 5.8, resonance: 0.7), "held near 6/min")
        XCTAssertEqual(VerdictEngine.breathReading(meanRate: 11.2, resonance: 0.1), "averaged 11.2/min")
        XCTAssertNil(VerdictEngine.breathReading(meanRate: nil, resonance: 0.7))
    }
}
