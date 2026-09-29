import XCTest
@testable import Coherence

/// The onboarding funnel in PostHog is read by screen name, not by the Swift
/// case name. A screen without a name shows up as "??" in a dashboard, which
/// is how a new screen would silently become unreadable.
final class AnalyticsScreenNamesTests: XCTestCase {

    func test_everyOnboardingScreenHasAReadableName() {
        var seen = Set<String>()
        for step in OnboardingView.Step.allCases {
            let id = String(describing: step)
            let name = Analytics.onboardingScreenName(for: id)
            XCTAssertFalse(name.hasPrefix("??"), "Screen `\(id)` has no readable analytics name")
            XCTAssertTrue(seen.insert(name).inserted, "Two screens share the analytics name `\(name)`")
        }
    }

    /// Two digits (a letter for a conditional screen) for a live screen, "zz"
    /// and "(cut)" for a cut one, so a breakdown sorts in flow order and the
    /// cut ones sink to the bottom.
    func test_everyNameIsNumberedOrMarkedCut() {
        let numbered = try! NSRegularExpression(pattern: "^[0-9]{2}[a-z]? ")
        for step in OnboardingView.Step.allCases {
            let name = Analytics.onboardingScreenName(for: String(describing: step))
            let range = NSRange(name.startIndex..., in: name)
            let isNumbered = numbered.firstMatch(in: name, range: range) != nil
            let isCut = name.hasPrefix("zz ") && name.hasSuffix("(cut)")
            XCTAssertTrue(isNumbered != isCut, "`\(name)` is neither numbered nor marked cut")
        }
    }

    func test_onboardingStepCarriesTheRoutingIDTheScreenNameAndTheFlow() {
        let props = Analytics.Event.onboardingStep(id: "baseline").properties
        XCTAssertEqual(props["step"] as? String, "baseline")
        XCTAssertEqual(props["screen"] as? String, "18 How often do you meditate right now?")
        XCTAssertEqual(props["flow"] as? String, "1.1")
    }

    func test_unknownScreenIsVisiblyUnnamed() {
        XCTAssertTrue(Analytics.onboardingScreenName(for: "somethingNew").hasPrefix("??"))
    }

    // MARK: What may never be sent

    /// score50/75/90 are thresholds on the score, which inherits HealthKit's
    /// 5.1.3 disclosure ban. Every other award is sent by id.
    func test_scoreAwardsAreNeverSent() {
        let all = Coherence.Award.all
        XCTAssertFalse(all.filter { $0.group == .depth }.isEmpty)
        for award in all {
            let event = Analytics.awardUnlocked(award)
            if award.group == .depth {
                XCTAssertNil(event, "\(award.id) is a score threshold and must not be sent")
            } else {
                XCTAssertEqual(event?.properties["id"] as? String, award.id)
            }
        }
    }

    /// Block's ask comes from Screen Time and stays on the phone.
    func test_notificationKinds() {
        XCTAssertNil(Analytics.notificationKind(identifier: "block-ask", userInfo: ["block": "ask"]))
        XCTAssertEqual(Analytics.notificationKind(identifier: "session-end-x",
                                                  userInfo: [SessionEndNotice.userInfoKey: "x"]), "session_end")
        XCTAssertEqual(Analytics.notificationKind(identifier: "left-app-x",
                                                  userInfo: [LeftAppNotice.userInfoKey: "x"]), "come_back")
        XCTAssertEqual(Analytics.notificationKind(identifier: NotificationScheduler.reminderID,
                                                  userInfo: [:]), "reminder")
        XCTAssertNil(Analytics.notificationKind(identifier: "something-else", userInfo: [:]))
    }

    /// Yes/no properties go as real booleans so PostHog types them as such.
    func test_booleanPropertiesAreBooleans() {
        let completed = Analytics.Event.sessionCompleted(source: "phone_watch", measured: false,
                                                         durationBand: "3to7m", streakBand: "1").properties
        XCTAssertEqual(completed["measured"] as? Bool, false)
        XCTAssertEqual(completed["source"] as? String, "phone_watch")
        XCTAssertEqual(Analytics.Event.rewardViewed(stageUp: true).properties["stage_up"] as? Bool, true)
        XCTAssertEqual(Analytics.Event.watchSwitch(on: true, source: "ready").properties["on"] as? Bool, true)
    }

    // MARK: The plan person property

    func test_planNameRanksTheBiggestPlan() {
        XCTAssertEqual(Store.planName(owning: []), "none")
        XCTAssertEqual(Store.planName(owning: ["com.lockout.meditate808.monthly"]), "monthly")
        XCTAssertEqual(Store.planName(owning: ["com.lockout.meditate808.monthly",
                                               "com.lockout.meditate808.yearly"]), "yearly")
        XCTAssertEqual(Store.planName(owning: ["com.lockout.meditate808.yearly",
                                               "com.lockout.meditate808.lifetime"]), "lifetime")
        XCTAssertEqual(Store.planName(owning: ["com.lockout.meditate808.monthly50"]), "monthHalf")
        XCTAssertEqual(Store.planName(owning: ["com.somebody.else"]), "none")
    }
}
