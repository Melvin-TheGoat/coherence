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

    /// The answer rides on the same event, and cannot overwrite the three
    /// properties every funnel reads.
    func test_onboardingStepCarriesItsAnswer() {
        let answer: [String: Any] = ["onboarding_frequency": "mostWeeks", "step": "spoofed"]
        let props = Analytics.Event.onboardingStep(id: "baseline", answer: answer).properties
        XCTAssertEqual(props["onboarding_frequency"] as? String, "mostWeeks")
        XCTAssertEqual(props["step"] as? String, "baseline")
    }

    /// Run over every real onboarding screen with every question answered:
    /// only the eight on the approved list send anything. A new screen that
    /// starts sending an answer has to be added to the list on purpose.
    func test_onlyTheApprovedOnboardingScreensSendAnswers() {
        var a = OnboardingAnswers()
        a.motivations = [.sharperFocus]
        a.obstacles = [.noTime]
        a.stress = 0.9
        a.stressLevel = 4
        a.mindWandering = 0.8
        a.role = .student
        a.quietTime = .morning
        a.habitHistory = .firstTry
        a.ageBracket = "18 to 24"
        a.currentFrequency = .never
        let approved: Set = ["motivation", "obstacles", "role", "quietTime", "habitHistory",
                             "age", "baseline", "mindProfile"]
        for step in OnboardingView.Step.allCases {
            let id = String(describing: step)
            let sends = !OnboardingAnswerReport.properties(forStep: id, answers: a).isEmpty
            XCTAssertEqual(sends, approved.contains(id), "`\(id)` answer reporting is off the list")
        }
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

    // MARK: The 1.4 friends screens

    /// Meditating together, pictures and invite codes send what was tapped
    /// and nothing about who: no handle, no name, no code, no day.
    func test_friendsScreensSendChoicesNeverPeople() {
        typealias E = Analytics.Event
        let cases: [(E, String, [String])] = [
            (.friendsOpened(source: "home", news: true), "friends_opened", ["source", "news"]),
            (.goalStartOpened(source: "friend_page"), "goal_start_opened", ["source"]),
            (.goalInvited(target: 4), "goal_invited", ["target"]),
            (.goalInviteAnswered(accepted: false), "goal_invite_answered", ["answer"]),
            (.goalEnded(wasRunning: true), "goal_ended", ["kind"]),
            (.goalOpened(state: "invite_to_me"), "goal_opened", ["state"]),
            (.nudgeSent(kind: "high_five"), "nudge_sent", ["kind"]),
            (.goalMeditateTapped, "goal_meditate_tapped", []),
            (.pictureChosen(source: "preset", placement: "prompt", preset: "otto"), "picture_chosen",
             ["source", "placement", "preset"]),
            (.pictureChosen(source: "camera", placement: "profile", preset: nil), "picture_chosen",
             ["source", "placement"]),
            (.picturePromptShown, "picture_prompt_shown", []),
            (.picturePromptAnswered(answer: "tomorrow"), "picture_prompt_answered", ["answer"]),
            (.inviteOpened(source: "requests"), "invite_opened", ["source"]),
            (.inviteCodeSent, "invite_code_sent", []),
            (.inviteCodeLookedUp(outcome: "found", source: "onboarding"), "invite_code_looked_up",
             ["outcome", "source"]),
        ]
        for (event, name, keys) in cases {
            XCTAssertEqual(event.name, name)
            XCTAssertEqual(Set(event.properties.keys), Set(keys), name)
        }
        XCTAssertEqual(E.friendsOpened(source: "push", news: true).properties["news"] as? Bool, true)
        XCTAssertEqual(E.goalInvited(target: 4).properties["target"] as? Int, 4)
        XCTAssertEqual(E.goalEnded(wasRunning: false).properties["kind"] as? String, "invite_cancelled")
        XCTAssertEqual(E.goalInviteAnswered(accepted: true).properties["answer"] as? String, "yes")
    }

    /// How many goals a session counted for goes as a band, never who.
    func test_rewardCarriesHowManyGoalsAsABand() {
        XCTAssertEqual(Analytics.Event.rewardViewed(stageUp: false).properties["goals"] as? String, "0")
        XCTAssertEqual(Analytics.Event.rewardViewed(stageUp: false, goals: 2).properties["goals"] as? String, "2")
        XCTAssertEqual(Analytics.Event.rewardViewed(stageUp: false, goals: 9).properties["goals"] as? String, "3plus")
    }

    /// An invite code lookup reports how it went, never the code.
    func test_inviteLookupOutcomes() {
        XCTAssertEqual(CommunityModel.lookupOutcome(.failure(.inviteCodeUnknown)), "unknown")
        XCTAssertEqual(CommunityModel.lookupOutcome(.failure(.inviteCodeIsYours)), "yours")
        XCTAssertEqual(CommunityModel.lookupOutcome(.failure(.blocked)), "blocked")
        XCTAssertEqual(CommunityModel.lookupOutcome(.failure(.unavailable)), "offline")
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
