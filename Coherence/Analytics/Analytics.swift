import Foundation
import os
import PostHog

/// The app's single analytics doorway. Every tracked moment routes through
/// here, and here decides where it goes.
///
/// **LIVE since 2026-08-17: Release builds ship named events to PostHog**
/// (US Cloud, publishable client key below, autocapture and replay off).
/// DEBUG builds never touch the network: `start()` returns before SDK setup,
/// so local runs print to the console sink and stay out of the beta's
/// dashboards. The privacy manifest declares Product Interaction; the App
/// Privacy labels in App Store Connect must say the same at submission.
///
/// Rules, decided with Aziz (2026-08-17) — hold them:
/// - **Behavioral events only. Never a biometric.** No scores, no heart rate,
///   no breathing values, not even banded. HR arrives via HealthKit and
///   guideline 5.1.3 bans disclosing HealthKit-derived data to third parties;
///   scores inherit that. If engine-tuning analytics are ever wanted, that is
///   a first-party endpoint with explicit consent, not an event here.
/// - **No free text.** Nothing a user typed.
/// - **No identity.** Anonymous install-scoped ID only, assigned by the
///   provider at launch; nothing here names the user.
enum Analytics {

    /// Every event the app emits. One enum so the full surface is reviewable
    /// in one place; adding a case is a deliberate act, not a string typo.
    ///
    /// Rebuilt for 1.1 (2026-09-28). Three more rules on top of the ones
    /// above, each a promise the privacy policy now makes:
    /// - **Nothing Block or Screen Time learns** (apps, shield taps, passes,
    ///   skipped windows, Otto's ask). Apple's Family Controls terms forbid
    ///   it leaving the phone. The only Block-adjacent event is
    ///   `paywall_viewed` with placement "block".
    /// - **No onboarding answers.** Which screen was left, never what was
    ///   picked on it.
    /// - **No award that is a threshold on the score** (`Award.Group.depth`):
    ///   "reached 90" is a banded score by another name.
    enum Event {
        // Onboarding
        /// A screen was LEFT. Pass-through hops never send it.
        case onboardingStep(id: String)
        case onboardingCompleted
        /// Reopened onboarding on the screen they left (`OnboardingResume`).
        case onboardingResumed(id: String)
        case signIn(outcome: String)              // "signed_in" | "skipped"
        case reminderPermission(outcome: String)  // "allowed" | "denied" | "skipped"
        case healthPermission(outcome: String)    // "allowed" | "declined"

        // Core loop
        case sessionStarted(source: String, sound: String)   // source: "phone" | "watch" | "phone_watch"
        /// A sit done without the app, recorded by hand. Nothing about it.
        case sessionLogged
        /// `measured` is whether the Watch's readings were saved with it:
        /// false on a "phone_watch" or "watch" session is the failure signal
        /// (the Watch was asked and nothing came back). Never what they read.
        case sessionCompleted(source: String, measured: Bool, durationBand: String, streakBand: String)
        /// A Watch-measured sit carried on as a phone sit:
        /// "no_ack" | "launch_failed" | "ended_before_start".
        case watchFallback(reason: String)
        /// A session the Watch ended but did not score: "too_short" (under the
        /// minimum, an accidental Begin/End, not a failure), "unreadable", or
        /// "left_app" (a phone sit voided for leaving 808 too long).
        case sessionDiscarded(reason: String, durationBand: String)
        /// Left 808 mid phone sit; the "come back" notice is armed.
        case sessionLeftApp
        /// Came back inside the grace period and the sit carried on.
        case sessionReturned
        /// The user removed a session from their history. Name only.
        case sessionDeleted
        case sessionStartFailed(reason: String)
        /// The after-session reward screen. `stageUp` is whether Otto moved
        /// to a brighter stage, which is practice-derived, never measured.
        case rewardViewed(stageUp: Bool)
        /// Otto's glow stage changed with a landed session
        /// (`OttoAura.Stage` names). Derived from session dates only.
        case glowStageChanged(from: String, to: String)
        case resultViewed
        case resultMissing                        // a measured session with no stats on this phone
        /// Apple's rating sheet was requested (it decides whether to show):
        /// "onboarding" | "results".
        case ratingPrompted(placement: String)

