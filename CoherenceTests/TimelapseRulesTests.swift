import XCTest
@testable import Coherence

/// Session timelapse (Melvin, 2026-11-16): always a timelapse, one second of
/// clip per half minute meditated, never under 6 seconds or over 30; a reel
/// that thins itself so memory stays flat; and auto-save offered once, after
/// the first manual Save.
final class TimelapseRulesTests: XCTestCase {

    // MARK: - Clip length

    func test_clipIsOneSecondPerHalfMinute() {
        XCTAssertEqual(TimelapseRule.clipSeconds(forSessionSeconds: 5 * 60), 10)
        XCTAssertEqual(TimelapseRule.clipSeconds(forSessionSeconds: 10 * 60), 20)
        XCTAssertEqual(TimelapseRule.clipSeconds(forSessionSeconds: 12 * 60), 24)
    }

    func test_clipNeverShorterThanSixSeconds() {
        XCTAssertEqual(TimelapseRule.clipSeconds(forSessionSeconds: 60), 6)
        XCTAssertEqual(TimelapseRule.clipSeconds(forSessionSeconds: 3 * 60), 6)
        XCTAssertEqual(TimelapseRule.clipSeconds(forSessionSeconds: 0), 6)
        XCTAssertEqual(TimelapseRule.clipSeconds(forSessionSeconds: .nan), 6)
    }

    func test_clipNeverLongerThanThirtySeconds() {
        XCTAssertEqual(TimelapseRule.clipSeconds(forSessionSeconds: 15 * 60), 30)
        XCTAssertEqual(TimelapseRule.clipSeconds(forSessionSeconds: 20 * 60), 30)
        XCTAssertEqual(TimelapseRule.clipSeconds(forSessionSeconds: 3 * 3600), 30)
    }

    func test_framesNeededAtThirtyFramesASecond() {
        XCTAssertEqual(TimelapseRule.framesNeeded(forSessionSeconds: 10 * 60), 600)
        XCTAssertEqual(TimelapseRule.framesNeeded(forSessionSeconds: 60 * 60), 900)
    }

    func test_speedLine() {
        XCTAssertEqual(TimelapseRule.speedLine(sessionSeconds: 20 * 60), "20 min in 30 s")
        XCTAssertEqual(TimelapseRule.speedLine(sessionSeconds: 5 * 60), "5 min in 10 s")
        XCTAssertEqual(TimelapseRule.speedLine(sessionSeconds: 65 * 60), "1 h 5 min in 30 s")
        XCTAssertEqual(TimelapseRule.makingLine(sessionSeconds: 20 * 60), "20 minutes becomes 30 seconds")
    }

    func test_noEmDashesInWhatPeopleRead() {
        for s in [TimelapseRule.speedLine(sessionSeconds: 1234), TimelapseRule.makingLine(sessionSeconds: 1234)] {
            XCTAssertFalse(s.contains("\u{2014}"), s)
        }
    }

    // MARK: - Mapping kept frames onto the clip

    func test_frameMapRepeatsFewFramesEvenly() {
        let map = TimelapseRule.frameMap(kept: 2, needed: 6)
        XCTAssertEqual(map, [0, 0, 0, 1, 1, 1])
    }

    func test_frameMapSkipsManyFramesEvenly() {
        let map = TimelapseRule.frameMap(kept: 10, needed: 5)
        XCTAssertEqual(map, [0, 2, 4, 6, 8])
    }

    func test_frameMapCoversFirstToLastAndNeverOverruns() {
        let map = TimelapseRule.frameMap(kept: 1_199, needed: 900)
        XCTAssertEqual(map.count, 900)
        XCTAssertEqual(map.first, 0)
        XCTAssertLessThan(map.last!, 1_199)
        XCTAssertEqual(map, map.sorted())
        XCTAssertEqual(TimelapseRule.frameMap(kept: 0, needed: 10), [])
    }

    // MARK: - The reel

    func test_timedSessionPicksTheExactGapAndNeverThins() {
        var plan = TimelapseReelPlan(plannedSeconds: 10 * 60)
        XCTAssertEqual(plan.interval, 1, accuracy: 0.0001)
        var t = 0.0
        while t < 600 {
            if plan.wants(at: t) { XCTAssertEqual(plan.keep(at: t), []) }
            t += 0.2
        }
        XCTAssertEqual(Double(plan.count), 600, accuracy: 2)
        XCTAssertEqual(plan.interval, 1, accuracy: 0.0001)
    }

