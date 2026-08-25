import XCTest
@testable import Coherence

/// A free user reads the verdict without the measurements in it.
///
/// **This is a real lock, not a cosmetic one.** "Heart settled 11 beats" is
/// evidence, so leaving it in the sentence would walk straight through the lock
/// on the graph card directly below it, and the whole boundary would be
/// decorative.
final class NumberlessVerdictTests: XCTestCase {

    private let strong = VerdictEngine.Inputs(
        overallScore: 0.82, stillnessScore: 0.91, hrDecline: 11,
        meanBreathingRate: 6.1, resonanceMatchScore: 0.98,
        breathDoorwayRate: 5.8, breathDoorwayHeldSec: 180)

    private let mild = VerdictEngine.Inputs(
        overallScore: 0.48, stillnessScore: 0.70, hrDecline: 5,
        meanBreathingRate: 11.2, breathDoorwayRate: nil, breathDoorwayHeldSec: nil)

    private let restless = VerdictEngine.Inputs(
        overallScore: 0.21, stillnessScore: 0.31, hrDecline: -8)

    /// No digit reaches a free user's sentence, in any claim family.
    func test_numberlessVerdictCarriesNoDigits() {
        for inputs in [strong, mild, restless] {
            let sentence = VerdictEngine.verdict(for: inputs, numbers: false).sentence
            XCTAssertNil(sentence.rangeOfCharacter(from: .decimalDigits),
                         "a number escaped into '\(sentence)'")
        }
    }

    /// The paid verdict still carries them, or the lock is protecting nothing.
    func test_paidVerdictStillCarriesTheNumbers() {
        let sentence = VerdictEngine.verdict(for: strong, numbers: true).sentence
        XCTAssertNotNil(sentence.rangeOfCharacter(from: .decimalDigits))
    }

    /// The headline is the score's own words, so it never changes. A free user
    /// and a paid user who sat the same session are told the same thing landed.
    func test_headlineIsIdenticalEitherWay() {
        for inputs in [strong, mild, restless] {
            XCTAssertEqual(VerdictEngine.verdict(for: inputs, numbers: false).headline,
                           VerdictEngine.verdict(for: inputs, numbers: true).headline)
        }
    }

    /// **The numberless claim must be the same claim.** Free users get a
    /// coarser resolution, never a softer or a different verdict: a session
    /// where the heart settled says so at both tiers.
    func test_sameClaimsAtBothResolutions() {
        let free = VerdictEngine.verdict(for: strong, numbers: false).sentence.lowercased()
        let paid = VerdictEngine.verdict(for: strong, numbers: true).sentence.lowercased()
        for word in ["heart", "breath", "still"] where paid.contains(word) {
            XCTAssertTrue(free.contains(word),
                          "the free verdict dropped the '\(word)' claim instead of its number")
        }
    }

    /// Standing is a measurement of a run of sessions, which is exactly what
    /// the locked home sparkline withholds.
    func test_standingIsNumberlessToo() {
        let history = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7]
        let free = VerdictEngine.standing(score: 0.55, history: history, numbers: false)
        XCTAssertNotNil(free)
        XCTAssertNil(free?.rangeOfCharacter(from: .decimalDigits))
        XCTAssertNotNil(VerdictEngine.standing(score: 0.55, history: history, numbers: true)?
            .rangeOfCharacter(from: .decimalDigits))
    }

    /// Weak sessions still get honest coaching and never shame, at either tier.
    func test_weakSessionsAreNeverShamed() {
        let banned = ["failed", "bad", "poor", "wasted", "you should"]
        for numbers in [true, false] {
            let text = VerdictEngine.verdict(for: restless, numbers: numbers)
            let all = (text.headline + " " + text.sentence).lowercased()
            for word in banned { XCTAssertFalse(all.contains(word), "verdict says '\(word)'") }
        }
    }
}