        // Monetization
        case paywallViewed(placement: String)
        /// Closed without buying: swiped away, or moved past while plans
        /// could not load.
        case paywallDismissed(placement: String)
        case planSelected(plan: String, placement: String)
        case purchaseStarted(plan: String, placement: String)
        case purchase(plan: String, placement: String)
        /// "cancelled" | "pending" | "failed"
        case purchaseFailed(plan: String, placement: String, reason: String)
        case trialStarted(plan: String)
        /// The "No, I don't want to pay" ladder. `rung` is
        /// `DownsellRung.analyticsName`: "trial" | "half_month".
        case offerViewed(rung: String)
        case offerAccepted(rung: String)
        case offerDeclined(rung: String)
        /// source: "paywall" | "settings"; outcome: "restored" | "nothing" | "failed".
        case restore(source: String, outcome: String)
        case entitlementLost
        /// Tapped a locked curve, tile or trend. The single most useful signal
        /// we have for which piece of evidence actually sells.
        ///
        /// **Carries the signal's NAME, never its value.** Heart rate arrives
        /// via HealthKit and 5.1.3 bans third-party disclosure; a banded score
        /// inherits the same problem. "heart" is a screen region, not a
        /// biometric.
        case lockedTapped(signal: String)
        /// Tapped a locked share-card skin. Decides whether cosmetics are
        /// worth developing into a real line.
        case skinLockedTapped(skin: String)

        // Otto's hats, bought with minutes meditated.
        case hatBought(id: String)
        case hatWorn(id: String)                  // a hat id, or "none" when taken off

        // Apple Watch
        /// The "measure with Apple Watch" switch: source "ready" | "settings".
        case watchSwitch(on: Bool, source: String)
        case watchSetupOpened(source: String)     // "ready" | "settings"
        /// The first time a Watch ever answered 808 on this install.
        case watchConnected

        // Engagement
        case shareOpened
        case guideOpened
        case reminderEnabled
        /// A tapped notification: "reminder" | "session_end" | "come_back".
        /// Never Block's "Otto wants a word".
        case notificationOpened(kind: String)
        case awardUnlocked(id: String)
        case signedOut
        case accountDeleted
        /// Otto, the on-device data interpreter. Two names and nothing else:
        /// the chat holds heart rates and scores in its prompt, so no
        /// question, reply or number may ride along (5.1.3 and the no-text
        /// rule above).
        case ottoOpened
        case ottoAsked

        // Friends (COMMUNITY.md). Counts only; never a handle, a caption or a
        // score.
        case friendsOpened
        case usernameClaimed
        case friendRequestSent
        case friendAccepted
        case inviteShared
        case userBlocked
        case contentReported(kind: String)   // "profile" (posts are gone)
        case inviteRewarded                  // a brought friend sat; the grant landed
        case profileCreated(photo: Bool)
        case friendsIntroShown               // the one-time prompt for pre-Friends users

        var name: String {
            switch self {
            case .onboardingStep: "onboarding_step"
            case .onboardingCompleted: "onboarding_completed"
            case .onboardingResumed: "onboarding_resumed"
            case .signIn: "sign_in"
            case .reminderPermission: "reminder_permission"
            case .healthPermission: "health_permission"
            case .sessionStarted: "session_started"
            case .sessionLogged: "session_logged"
            case .sessionCompleted: "session_completed"
            case .watchFallback: "watch_fallback"
            case .sessionDiscarded: "session_discarded"
            case .sessionLeftApp: "session_left_app"
            case .sessionReturned: "session_returned"
            case .sessionDeleted: "session_deleted"
            case .sessionStartFailed: "session_start_failed"
            case .rewardViewed: "reward_viewed"
            case .glowStageChanged: "glow_stage_changed"
            case .resultViewed: "result_viewed"
            case .resultMissing: "result_missing"
            case .ratingPrompted: "rating_prompted"
            case .paywallViewed: "paywall_viewed"
            case .paywallDismissed: "paywall_dismissed"
            case .planSelected: "plan_selected"
            case .purchaseStarted: "purchase_started"
            case .purchase: "purchase"
            case .purchaseFailed: "purchase_failed"
            case .trialStarted: "trial_started"
            case .offerViewed: "offer_viewed"
            case .offerAccepted: "offer_accepted"
            case .offerDeclined: "offer_declined"
            case .restore: "restore"
            case .entitlementLost: "entitlement_lost"
            case .lockedTapped: "locked_tapped"
            case .skinLockedTapped: "skin_locked_tapped"
            case .hatBought: "hat_bought"
            case .hatWorn: "hat_worn"
            case .watchSwitch: "watch_switch"
            case .watchSetupOpened: "watch_setup_opened"
            case .watchConnected: "watch_connected"
            case .shareOpened: "share_opened"
            case .guideOpened: "guide_opened"
            case .reminderEnabled: "reminder_enabled"
            case .notificationOpened: "notification_opened"
            case .awardUnlocked: "award_unlocked"
            case .signedOut: "signed_out"
            case .accountDeleted: "account_deleted"
            case .ottoOpened: "otto_opened"
            case .ottoAsked: "otto_asked"
            case .friendsOpened: "friends_opened"
            case .usernameClaimed: "username_claimed"
            case .friendRequestSent: "friend_request_sent"
            case .friendAccepted: "friend_accepted"
            case .inviteShared: "invite_shared"
            case .userBlocked: "user_blocked"
            case .contentReported: "content_reported"
            case .inviteRewarded: "invite_rewarded"
            case .profileCreated: "profile_created"
            case .friendsIntroShown: "friends_intro_shown"
            }
        }