    func test_openSessionStartsFineAndHalvesWhenFull() {
        var plan = TimelapseReelPlan(plannedSeconds: nil)
        XCTAssertEqual(plan.interval, TimelapseReelPlan.shortestInterval)
        var dropped: [Int] = []
        var t = 0.0
        while dropped.isEmpty {
            if plan.wants(at: t) { dropped = plan.keep(at: t) }
            t += 0.1
        }
        XCTAssertEqual(dropped.count, TimelapseReelPlan.capacity / 2)
        XCTAssertEqual(dropped.first, 1)
        XCTAssertTrue(dropped.allSatisfy { $0 % 2 == 1 })
        XCTAssertEqual(plan.count, TimelapseReelPlan.capacity / 2)
        XCTAssertEqual(plan.interval, TimelapseReelPlan.shortestInterval * 2, accuracy: 0.0001)
    }

    func test_reelStaysBoundedOverAThreeHourSession() {
        var plan = TimelapseReelPlan(plannedSeconds: nil)
        var t = 0.0
        while t < 3 * 3600 {
            if plan.wants(at: t) { _ = plan.keep(at: t) }
            XCTAssertLessThan(plan.count, TimelapseReelPlan.capacity)
            t += 0.25
        }
        // The kept frames still span the whole session, evenly.
        XCTAssertGreaterThan(plan.count, TimelapseReelPlan.capacity / 2 - 1)
        XCTAssertEqual(plan.times.first, 0)
        XCTAssertGreaterThan(plan.times.last ?? 0, 3 * 3600 - 2 * plan.interval)
    }

    func test_slowDownDoublesTheGap() {
        var plan = TimelapseReelPlan(plannedSeconds: 10 * 60)
        _ = plan.keep(at: 0)
        plan.slowDown()
        XCTAssertEqual(plan.interval, 2, accuracy: 0.0001)
        XCTAssertFalse(plan.wants(at: 1.5))
        XCTAssertTrue(plan.wants(at: 2))
    }

    // MARK: - Auto-save to Photos

    func test_autoSaveIsOffUntilAsked() {
        let auto = TimelapseAutoSave()
        XCTAssertFalse(auto.savesAutomatically)
        XCTAssertNil(auto.enabled)
    }

    func test_firstManualSaveOffersOnceOnly() {
        var auto = TimelapseAutoSave()
        XCTAssertTrue(auto.afterManualSave())
        XCTAssertFalse(auto.afterManualSave())
        XCTAssertFalse(auto.savesAutomatically, "an unanswered offer is not a yes")
    }

    func test_answeringYesTurnsItOn() {
        var auto = TimelapseAutoSave()
        _ = auto.afterManualSave()
        auto.answer(true)
        XCTAssertTrue(auto.savesAutomatically)
        XCTAssertFalse(auto.afterManualSave())
    }

    func test_choiceMadeInSettingsMeansNoOffer() {
        var auto = TimelapseAutoSave()
        auto.answer(false)
        XCTAssertFalse(auto.afterManualSave())
    }

    func test_autoSaveRoundTripsThroughDefaults() {
        let d = UserDefaults(suiteName: "TimelapseRulesTests-\(UUID().uuidString)")!
        XCTAssertEqual(TimelapseAutoSave.load(d), TimelapseAutoSave())
        var auto = TimelapseAutoSave.load(d)
        _ = auto.afterManualSave()
        auto.store(d)
        XCTAssertEqual(TimelapseAutoSave.load(d).offered, true)
        XCTAssertNil(TimelapseAutoSave.load(d).enabled)
        auto.answer(true)
        auto.store(d)
        XCTAssertTrue(TimelapseAutoSave.load(d).savesAutomatically)
    }

    // MARK: - Lens

    func test_lensRemembersAndOnlyTheFrontMirrors() {
        let d = UserDefaults(suiteName: "TimelapseRulesTests-\(UUID().uuidString)")!
        XCTAssertEqual(TimelapseLens.load(d), .front)
        TimelapseLens.back.store(d)
        XCTAssertEqual(TimelapseLens.load(d), .back)
        XCTAssertTrue(TimelapseLens.front.mirrored)
        XCTAssertFalse(TimelapseLens.back.mirrored)
        XCTAssertEqual(TimelapseLens.front.flipped, .back)
    }
}
