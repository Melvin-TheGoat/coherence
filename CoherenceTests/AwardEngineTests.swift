import XCTest
@testable import Coherence

/// Awards are derived, so these tests are the whole feature. Anything that
/// passes here is true on a device, because nothing else decides.
final class AwardEngineTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func day(_ offsetFromToday: Int, score: Double? = nil, minutes: Int = 10)
        -> AwardEngine.SessionFact {
        let d = cal.date(byAdding: .day, value: offsetFromToday,
                         to: cal.startOfDay(for: Date()))!
        return .init(startedAt: d.addingTimeInterval(9 * 3600),
                     durationSec: minutes * 60, overallScore: score)
    }

    private func earned(_ facts: [AwardEngine.SessionFact],
                        created: Date? = Date()) -> [String: AwardEngine.Earned] {
        Dictionary(uniqueKeysWithValues: AwardEngine
            .evaluate(sessions: facts, accountCreatedAt: created, calendar: cal)
            .map { ($0.award.id, $0) })
    }

    // MARK: The rule that matters most

    /// THE load-bearing behaviour. Melvin's call: you keep the award. Taking it
    /// back punishes exactly the person we are trying to bring back.
    func test_brokenStreakKeepsTheAward() {
        // Ten straight days, then a two week gap, then one session today.
        var facts = (1...10).map { day(-40 + $0) }
        facts.append(day(0))

        let a = earned(facts)
        XCTAssertTrue(a["streak10"]!.isEarned, "a broken streak took the award back")
        XCTAssertTrue(a["streak5"]!.isEarned)
        XCTAssertFalse(a["streak25"]!.isEarned)
    }

    /// The date shown is when it was earned, not when it was noticed. Someone
    /// who ran forty days straight earned the ten-day award on day ten.
    func test_earnedDateIsTheSessionThatEarnedIt() {
        let facts = (0..<40).map { day(-39 + $0) }
        let a = earned(facts)

        let tenth = cal.startOfDay(for: facts[9].startedAt)
        XCTAssertEqual(a["streak10"].flatMap { $0.earnedAt.map(cal.startOfDay(for:)) },
                       tenth, "streak award dated to the end of the run, not day ten")
    }

    // MARK: Backfill

    /// Backfill is not a feature, it is a consequence: derived rules read the
    /// history that already exists.
    func test_existingHistoryEarnsItsAwardsWithNoMigration() {
        let facts = (0..<30).map { day(-29 + $0, score: 0.8, minutes: 25) }
        let a = earned(facts)

        for id in ["firstStep", "firstSession", "streak3", "streak5", "streak10",
                   "streak25", "score50", "score75", "min20"] {
            XCTAssertTrue(a[id]!.isEarned, "\(id) was not backfilled from history")
        }
        XCTAssertFalse(a["score90"]!.isEarned)
        XCTAssertFalse(a["min30"]!.isEarned)
        XCTAssertFalse(a["streak50"]!.isEarned)
    }

    // MARK: Thresholds

    func test_scoreAwardsNeedASessionThatReachedThem() {
        XCTAssertFalse(earned([day(0, score: 0.49)])["score50"]!.isEarned)
        XCTAssertTrue(earned([day(0, score: 0.50)])["score50"]!.isEarned)
        // One good session is enough; it does not have to be the latest.
        let mixed = earned([day(-2, score: 0.91), day(-1, score: 0.2), day(0, score: 0.3)])
        XCTAssertTrue(mixed["score90"]!.isEarned)
    }

    func test_durationAwardsAreOneSitNotATotal() {
        // Four ten-minute sits are forty minutes and earn nothing.
        let short = earned((0..<4).map { day(-$0, minutes: 10) })
        XCTAssertFalse(short["min20"]!.isEarned, "summed minutes earned a single-sit award")
        XCTAssertTrue(earned([day(0, minutes: 20)])["min20"]!.isEarned)
    }

    // MARK: Days, not sessions

    func test_severalSessionsInOneDayAreOneDay() {
        let facts = (0..<6).map { _ in day(0) }
        XCTAssertFalse(earned(facts)["streak3"]!.isEarned,
                       "six sessions in one day counted as a streak")
    }

    // MARK: Empty and progress

    func test_freshAccountHasOnlyTheSignupAward() {
        let a = earned([], created: Date())
        XCTAssertTrue(a["firstStep"]!.isEarned)
        XCTAssertFalse(a["firstSession"]!.isEarned)
        XCTAssertEqual(a.values.filter(\.isEarned).count, 1)
    }

    func test_noAccountEarnsNothing() {
        let a = earned([], created: nil)
        XCTAssertTrue(a.values.allSatisfy { !$0.isEarned })
    }

    /// Progress must describe the live streak, not the best one ever, or the
    /// "next up" bar tells someone they are 40/50 when they sat once yesterday.
    func test_progressTracksTheCurrentStreakNotTheBestOne() {
        var facts = (1...20).map { day(-60 + $0) }
        facts.append(day(0))

        let a = earned(facts)
        XCTAssertEqual(a["streak25"]!.progressText, "1/25")
        XCTAssertEqual(a["streak25"]!.progress, 1.0 / 25, accuracy: 0.0001)
        XCTAssertTrue(a["streak10"]!.isEarned, "but the earned one is still earned")
    }

    /// An earned award reports no progress text: a finished thing showing
    /// "10/10" invites reading it as unfinished.
    func test_earnedAwardsCarryNoProgressText() {
        let a = earned((0..<5).map { day(-$0, score: 0.9, minutes: 40) })
        for item in a.values where item.isEarned {
            XCTAssertNil(item.progressText, "\(item.award.id) still showed progress")
            XCTAssertEqual(item.progress, 1)
        }
    }

    // MARK: The inbox

    /// The bug this was caught by, on the simulator: sessions load
    /// asynchronously, so the first look can happen against an empty history
    /// and every real award then queues up as breaking news.
    func test_historyThatArrivesLateIsNotAnnouncedAsNew() {
        AwardsInbox.resetForPreview()

        // First look: the store has not finished loading, so nothing is earned
        // except the signup award.
        let empty = AwardEngine.evaluate(sessions: [], accountCreatedAt: Date(), calendar: cal)
        AwardsInbox.seedIfNeeded(with: empty)
        XCTAssertTrue(AwardsInbox.pending(from: empty).isEmpty)

        // A moment later thirty days of history land.
        let full = AwardEngine.evaluate(
            sessions: (0..<30).map { day(-29 + $0, score: 0.8, minutes: 25) },
            accountCreatedAt: Date(), calendar: cal)
        XCTAssertTrue(AwardsInbox.pending(from: full).isEmpty,
                      "backfilled history announced itself as new awards")
        AwardsInbox.resetForPreview()
    }

    /// But something genuinely earned after the watermark must still announce,
    /// or the fix above silences the feature.
    func test_anAwardEarnedNowIsStillAnnounced() {
        AwardsInbox.resetForPreview()
        let before = AwardEngine.evaluate(sessions: [], accountCreatedAt: Date(), calendar: cal)
        AwardsInbox.seedIfNeeded(with: before)

        // A session that starts now, after the watermark.
        let fresh = AwardEngine.evaluate(
            sessions: [.init(startedAt: Date().addingTimeInterval(1),
                             durationSec: 1500, overallScore: 0.8)],
            accountCreatedAt: Date(), calendar: cal)
        let pending = AwardsInbox.pending(from: fresh)
        XCTAssertTrue(pending.contains { $0.award.id == "firstSession" },
                      "a genuinely new award was swallowed")

        // And only once.
        pending.forEach { AwardsInbox.markAnnounced($0.award.id) }
        XCTAssertTrue(AwardsInbox.pending(from: fresh).isEmpty)
        AwardsInbox.resetForPreview()
    }

    // MARK: Catalog

    func test_catalogIsWellFormed() {
        var seen = Set<String>()
        for award in Award.all {
            XCTAssertTrue(seen.insert(award.id).inserted, "duplicate \(award.id)")
            XCTAssertFalse(award.title.isEmpty)
            XCTAssertFalse(award.meaning.isEmpty)
        }
        // Every award must be reachable by some rule, or it is decoration that
        // can never be earned.
        let reachable = earned((0..<400).map { day(-399 + $0, score: 0.95, minutes: 65) })
        for award in Award.all {
            XCTAssertTrue(reachable[award.id]!.isEarned,
                          "\(award.id) cannot be earned by any history")
        }
    }

    /// No award may claim a health outcome or a brain state.
    func test_awardCopyRespectsTheScienceLine() {
        let banned = ["theta", "brainwave", "cure", "heals", "proven", "clinically",
                      "alpha state", "beta state"]
        for award in Award.all {
            let text = (award.meaning + " " + award.blurb + " " + award.title).lowercased()
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(award.id) says '\(word)'")
            }
        }
    }
}