        /// Strings, plus real booleans where a property is a yes or no, so
        /// PostHog types them as booleans. The two older yes/no properties
        /// (`photo`) keep their "yes"/"no" strings so old data still lines up.
        /// `duration` and `streak` keep their pre-1.1 keys for the same reason.
        var properties: [String: Any] {
            switch self {
            // `step` is the routing id (what the code calls the screen);
            // `screen` is the numbered human name a dashboard can be read by.
            // Both ship, so old funnels keep working and new ones read plainly.
            case .onboardingStep(let id):
                ["step": id, "screen": Analytics.onboardingScreenName(for: id), "flow": Analytics.appFlow]
            case .onboardingResumed(let id): ["step": id, "screen": Analytics.onboardingScreenName(for: id)]
            case .signIn(let outcome), .reminderPermission(let outcome), .healthPermission(let outcome):
                ["outcome": outcome]
            case .sessionStarted(let source, let sound): ["source": source, "sound": sound]
            case .sessionCompleted(let source, let measured, let d, let s):
                ["source": source, "measured": measured, "duration": d, "streak": s]
            case .watchFallback(let reason): ["reason": reason]
            case .sessionDiscarded(let reason, let d): ["reason": reason, "duration": d]
            case .sessionStartFailed(let reason): ["reason": reason]
            case .rewardViewed(let stageUp): ["stage_up": stageUp]
            case .glowStageChanged(let from, let to): ["from": from, "to": to]
            case .ratingPrompted(let placement): ["placement": placement]
            case .paywallViewed(let placement), .paywallDismissed(let placement): ["placement": placement]
            case .planSelected(let plan, let placement), .purchaseStarted(let plan, let placement),
                 .purchase(let plan, let placement):
                ["plan": plan, "placement": placement]
            case .purchaseFailed(let plan, let placement, let reason):
                ["plan": plan, "placement": placement, "reason": reason]
            case .trialStarted(let plan): ["plan": plan]
            case .offerViewed(let rung), .offerAccepted(let rung), .offerDeclined(let rung): ["rung": rung]
            case .restore(let source, let outcome): ["source": source, "outcome": outcome]
            case .lockedTapped(let signal): ["signal": signal]
            case .skinLockedTapped(let skin): ["skin": skin]
            case .hatBought(let id), .hatWorn(let id): ["hat_id": id]
            case .watchSwitch(let on, let source): ["on": on, "source": source]
            case .watchSetupOpened(let source): ["source": source]
            case .notificationOpened(let kind): ["kind": kind]
            case .awardUnlocked(let id): ["id": id]
            case .contentReported(let kind): ["kind": kind]
            case .profileCreated(let photo): ["photo": photo ? "yes" : "no"]
            default: [:]
            }
        }
    }

    /// Which onboarding the person went through, on every step and as a
    /// person property, so funnels can be split by flow as it keeps changing.
    static let appFlow = "1.1"

    /// The award event, or nil for an award that must never be sent: the
    /// `.depth` group is a threshold on the score (score50/75/90), and a
    /// score inherits HealthKit's 5.1.3 disclosure ban.
    static func awardUnlocked(_ award: Award) -> Event? {
        award.group == .depth ? nil : .awardUnlocked(id: award.id)
    }

