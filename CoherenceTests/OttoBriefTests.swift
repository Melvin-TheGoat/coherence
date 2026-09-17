import XCTest
@testable import Coherence

/// Otto's brief is rules, and these lock the rules that matter: the prompt
/// fits the on-device window, it carries the score's actual mechanics, the
/// person's numbers reach the model (on the phone) and never the analytics,
/// medical questions get one line, and no em dash reaches the screen.
final class OttoBriefTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_789_500_000)   // mid-2026, a fixed clock

    private func row(daysAgo: Int, score: Double = 0.62) -> OttoBrief.SessionRow {
        OttoBrief.SessionRow(date: now.addingTimeInterval(-Double(daysAgo) * 86_400 - 3_600),
                             minutes: 10, overallScore: score,
                             startHR: 74, endHR: 66, meanHR: 69,
                             stillnessScore: 0.84, doorwayRate: 5.8, doorwayHeldSec: 130,
                             technique: "Body Scan", sound: "Rain", rating: 7)
    }

    // MARK: Budget

    /// The model's window is about 4,096 tokens for everything. The standing
    /// brief, ten full sessions included, stays inside the character budget.
    func test_briefWithTenFullSessionsStaysUnderBudget() {
        let rows = (0..<10).map { row(daysAgo: $0) }
        let text = OttoBrief.instructions(sessions: rows, focus: rows[0], now: now)
        XCTAssertLessThan(text.count, OttoBrief.characterBudget, "brief is \(text.count) characters")
        XCTAssertLessThan(OttoBrief.instructions(sessions: [], focus: nil, now: now).count,
                          OttoBrief.characterBudget)
    }

    func test_onlyTenSessionsAreListed() {
        let rows = (0..<15).map { row(daysAgo: $0) }
        let table = OttoBrief.table(rows, focus: nil, now: now)
        XCTAssertEqual(table.split(separator: "\n").count, OttoBrief.maxSessions)
    }

    // MARK: The score rules

    /// The mechanics Otto explains are the ones the engine uses (SCORE v5 in
    /// CLAUDE.md), not whatever the model believes a meditation score is.
    func test_briefCarriesTheScoreRules() {
        let text = OttoBrief.instructions(sessions: [], focus: nil, now: now)
        for phrase in ["heart 50%", "stillness 30%", "breath 20%",
                       "heart 60% and stillness 40%",
                       "60 seconds", "9 per minute", "first 5 minutes",
                       "50 plus 5 per minute", "8%",
                       "cannot read brainwaves, theta, HRV"] {
            XCTAssertTrue(text.contains(phrase), "missing '\(phrase)'")
        }
    }

    /// Aziz, 2026-09-16: he asked Otto why he scored a 38 and "it basically
    /// gave me the formula back". The formula was the longest, most quotable
    /// block in the prompt and it sat above his own numbers, so a small
    /// on-device model reached for it. The answer shape now comes LAST, right
    /// before the question, and demonstrates the failure it is correcting.
    func test_theAnswerShapeComesLastAndForbidsRecitingTheFormula() {
        let focus = row(daysAgo: 0)
        let text = OttoBrief.instructions(sessions: [focus], focus: focus, now: now)

        // Last, because a small model weights the freshest instruction most.
        guard let shapeAt = text.range(of: "HOW TO ANSWER")?.lowerBound,
              let rulesAt = text.range(of: "BACKGROUND ON THE 808 SCORE")?.lowerBound,
              let tableAt = text.range(of: "THIS PERSON'S SESSIONS")?.lowerBound else {
            return XCTFail("the brief is missing one of its sections")
        }
        XCTAssertTrue(shapeAt > rulesAt, "the rules must not be the freshest thing in the prompt")
        XCTAssertTrue(shapeAt > tableAt, "the answer shape belongs after the person's own numbers")

        // It must say plainly what not to do, and show it.
        XCTAssertTrue(text.contains("Never reply by listing the weights"))
        XCTAssertTrue(text.contains("why did I score a 38?"), "the worked example is the instruction")
        XCTAssertTrue(text.contains("Bad (never do this)"))
        XCTAssertTrue(text.contains("Do not recite this"))
    }

    // MARK: The person's numbers

    /// The table reads the stored measurements back, on the phone, and marks
    /// which session the chat was opened from.
    func test_tableReadsTheSessionsNumbersBack() {
        let focus = row(daysAgo: 0)
        let table = OttoBrief.table([focus, row(daysAgo: 1, score: 0.48)], focus: focus, now: now)
        for piece in ["(in focus)", "10 min", "score 62", "heart 74 to 66 bpm, avg 69",
                      "stillness 0.84", "doorway 5.8/min kept up for 2:10", "body scan", "sound Rain", "rated 7/10",
                      "score 48"] {
            XCTAssertTrue(table.contains(piece), "missing '\(piece)' in\n\(table)")
        }
    }

    /// Absences are named so the model repeats a sentence instead of
    /// filling a gap.
    /// Otto must not do arithmetic. The brief precomputes the one hypothetical
    /// it allows, a short sit's depth under the 10-minute ceiling, and the
    /// rules forbid inventing any other "would have scored".
    func test_shortSitCarriesItsTenMinuteEquivalentAndTheRuleAgainstGuessing() {
        var five = row(daysAgo: 0, score: 0.60)
        five.minutes = 5
        XCTAssertEqual(five.scoreAtTenMinutes, 80, "5 min caps at 75%, so 60 is depth 0.80")
        let text = OttoBrief.line(five, focus: true, now: now)
        XCTAssertTrue(text.contains("at 10 min the same sit would score 80"), text)

        var ten = row(daysAgo: 0, score: 0.60)
        ten.minutes = 10
        XCTAssertNil(ten.scoreAtTenMinutes, "at ten minutes there is nothing to extrapolate")
        XCTAssertFalse(OttoBrief.line(ten, focus: true, now: now).contains("would score"))

        XCTAssertTrue(OttoBrief.scoreRules.contains("NEVER do arithmetic on the score"))
    }

    // MARK: The score card

    /// Melvin's sit (2026-09-16): 5 min, heart 60 climbing to 84, stillness
    /// 0.76, no doorway. Otto told him "still for 0.76 seconds" and
    /// "60% + 40% + 0% = 100%". The card now does that arithmetic in points
    /// that add up to the score on the ring, and names every input.
    func test_scoreCardAddsUpToTheScoreAndNamesEveryInput() {
        let hr = [60.0, 66, 70, 72, 75, 78, 80, 82, 84]
        let b = Coherence.SignalEngine.breakdown(stillnessScore: 0.76, heartRateTimeseries: hr,
                                       hasDoorway: false, durationSec: 300)!
        var r = OttoBrief.SessionRow(date: now, minutes: 5, overallScore: b.score,
                                     startHR: 60, endHR: 84, meanHR: 70, stillnessScore: 0.76)
        r.breakdown = b
        let card = OttoBrief.scoreCard(r)!
        let score = r.score100!
        XCTAssertEqual(score, Int((b.score * 100).rounded()))
        // Points, scaled to the 5-minute cap of 75, sum to the score.
        let heart = Int((b.heartPoints! * 0.75).rounded())
        let still = Int((b.stillnessPoints! * 0.75).rounded())
        XCTAssertEqual(heart, 0, "a climbing heart earns nothing")
        XCTAssertEqual(still, 13, "0.76 cubed is 0.44, of 30 scaled points")
        XCTAssertTrue(abs(heart + still - score) <= 1, "\(heart) + \(still) vs \(score)")
        for piece in ["opened at 60 bpm", "closed at 84 bpm", "climbed 24 beats",
                      "0% of the sit", "Heart earned 0 of 45 points",
                      "Stillness: 0.76 on a 0 to 1 scale", "Cubed for the score it is 0.44",
                      "Stillness earned 13 of 30 points",
                      "no slow-breath doorway", "share the whole score 60/40",
                      "cap of 75", "COACHING FOR THIS SESSION", "heart (45 points left)"] {
            XCTAssertTrue(card.contains(piece), "missing '\(piece)' in\n\(card)")
        }
        XCTAssertFalse(card.contains("0.76 seconds"), "stillness is never seconds")
        // The two hypotheticals the app allows, both computed here.
        XCTAssertTrue(card.contains("With a breath doorway the same sit would score"))
        XCTAssertTrue(card.contains("At 10 min the same sit would score"))
        // The table line carries the same points, and the brief carries the card.
        XCTAssertTrue(OttoBrief.line(r, focus: true, now: now).contains("heart 0 of 45, stillness 13 of 30"))
        XCTAssertTrue(OttoBrief.instructions(sessions: [r], focus: r, now: now).contains("SCORE CARD"))
    }

    /// A settled sit with a doorway: three terms, and the biggest lever is
    /// whatever has the most points left, decided by rule so the advice is
    /// the same every time.
    func test_scoreCardWithADoorwayRanksTheLeversByRule() {
        let hr = [74.0, 72, 70, 68, 67, 66, 66, 66, 66]
        let b = Coherence.SignalEngine.breakdown(stillnessScore: 0.84, heartRateTimeseries: hr,
                                       hasDoorway: true, durationSec: 600)!
        var r = row(daysAgo: 0, score: b.score)
        r.breakdown = b
        let card = OttoBrief.scoreCard(r)!
        XCTAssertTrue(card.contains("Breath earned 20 of 20 points"), card)
        XCTAssertTrue(card.contains("full 100 was available"), card)
        XCTAssertNil(OttoBrief.scoreWithDoorway(b), "already has one")
        // 0.84 cubed = 0.59 → 18 of 30 (12 left); heart 0.6 + 0.4·8/12 = 0.87 → 43 of 50 (7 left).
        XCTAssertTrue(card.contains("COACHING FOR THIS SESSION, biggest lever first: stillness (12 points left)"), card)
        let sum = Int((b.heartPoints! + b.stillnessPoints! + b.breathPoints).rounded())
        XCTAssertTrue(abs(sum - r.score100!) <= 1)
    }

    /// The breakdown is the score: one code path, so the explanation and
    /// the ring can never disagree.
    func test_breakdownIsTheScore() {
        let hr = [70.0, 69, 68, 66, 65, 64]
        for (still, doorway, secs) in [(0.9, true, 1200), (0.5, false, 120), (0.97, false, 2400)] {
            let dw = doorway ? Coherence.SignalEngine.BreathDoorway(rate: 6, heldSec: 90, startSec: 5) : nil
            let score = Coherence.SignalEngine.score(stillnessScore: still, heartRateTimeseries: hr,
                                           breathDoorway: dw, durationSec: secs)
            let b = Coherence.SignalEngine.breakdown(stillnessScore: still, heartRateTimeseries: hr,
                                           hasDoorway: doorway, durationSec: secs)
            XCTAssertEqual(score, b?.score)
        }
        XCTAssertNil(Coherence.SignalEngine.breakdown(stillnessScore: nil, heartRateTimeseries: [], hasDoorway: false, durationSec: 60))
    }

    // MARK: The lab

    /// Not a test: writes the brief for a sit shaped like Melvin's to the
    /// path in OTTO_BRIEF_OUT (pass `TEST_RUNNER_OTTO_BRIEF_OUT=...` to
    /// xcodebuild) so `tools/otto_lab.swift` can put questions to the same
    /// on-device model on the Mac and the answers can be read without a
    /// phone. Does nothing otherwise.
    func test_dumpBriefForTheLab() throws {
        guard let out = ProcessInfo.processInfo.environment["OTTO_BRIEF_OUT"] else { return }
        let hr = [60.0, 63, 66, 68, 70, 72, 74, 75, 76, 78, 79, 80, 81, 82, 83, 84]
        let poorB = Coherence.SignalEngine.breakdown(stillnessScore: 0.76, heartRateTimeseries: hr,
                                                     hasDoorway: false, durationSec: 300)!
        var poor = OttoBrief.SessionRow(date: now, minutes: 5, overallScore: poorB.score,
                                        startHR: 60, endHR: 84, meanHR: 70, stillnessScore: 0.76,
                                        technique: "Breath", sound: "Silence", rating: 5)
        poor.breakdown = poorB
        let goodHR = [76.0, 74, 72, 70, 69, 68, 67, 66, 66, 65, 65, 65]
        let goodB = Coherence.SignalEngine.breakdown(stillnessScore: 0.91, heartRateTimeseries: goodHR,
                                                     hasDoorway: true, durationSec: 900)!
        var good = OttoBrief.SessionRow(date: now.addingTimeInterval(-86_400 * 2), minutes: 15,
                                        overallScore: goodB.score, startHR: 76, endHR: 65, meanHR: 68,
                                        stillnessScore: 0.91, doorwayRate: 5.6, doorwayHeldSec: 150,
                                        technique: "Body Scan", sound: "Rain", rating: 8)
        good.breakdown = goodB
        let text = OttoBrief.instructions(sessions: [poor, good], focus: poor, now: now)
        try text.write(toFile: out, atomically: true, encoding: .utf8)
    }

    // MARK: Saved conversations

    /// Leaving the chat keeps it: lines round-trip through the store, the
    /// tail is kept, and a session's chat dies with the session.
    func test_chatIsSavedPerSessionAndCapped() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("otto-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let key = OttoChatStore.key(for: id)
        XCTAssertNil(OttoChatStore.load(key: key, directory: dir))
        let lines = (0..<100).map { OttoChatStore.Saved.Line(fromOtto: $0 % 2 == 0, text: "line \($0)") }
        OttoChatStore.save(lines, key: key, directory: dir)
        let back = OttoChatStore.load(key: key, directory: dir)!
        XCTAssertEqual(back.lines.count, OttoChatStore.maxLines)
        XCTAssertEqual(back.lines.last?.text, "line 99")
        XCTAssertEqual(OttoChatStore.key(for: nil), "profile")
        OttoChatStore.delete(key: key, directory: dir)
        XCTAssertNil(OttoChatStore.load(key: key, directory: dir))
        OttoChatStore.save(lines, key: "profile", directory: dir)
        OttoChatStore.deleteAll(directory: dir)
        XCTAssertNil(OttoChatStore.load(key: "profile", directory: dir))
    }

    func test_unreadSignalsAreNamedNotOmitted() {
        let bare = OttoBrief.SessionRow(date: now, minutes: 5)
        let line = OttoBrief.line(bare, focus: false, now: now)
        XCTAssertTrue(line.contains("heart not read"))
        XCTAssertTrue(line.contains("stillness not read"))
        XCTAssertTrue(line.contains("no doorway"))
        XCTAssertTrue(line.contains("no score"))
    }

    func test_openingReferencesTheSessionInFocus() {
        let focus = row(daysAgo: 0)
        let opening = OttoBrief.opening(focus: focus, sessionCount: 3)
        XCTAssertTrue(opening.contains("62"), opening)
        XCTAssertTrue(opening.contains("10 minute"), opening)
        XCTAssertTrue(opening.contains("heart eased down 8 beats"), opening)
        XCTAssertEqual(OttoBrief.suggestedQuestions(focus: focus, sessionCount: 3).first, "Why did I score 62?")
    }

    func test_openingWithoutSessionsInvitesAStart() {
        XCTAssertTrue(OttoBrief.opening(focus: nil, sessionCount: 0).contains("how to start"))
        XCTAssertTrue(OttoBrief.opening(focus: nil, sessionCount: 4).contains("last 4 sessions"))
    }

    // MARK: Analytics

    /// Otto's two events carry nothing: no question, no number. The brief
    /// below holds a heart rate of 74; none of its digits can reach a
    /// property because there are no properties.
    func test_analyticsEventsCarryNothing() {
        XCTAssertEqual(Analytics.Event.ottoOpened.name, "otto_opened")
        XCTAssertEqual(Analytics.Event.ottoAsked.name, "otto_asked")
        XCTAssertTrue(Analytics.Event.ottoOpened.properties.isEmpty)
        XCTAssertTrue(Analytics.Event.ottoAsked.properties.isEmpty)
        let brief = OttoBrief.instructions(sessions: [row(daysAgo: 0)], focus: nil, now: now)
        XCTAssertTrue(brief.contains("74"))
        for event in [Analytics.Event.ottoOpened, .ottoAsked] {
            let dumped = event.name + event.properties.description
            XCTAssertNil(dumped.rangeOfCharacter(from: .decimalDigits), "a digit escaped into \(dumped)")
        }
    }

    // MARK: Medical questions

    func test_medicalQuestionsGetTheDeclineLine() {
        for q in ["Can meditation fix my arrhythmia?",
                  "Is it safe to meditate while pregnant?",
                  "Should I stop my medication?",
                  "Does this mean I have anxiety?",
                  "My chest hurts when I breathe slow, is that chest pain normal?",
                  "can you diagnose what my heart rate means"] {
            XCTAssertEqual(OttoBrief.medicalDecline(for: q), OttoBrief.declineLine, q)
        }
    }

    func test_practiceQuestionsReachTheModel() {
        for q in ["Why did I score 62?", "How do I settle faster?", "What is a breath doorway?",
                  "Should I go on a meditation retreat?", "How is my practice trending?"] {
            XCTAssertNil(OttoBrief.medicalDecline(for: q), q)
        }
    }

    // MARK: No em dashes

    func test_nothingOttoWritesCarriesAnEmDash() {
        let focus = row(daysAgo: 0)
        let texts = [OttoBrief.instructions(sessions: [focus], focus: focus, now: now),
                     OttoBrief.opening(focus: focus, sessionCount: 1),
                     OttoBrief.opening(focus: nil, sessionCount: 0),
                     OttoBrief.declineLine,
                     OttoAvailability.headline] + OttoBrief.suggestedQuestions(focus: focus, sessionCount: 1)
        for text in texts {
            XCTAssertFalse(text.contains("—"), text)
        }
        XCTAssertEqual(OttoBrief.sanitize("Heart settled — a good sign"), "Heart settled, a good sign")
        XCTAssertFalse(OttoBrief.sanitize("one—two – three").contains("—"))
    }
}
