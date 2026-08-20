import XCTest
@testable import Coherence

/// The spoken verdict is rules over measured numbers — no AI, no network.
/// These lock the contract that matters: every sentence states something the
/// signals actually show, and a weak session is coached honestly, never shamed.
final class VerdictEngineTests: XCTestCase {

    /// One voice. The verdict is a single sentence naming every measured
    /// signal once. There used to be a second, teal "coupling" line under it
    /// built from the same numbers; Melvin and Aziz cut it because two
    /// explanations of one meditation is one too many.
    func test_strongSession_namesEverySignalInOneSentence() {
        let v = VerdictEngine.verdict(for: .init(
            overallScore: 0.81, stillnessScore: 0.88, hrDecline: 11,
            meanBreathingRate: 5.8, resonanceMatchScore: 0.72,
            breathDoorwayRate: 5.8, breathDoorwayHeldSec: 180, bellyBreathing: true))
        XCTAssertEqual(v.headline, "Your practice landed.")
        XCTAssertTrue(v.sentence.contains("11 beats"), v.sentence)
        XCTAssertTrue(v.sentence.contains("breath slowed"), v.sentence)
        XCTAssertTrue(v.sentence.contains("still"), v.sentence)
    }

    func test_restlessSession_isHonestNotHarsh() {
        let v = VerdictEngine.verdict(for: .init(
            overallScore: 0.2, stillnessScore: 0.3, hrDecline: -8, bellyBreathing: false)
        )
        XCTAssertEqual(v.headline, "A restless one. That happens.")
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

    /// No breathing data → no breath claim. The rule used to be "never mention
    /// breath on a non-belly session"; since the wrist path (2026-08-07) any
    /// session may carry a real breath reading, so the gate moved from the
    /// mode flag to data presence. The engine only populates breathing when it
    /// genuinely read one, so nil stays an absolute silence.
    func test_sessionWithoutBreathingData_neverClaimsBreath() {
        let v = VerdictEngine.verdict(for: .init(
            overallScore: 0.7, stillnessScore: 0.9, hrDecline: 6,
            meanBreathingRate: nil, resonanceMatchScore: nil, bellyBreathing: false))
        XCTAssertFalse(v.sentence.contains("resonance"), v.sentence)
        XCTAssertFalse(v.sentence.contains("breath"), v.sentence)
    }

    /// The other direction: a wrist session that DID read a breath is allowed
    /// to say so, belly flag or no belly flag.
    func test_wristSessionWithBreathingData_mayClaimBreath() {
        let v = VerdictEngine.verdict(for: .init(
            overallScore: 0.8, stillnessScore: 0.9, hrDecline: 2,
            meanBreathingRate: 5.8, resonanceMatchScore: 0.9,
            breathDoorwayRate: 5.8, breathDoorwayHeldSec: 200, bellyBreathing: false))
        // Lowercased: this claim leads the sentence here, so it is capitalised.
        XCTAssertTrue(v.sentence.lowercased().contains("breath slowed"), v.sentence)
    }

    /// A session read at natural pace has no doorway, so the score's breath
    /// term is absent — and the verdict must SAY so rather than fall silent on
    /// its largest component, which is what it used to do above 8/min.
    func test_readAtNaturalPace_saysSoRatherThanNothing() {
        let v = VerdictEngine.verdict(for: .init(
            overallScore: 0.6, stillnessScore: 0.9, hrDecline: 5,
            meanBreathingRate: 12.4, resonanceMatchScore: 0.02,
            breathDoorwayRate: nil, breathDoorwayHeldSec: nil))
        XCTAssertTrue(v.sentence.contains("own pace"), v.sentence)
        XCTAssertFalse(v.sentence.contains("slowed"), v.sentence)
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

    func test_breathReading_namesTheDoorwayWhenThereWasOne() {
        XCTAssertEqual(VerdictEngine.breathReading(meanRate: 9.1, doorwayRate: 5.8,
                                                   doorwayHeldSec: 190),
                       "slowed to 5.8/min for 3:10")
        XCTAssertEqual(VerdictEngine.breathReading(meanRate: 11.2, doorwayRate: nil,
                                                   doorwayHeldSec: nil),
                       "averaged 11.2/min")
        XCTAssertNil(VerdictEngine.breathReading(meanRate: nil, doorwayRate: nil,
                                                 doorwayHeldSec: nil))
    }

    // MARK: - Standing (this session vs the user's own history)

    /// The whole point of relative scoring: with too little history, any
    /// comparison is noise. Say nothing rather than something shaky.
    func test_standing_saysNothingBeforeEnoughHistory() {
        for count in 0..<VerdictEngine.minimumHistory {
            let history = Array(repeating: 0.5, count: count)
            XCTAssertNil(VerdictEngine.standing(score: 0.9, history: history),
                         "claimed a standing with only \(count) prior sessions")
        }
    }

    func test_standing_countsHowManyItBeat() {
        // 6 priors, this session beats 4 of them.
        let history = [0.9, 0.85, 0.4, 0.3, 0.2, 0.1]
        XCTAssertEqual(VerdictEngine.standing(score: 0.5, history: history),
                       "calmer than 4 of your last 6")
    }

    func test_standing_recognisesABest() {
        let history = [0.5, 0.4, 0.6, 0.3, 0.2]
        XCTAssertEqual(VerdictEngine.standing(score: 0.95, history: history),
                       "your stillest session yet")
    }

    /// A bad session is described plainly, never with a score-shaped insult.
    func test_standing_worstIsHonestNotHarsh() {
        let history = [0.5, 0.4, 0.6, 0.3, 0.2]
        let s = VerdictEngine.standing(score: 0.05, history: history)
        XCTAssertEqual(s, "a quieter showing than usual")
        XCTAssertFalse(s!.contains("worst"))
    }

    /// Only the last 10 count, so an old run of great sessions can't make every
    /// later one read as a failure.
    func test_standing_windowsToTen() {
        let history = Array(repeating: 0.99, count: 30)
        XCTAssertEqual(VerdictEngine.standing(score: 0.5, history: history),
                       "a quieter showing than usual")
        XCTAssertNil(VerdictEngine.standing(score: nil, history: history))
    }

    /// Nothing the engine can say may imply we measured a brain state.
    func test_noVerdictClaimsABrainState() {
        let inputs: [VerdictEngine.Inputs] = [
            .init(overallScore: 0.95, stillnessScore: 0.95, hrDecline: 20,
                  meanBreathingRate: 6, resonanceMatchScore: 0.9,
                  breathDoorwayRate: 6, breathDoorwayHeldSec: 240, bellyBreathing: true),
            .init(overallScore: 0.1, stillnessScore: 0.1, hrDecline: -10),
            .init(overallScore: 0.5),
        ]
        let banned = ["theta", "brain", "subconscious", "probability", "likely"]
        for i in inputs {
            let v = VerdictEngine.verdict(for: i)
            let text = (v.headline + " " + v.sentence).lowercased()
            for word in banned {
                XCTAssertFalse(text.contains(word), "verdict said '\(word)': \(text)")
            }
        }
    }
}