    /// Which of 808's own notifications was tapped, or nil for anything
    /// else. Block's "Otto wants a word" is deliberately nil: Screen Time's
    /// terms keep everything Block does on the phone.
    static func notificationKind(identifier: String, userInfo: [AnyHashable: Any]) -> String? {
        if userInfo["block"] != nil { return nil }
        if userInfo[SessionEndNotice.userInfoKey] != nil { return "session_end" }
        if userInfo[LeftAppNotice.userInfoKey] != nil { return "come_back" }
        if identifier == NotificationScheduler.reminderID { return "reminder" }
        return nil
    }

    /// The PostHog project API key. A PUBLISHABLE client key, not a secret,
    /// so committing it is fine (it can only write events, never read them).
    /// Empty = analytics fully off: no SDK setup, no network, events go to
    /// the debug console only. That emptiness is the launch switch.
    private static let postHogKey = "phc_BUkC4ZWkwcp2L3XPjZAo94CP43bUDLMgDtaNM5BqML3s"
    private static let postHogHost = "https://us.i.posthog.com"

    /// Call once at app start. A no-op while the key is empty.
    static func start() {
        #if DEBUG
        // Dev and simulator launches stay out of the production project: the
        // dashboards exist to read the beta, and every local run was writing
        // into them. Events still print to the console sink below.
        return
        #else
        guard !postHogKey.isEmpty else { return }
        let config = PostHogConfig(apiKey: postHogKey, host: postHogHost)
        // Manual events only. Autocapture would hoover screen names and taps
        // we never reviewed against the no-biometrics/no-text rules; every
        // event this app sends is a named case in `Event`, on purpose.
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = true   // app_opened powers retention
        config.sessionReplay = false
        // Every capture path that invents its own events stays off: the
        // policy promises named behavioral events only (Melvin, 2026-09-29).
        // Element interactions are off by default in this SDK (3.69.6), set
        // anyway so an update cannot switch them on.
        config.captureElementInteractions = false
        // Rage clicks are a SEPARATE integration, ON by default and not
        // governed by `captureElementInteractions`. It is what sent a
        // `$rageclick` with touch coordinates and a SwiftUI view-hierarchy
        // string into the live feed; turning element interactions off never
        // touched it.
        config.rageClickConfig.enabled = false
        // Surveys are on by default: a remote survey could be switched on
        // from PostHog's dashboard and shown inside 808. Nothing we have not
        // reviewed gets to draw on screen.
        config.surveys = false
        // Push capture is on by default and swizzles the app delegate: the
        // subscription integration would hand PostHog the APNs token that
        // CloudKit's sync registers for, and the opened integration would
        // report taps on remote notifications. 808 uses neither.
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        // No feature flags are read anywhere in 808, so there is nothing to
        // preload; the request would only carry the anonymous ID and person
        // properties to PostHog on every launch for no reason.
        config.preloadFeatureFlags = false
        // No crash reports either. Off is the SDK's default, and PostHog's
        // own dashboard can only narrow it further, never switch it on; set
        // here so the App Privacy label ("no diagnostics") rests on this
        // line rather than on a default that could change in an update.
        config.errorTrackingConfig.autoCapture = false
        PostHogSDK.shared.setup(config)
        applyTeamDevice()
        sink = { event in
            PostHogSDK.shared.capture(event.name, properties: event.properties)
        }
        personSink = { props in
            PostHogSDK.shared.setPersonProperties(userPropertiesToSet: props)
        }
        started = true
        // Anything set before the SDK existed (WatchLink reads the pairing
        // at launch, before this runs) goes now.
        personSink(person)
        #endif
    }

    /// Whether `start()` set the SDK up. Release only; DEBUG never does.
    private static var started = false

    // MARK: - Person properties

    /// Facts about this install, set on the ANONYMOUS PostHog person so a
    /// funnel can be split by them. Never an identify, never a name. Approved
    /// with the product owner (2026-09-28), and the list is closed:
    /// - `is_subscriber` (Bool) and `plan` (a `SubscriptionPlan` raw value,
    ///   or "none"), from the store's entitlement.
    /// - `has_paired_watch` (Bool), from WatchConnectivity.
    /// - `app_flow` ("1.1").
    /// Nothing measured, nothing Block knows, no onboarding answer.
    private static var person: [String: Any] = ["app_flow": appFlow]

