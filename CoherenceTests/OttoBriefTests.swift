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

    // MARK: The person's numbers

    /// The table reads the stored measurements back, on the phone, and marks
    /// which session the chat was opened from.
    func test_tableReadsTheSessionsNumbersBack() {
        let focus = row(daysAgo: 0)
        let table = OttoBrief.table([focus, row(daysAgo: 1, score: 0.48)], focus: focus, now: now)
        for piece in ["(in focus)", "10 min", "score 62", "heart 74 to 66 bpm, avg 69",
                      "stillness 0.84", "doorway 5.8/min held 2:10", "body scan", "sound Rain", "rated 7/10",
                      "score 48"] {
            XCTAssertTrue(table.contains(piece), "missing '\(piece)' in\n\(table)")
        }
    }

    /// Absences are named so the model repeats a sentence instead of
    /// filling a gap.
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
