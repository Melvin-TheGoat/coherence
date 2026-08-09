import XCTest
@testable import Coherence

/// The branch tests assert which questions get *asked*. These assert what the
/// app says *back*, which is where the personalization actually broke: three
/// payoff screens read answers the user was never asked, hit nil, and printed
/// a fallback written for somebody else.
///
/// The rule every case here enforces: **a screen may only speak from an answer
/// the persona was actually given.**
final class PersonaCopyTests: XCTestCase {

    private func answers(_ frequency: CurrentFrequency,
                         configure: (inout OnboardingAnswers) -> Void = { _ in })
    -> OnboardingAnswers {
        var a = OnboardingAnswers()
        a.currentFrequency = frequency
        a.motivations = [.lessStressed]
        a.anchor = .wake
        configure(&a)
        return a
    }

    // MARK: - The regular meditator

    /// THE BUG. A regular is asked neither `restarts` nor `intendedFor`, so
    /// both were nil and the profile fell through to "Building the habit" for
    /// somebody who meditates almost daily.
    func test_regularIsNeverToldTheyAreBuildingTheHabit() {
        for frequency in [CurrentFrequency.mostWeeks, .almostDaily] {
            let a = answers(frequency) { $0.blindSpot = .improving }
            XCTAssertTrue(a.alreadyPracticing, "\(frequency) not recognised as practicing")
            let p = PracticeProfile(from: a)
            XCTAssertEqual(p.pattern, "Already practicing. Now it gets measured",
                           "\(frequency) was profiled by a restart count it never gave")
        }
    }

    /// The regular's one unique question used to be collected and dropped: the
    /// profile printed `primaryCause` (never asked) or a hardcoded string.
    func test_regularsBlindSpotAnswerIsActuallyUsed() {
        for spot in BlindSpot.allCases {
            let a = answers(.almostDaily) { $0.blindSpot = spot }
            XCTAssertEqual(PracticeProfile(from: a).blindSpot, spot.label,
                           "\(spot) was collected and then ignored")

            let concerns = a.namedConcerns
            XCTAssertEqual(concerns.count, 1)
            XCTAssertEqual(concerns.first?.quote, spot.label)
            XCTAssertEqual(concerns.first?.answer, spot.answer)
        }
    }

    /// Every blind spot needs a distinct reply, for the same reason
    /// `DropoutCause.answer` does: they render as a list with no quote above
    /// them, so a duplicate prints the same row twice.
    func test_blindSpotAnswersAreDistinctAndConcrete() {
        let all = BlindSpot.allCases.map(\.answer)
        XCTAssertEqual(Set(all).count, all.count, "two blind spots share one answer")
        for answer in all {
            XCTAssertFalse(answer.isEmpty)
            XCTAssertFalse(answer.contains("—"), "em dash in user-facing copy")
            // We measure motion and heart rate. Never a brain state.
            for banned in ["theta", "brainwave", "subconscious", "alpha"] {
                XCTAssertFalse(answer.lowercased().contains(banned),
                               "'\(answer)' claims something we can't measure")
            }
        }
    }

    // MARK: - The newcomer

    /// Someone who has never meditated has no dropout cause and no blind spot.
    /// `HowScreen` used to fall back to `[.couldntTell]` and print it in
    /// quotation marks under a "You said" header.
    func test_newcomerIsNeverQuotedOnSomethingTheyDidNotSay() {
        let a = answers(.never) { $0.intendedFor = .months }
        XCTAssertEqual(a.persona, .newcomer)
        XCTAssertTrue(a.namedConcerns.isEmpty,
                      "quoted a newcomer on a question they were never asked")
        XCTAssertEqual(a.unnamedCauses.count, DropoutCause.allCases.count,
                       "a newcomer named no cause, so every answer is still to be shown")
    }

    func test_newcomerIsNotProfiledAsARestarter() {
        let p = PracticeProfile(from: answers(.never))
        XCTAssertEqual(p.pattern, "Starting fresh")
        XCTAssertEqual(p.blindSpot, "Whether it's working, once you start",
                       "asserted a blind spot about a practice they haven't begun")
    }

    // MARK: - The restarter

    /// The persona the consistency copy was written for still gets it.
    func test_restarterKeepsTheirOwnWords() {
        for frequency in [CurrentFrequency.triedNeverStuck, .fewTimesMonth] {
            let a = answers(frequency) {
                $0.restarts = .few
                $0.causes = [.forgot, .gotBoring]
            }
            XCTAssertFalse(a.alreadyPracticing, "\(frequency) misread as practicing")

            let p = PracticeProfile(from: a)
            XCTAssertEqual(p.pattern, "Started and stopped a few times")
            XCTAssertEqual(p.blindSpot, a.primaryCause?.label)

            // Both causes are quoted, in enum order, and neither is invented.
            let quotes = a.namedConcerns.map(\.quote)
            XCTAssertEqual(quotes, [DropoutCause.forgot.label, DropoutCause.gotBoring.label])
            XCTAssertEqual(a.unnamedCauses.count, DropoutCause.allCases.count - 2)
        }
    }

    /// The escape hatches still work: someone who ticks "it already sticks"
    /// gets the practicing copy even though their baseline says restarter.
    func test_escapeHatchesStillReadAsPracticing() {
        XCTAssertTrue(answers(.triedNeverStuck) { $0.restarts = .sticks }.alreadyPracticing)
        XCTAssertTrue(answers(.never) { $0.intendedFor = .alreadyPractice }.alreadyPracticing)
    }

    // MARK: - Across every persona

    /// Nothing a screen prints may be a quote the user did not produce, and
    /// the profile's four cards must always be filled.
    func test_noPersonaGetsAnEmptyOrInventedProfile() {
        for frequency in CurrentFrequency.allCases {
            let a = answers(frequency)
            let p = PracticeProfile(from: a)
            for (label, value) in [("chasing", p.chasing), ("pattern", p.pattern),
                                   ("anchor", p.anchorLine), ("blind spot", p.blindSpot)] {
                XCTAssertFalse(value.isEmpty, "\(frequency): \(label) card is blank")
                XCTAssertFalse(value.contains("—"), "\(frequency): em dash in \(label)")
            }
            // Every quote must trace to an answer that exists.
            for concern in a.namedConcerns {
                let fromCause = DropoutCause.allCases.contains { $0.label == concern.quote && a.causes.contains($0) }
                let fromSpot = a.blindSpot?.label == concern.quote
                XCTAssertTrue(fromCause || fromSpot,
                              "\(frequency) quoted \u{201C}\(concern.quote)\u{201D} from nowhere")
            }
        }
    }

    /// A named concern and the unnamed list must never print the same answer
    /// twice on one screen.
    func test_namedAndUnnamedNeverOverlap() {
        let a = answers(.fewTimesMonth) { $0.causes = [.noTime] }
        let named = Set(a.namedConcerns.map(\.answer))
        let unnamed = Set(a.unnamedCauses.map(\.answer))
        XCTAssertTrue(named.isDisjoint(with: unnamed), "an answer is rendered twice")
    }
}