    static func setPersonProperties(_ props: [String: Any]) {
        person.merge(props) { _, new in new }
        personSink(props)
    }

    /// Where person properties go. Swapped for PostHog by `start()`.
    private static var personSink: ([String: Any]) -> Void = { props in
        #if DEBUG
        Logger(subsystem: "com.lockout.meditate808", category: "analytics")
            .debug("person \(props, privacy: .public)")
        #endif
    }

    /// A new anonymous person: after sign-out and account deletion, so the
    /// next person on this phone is not stitched to the last one. The
    /// device facts (`person`) and the team flag are true of the phone, not
    /// the person, so they are set again straight away.
    static func reset() {
        #if !DEBUG
        guard started else { return }
        PostHogSDK.shared.reset()
        applyTeamDevice()
        personSink(person)
        #endif
    }

    // MARK: - Team devices

    /// Founders' phones send events like anyone else's, and every reinstall
    /// mints a new anonymous id, so neither an id list nor a postal code held
    /// up as an "internal user" rule (both were tried in PostHog on
    /// 2026-09-12; the postal one would have hidden friends). Instead the
    /// phone flags itself: seven taps on the version line in Settings
    /// registers `team_device = true` as a super property on every event,
    /// and the project's internal-user filter is `team_device ≠ true`.
    /// Off by default, so no real user is ever flagged by accident.
    private static let teamDeviceKey = "analytics.teamDevice.v1"

    static var isTeamDevice: Bool {
        UserDefaults.standard.bool(forKey: teamDeviceKey)
    }

