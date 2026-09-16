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
    enum Event {
        // Onboarding
        case onboardingStep(id: String)
        case onboardingCompleted
        /// Reopened onboarding on the screen they left (`OnboardingResume`).
        case onboardingResumed(id: String)
        case watchGate(outcome: String)          // "hasWatch" | "waitlist" | "notYet" | "declined"

        // Core loop
        case sessionStarted(source: String, sound: String)   // source: "phone" | "watch"
        case sessionCompleted(durationBand: String, streakBand: String)
        /// A session the Watch ended but did not score: "too_short" (under the
        /// minimum, an accidental Begin/End, not a failure) or "unreadable".
        case sessionDiscarded(reason: String, durationBand: String)
        /// The user removed a session from their history. Name only.
        case sessionDeleted
        case sessionStartFailed(reason: String)
        case resultViewed
        case resultMissing                        // a session ended with no stats: the failure metric
        case ratingPrompted                       // Apple's rating sheet was requested (it decides whether to show)

        // Monetization
        case paywallViewed(placement: String)
        case paywallDismissed
        case trialStarted
        case purchase(plan: String)
        case restore
        case entitlementLost
        /// Settled for free 808. `afterRung` is how far down the ladder they
        /// got first, so we learn whether the downsells do anything at all.
        case freeTierEntered(afterRung: String)
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

        // Engagement
        case shareOpened
        case guideOpened
        case reminderEnabled
        case notificationOpened
        case awardUnlocked(id: String)
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
        case postCreated(photo: Bool)
        case reactionGiven
        case userBlocked
        case contentReported(kind: String)   // "post" | "profile"
        case inviteRewarded                  // a brought friend sat; the grant landed
        case profileCreated(photo: Bool)
        case friendsIntroShown               // the one-time prompt for pre-Friends users

        var name: String {
            switch self {
            case .onboardingStep: "onboarding_step"
            case .onboardingCompleted: "onboarding_completed"
            case .onboardingResumed: "onboarding_resumed"
            case .watchGate: "watch_gate"
            case .sessionStarted: "session_started"
            case .sessionCompleted: "session_completed"
            case .sessionDiscarded: "session_discarded"
            case .sessionDeleted: "session_deleted"
            case .sessionStartFailed: "session_start_failed"
            case .resultViewed: "result_viewed"
            case .resultMissing: "result_missing"
            case .ratingPrompted: "rating_prompted"
            case .paywallViewed: "paywall_viewed"
            case .paywallDismissed: "paywall_dismissed"
            case .trialStarted: "trial_started"
            case .purchase: "purchase"
            case .restore: "restore"
            case .entitlementLost: "entitlement_lost"
            case .freeTierEntered: "free_tier_entered"
            case .lockedTapped: "locked_tapped"
            case .skinLockedTapped: "skin_locked_tapped"
            case .shareOpened: "share_opened"
            case .guideOpened: "guide_opened"
            case .reminderEnabled: "reminder_enabled"
            case .notificationOpened: "notification_opened"
            case .awardUnlocked: "award_unlocked"
            case .accountDeleted: "account_deleted"
            case .ottoOpened: "otto_opened"
            case .ottoAsked: "otto_asked"
            case .friendsOpened: "friends_opened"
            case .usernameClaimed: "username_claimed"
            case .friendRequestSent: "friend_request_sent"
            case .friendAccepted: "friend_accepted"
            case .inviteShared: "invite_shared"
            case .postCreated: "post_created"
            case .reactionGiven: "reaction_given"
            case .userBlocked: "user_blocked"
            case .contentReported: "content_reported"
            case .inviteRewarded: "invite_rewarded"
            case .profileCreated: "profile_created"
            case .friendsIntroShown: "friends_intro_shown"
            }
        }

        var properties: [String: String] {
            switch self {
            // `step` is the routing id (what the code calls the screen);
            // `screen` is the numbered human name a dashboard can be read by.
            // Both ship, so old funnels keep working and new ones read plainly.
            case .onboardingStep(let id): ["step": id, "screen": Analytics.onboardingScreenName(for: id)]
            case .onboardingResumed(let id): ["step": id, "screen": Analytics.onboardingScreenName(for: id)]
            case .watchGate(let outcome): ["outcome": outcome]
            case .sessionStarted(let source, let sound): ["source": source, "sound": sound]
            case .sessionCompleted(let d, let s): ["duration": d, "streak": s]
            case .sessionDiscarded(let reason, let d): ["reason": reason, "duration": d]
            case .sessionStartFailed(let reason): ["reason": reason]
            case .paywallViewed(let placement): ["placement": placement]
            case .purchase(let plan): ["plan": plan]
            case .awardUnlocked(let id): ["id": id]
            case .freeTierEntered(let rung): ["after_rung": rung]
            case .lockedTapped(let signal): ["signal": signal]
            case .skinLockedTapped(let skin): ["skin": skin]
            case .postCreated(let photo): ["photo": photo ? "yes" : "no"]
            case .contentReported(let kind): ["kind": kind]
            case .profileCreated(let photo): ["photo": photo ? "yes" : "no"]
            default: [:]
            }
        }
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
        // Element-interaction autocapture is ON by default and slipped a
        // "Rageclick" with a SwiftUI view-hierarchy string into the live
        // feed. The policy promises named behavioral events only; every
        // capture path that invents its own events stays off.
        config.captureElementInteractions = false
        PostHogSDK.shared.setup(config)
        applyTeamDevice()
        sink = { event in
            PostHogSDK.shared.capture(event.name, properties: event.properties)
        }
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
    /// showed `relief` and `proofYourWay`. Letters mark branch screens a
    /// persona may never see, so a funnel over the numbered ones is one every
    /// user walks. `AnalyticsScreenNamesTests` fails the build if a Step case
    /// is added without a name here.
    static func onboardingScreenName(for id: String) -> String {
        onboardingScreenNames[id] ?? "?? \(id)"
    }

    private static let onboardingScreenNames: [String: String] = [
        "relief":            "01 Relief: you're not bad at meditation",
        "breath":            "02 One breath before we start",
        "baseline":          "03 How often do you meditate?",
        "motivation":        "04 What are you hoping for?",
        "stress":            "05 How stressed lately?",
        "aloneWithThoughts": "06a Alone with your thoughts? (not regulars)",
        "doingNothing":      "06b How long doing nothing? (cut 1.0.2)",
        "restarts":          "07a What made you stop? (restarters)",
        "intendedFor":       "07b How long meaning to start? (newcomers)",
        "bodyCuriosity":     "08a Wonder what your body is doing? (not newcomers)",
        "bodyProof":         "08b How do you know it worked? (cut 1.0.2)",
        "bodyTracking":      "09 What do you already track?",
        "hardware":          "10 The hardware you'd otherwise need (off the path since 1.0.2)",
        "blindSpot":         "11 What can't you tell about your practice? (regulars)",
        "watchGate":         "12 Do you have an Apple Watch?",
        "watchSetup":        "12a 808 goes on your Watch (has Watch)",
        "waitlist":          "12b No-Watch waitlist",
        "anchor":            "13 When will you actually meditate? (cut 1.0.2)",
        "you":               "14 What should we call you?",
        "referral":          "02b How did you find us?",   // first question since 1.0.2; was 15
        "calculating":       "16 Calculating your plan",
        "result":            "17 Here's what you told us",
        "cost":              "17b The cost (not routed to)",
        "wall":              "31b The wall: you'd be in company (before the paywall since 1.0.2)",
        "proofBody":         "19 Proof: the body is visible (cut 1.0.2)",
        "sampleStart":       "20 Sample session: start",
        "sampleBuild":       "21 Sample session: the score builds",
        "proofYourWay":      "22 Proof: your way (cut 1.0.2)",
        "commitment":        "23 Make it a promise",
        "permission":        "24 One nudge at your time (notifications)",
        "week":              "25 Your first week (cut 1.0.2)",
        "rating":            "26 Does this sound like it'd work? (cut 1.0.2)",
        "health":            "27 Health data consent",
        "tourHome":          "28 Tour: this is home",
        "watchConnect":      "29 Tour: put your Watch on",
        "breathe":           "30 Tour: two-minute demo (cut 1.0.2)",
        "sessionResults":    "31 Tour: demo results (cut 1.0.2)",
        "paywall":           "32 Paywall (after the first session since 1.0.2)",
        "signIn":            "33 Sign in with Apple",
        "profile":           "34 Create your profile (Friends builds)",
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