    static func setTeamDevice(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: teamDeviceKey)
        applyTeamDevice()
    }

    private static func applyTeamDevice() {
        #if !DEBUG
        if isTeamDevice {
            PostHogSDK.shared.register(["team_device": true])
        } else {
            PostHogSDK.shared.unregister("team_device")
        }
        #endif
    }

    // MARK: - Onboarding screen names

    /// The numbered human name for each onboarding screen, keyed by the
    /// routing id (`String(describing: OnboardingView.Step)`). Read by the
    /// PostHog funnels, which nobody but the author could follow while they
    /// showed `relief` and `proofYourWay`.
    ///
    /// **Renumbered for 1.1 (2026-09-28) in today's order**, walked from
    /// `OnboardingView`'s routing. Two digits are screens every person sees,
    /// in the order they see them; a letter marks a screen only some phones
    /// show (a paired Watch, a Block or Friends build), so a funnel over the
    /// plain numbers is one everyone walks. Cut screens start "zz" so they
    /// sort last and read as gone; they keep a name because an old resume
    /// record can still land on one. The KEYS never change, so funnels built
    /// on `step` survive every renumbering. `AnalyticsScreenNamesTests` fails
    /// the build if a Step case is added without a name here.
    static func onboardingScreenName(for id: String) -> String {
        onboardingScreenNames[id] ?? "?? \(id)"
    }

    private static let onboardingScreenNames: [String: String] = [
        "relief":            "01 Welcome, Otto waves",
        "breath":            "02 One breath (starts by itself)",
        "breathing":         "03 One breath done (in 4, hold 2, out 4)",
        "meetOtto":          "04 Meet your meditating partner: Otto",
        "ottoGrows":         "05 The more you meditate, the brighter he gets",
        "seeForYourself":    "06 See for yourself (drag Otto's glow)",
        "clutter":           "07 Your mind is just cluttered",
        "questionCount":     "08 Let's personalize 808 for you",
        "motivation":        "09 What's your goal with meditation?",
        "obstacles":         "10 What usually gets in the way?",
        "stress":            "11 How stressed have you been lately?",
        "wandering":         "12 How much of your day is your mind elsewhere?",
        "role":              "13 Which one sounds most like you?",
        "quietTime":         "14 When could you fit in a few quiet minutes?",
        "habitHistory":      "15 Tried to make meditation a habit before?",
        "age":               "16 How old are you?",
        "didYouKnow":        "17 Did you know? (four sourced facts)",
        "baseline":          "18 How often do you meditate right now?",
        "buildingPlan":      "19 Tailoring 808 to you",
        "mindProfile":       "20 Your mind profile",
        "lifeNumber":        "21 N years with your mind elsewhere (seasons clip)",
        "lifePause":         "22 What would you do with N years?",
        "lifeDots":          "23 This is your life (the dots)",
        "goodNews":          "24 The good news (a quarter back)",
        "lifeMoments":       "25 N more years of family, fun, this world",
        "attentionHacked":   "26 Your attention has been hacked",
        "whyItWorks":        "27 How 808 makes meditation stick",
        "research":          "28 808 is built on research",
        "socialProof":       "29 Made for people like you (rating ask)",
        "thisWeek":          "30 In 1 week, 808 will help you",
        "ascend":            "31 Ready to take control? (hold to ascend)",
        "paywall":           "32 Paywall",
        "permission":        "33 One nudge at your time (notifications)",
        "health":            "33a Health consent (Watch paired)",
        "blockApps":         "33b Which apps should Otto hold? (Block builds)",
        "blockSchedule":     "33c When should Otto hold them? (Block builds)",
        "signIn":            "34 Sign in with Apple",
        "profile":           "34a Create your profile (Friends builds)",
        "tourHome":          "35 Tour: this is home",

        // Cut. Never sent any more (`go` skips pass-through hops); named so
        // an old resume record, or an old event in a breakdown, still reads.
        "recovery":          "zz How quickly do you settle back down? (cut)",
        "whatsWaiting":      "zz Here's what's waiting (cut)",
        "blockIntro":        "zz Otto can hold your apps (cut)",
        "auraDemo":          "zz Drag to see Otto brighten (cut)",
        "aloneWithThoughts": "zz Alone with your thoughts? (cut)",
        "doingNothing":      "zz How long doing nothing? (cut)",
        "referral":          "zz How did you find us? (cut)",
        "restarts":          "zz What made you stop? (cut)",
        "intendedFor":       "zz How long meaning to start? (cut)",
        "bodyCuriosity":     "zz Wonder what your body is doing? (cut)",
        "bodyProof":         "zz How do you know it worked? (cut)",
        "bodyTracking":      "zz What do you already track? (cut)",
        "hardware":          "zz The hardware you'd otherwise need (cut)",
        "blindSpot":         "zz What can't you tell about your practice? (cut)",
        "watchGate":         "zz Do you have an Apple Watch? (cut)",
        "watchSetup":        "zz 808 goes on your Watch (cut)",
        "waitlist":          "zz No-Watch waitlist (cut)",
        "anchor":            "zz When will you actually meditate? (cut)",
        "you":               "zz What should we call you? (cut)",
        "calculating":       "zz Calculating your plan (cut)",
        "result":            "zz Here's what you told us (cut)",
        "cost":              "zz The cost (cut)",
        "wall":              "zz The wall: you'd be in company (cut)",
        "proofBody":         "zz Proof: the body is visible (cut)",
        "sampleStart":       "zz Sample session: start (cut)",
        "sampleBuild":       "zz Sample session: the score builds (cut)",
        "proofYourWay":      "zz Proof: your way (cut)",
        "commitment":        "zz Make it a promise (cut)",
        "week":              "zz Your first week (cut)",
        "rating":            "zz Does this sound like it'd work? (cut)",
        "watchConnect":      "zz Tour: put your Watch on (cut)",
        "breathe":           "zz Tour: two-minute demo (cut)",
        "sessionResults":    "zz Tour: demo results (cut)",
    ]

    /// Where events go. `start()` swaps this to PostHog when a key is set;
    /// nothing else in the app knows or cares.
    static var sink: (Event) -> Void = { event in
        #if DEBUG
        Logger(subsystem: "com.lockout.meditate808", category: "analytics")
            .debug("track \(event.name, privacy: .public) \(event.properties, privacy: .public)")
        #endif
    }

    static func track(_ event: Event) { sink(event) }

    /// Coarse bands, so a property can never reconstruct a precise value.
    static func durationBand(seconds: Int) -> String {
        switch seconds {
        case ..<30: "under30s"
        case ..<180: "under3m"
        case ..<420: "3to7m"
        case ..<720: "7to12m"
        case ..<1500: "12to25m"
        default: "over25m"
        }
    }

    static func streakBand(days: Int) -> String {
        switch days {
        case ..<2: "1"
        case ..<4: "2to3"
        case ..<8: "4to7"
        case ..<31: "8to30"
        default: "over30"
        }
    }
}
