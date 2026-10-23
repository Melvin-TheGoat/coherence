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
    /// - **Onboarding answers: a closed list only** (reversed 2026-10-13,
    ///   Melvin, for the customer profile; it was "never what was picked").
    ///   `OnboardingAnswerReport` holds the list: goals, obstacles, role,
    ///   age range, frequency, tried before, quiet time and the mind profile
    ///   type. Never the stress answer, the mind-wandering slider, or text.
    /// - **No award that is a threshold on the score** (`Award.Group.depth`):
    ///   "reached 90" is a banded score by another name.
    enum Event {
        // Onboarding
        /// A screen was LEFT. Pass-through hops never send it. `answer` is
        /// what the screen collected, from `OnboardingAnswerReport` only.
        case onboardingStep(id: String, answer: [String: Any] = [:])
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
        /// `goals` is how many shared weekly goals the session counted for
        /// ("Counted for Ana and Daniel"), as a band, never who.
        case rewardViewed(stageUp: Bool, goals: Int = 0)
        /// Otto's glow stage changed with a landed session
        /// (`OttoAura.Stage` names). Derived from session dates only.
        case glowStageChanged(from: String, to: String)
        case resultViewed
        case resultMissing                        // a measured session with no stats on this phone
        /// Apple's rating sheet was requested (it decides whether to show),
        /// on Home after a session: "firstSession" | "weekStreak" | "later"
        /// (`ReviewPrompt.Moment`). Before 1.3: "onboarding" | "results".
        case ratingPrompted(placement: String)
        /// "Rate 808 on the App Store" in Settings opened the review page.
        case rateLinkOpened

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
        /// The home screen widget (1.2): tapped into 808, and added or
        /// removed as WidgetCenter reports on each return to the app. Size is
        /// "small" | "medium". Nothing about Otto's glow or the streak.
        case widgetOpened(size: String)
        case widgetAdded(size: String)
        case widgetRemoved(size: String)
        /// A tapped notification: "reminder" | "session_end" | "come_back".
        /// Never Block's "Otto wants a word".
        /// `topic` is a reminder's topic (`ReminderTopic`), never Block's.
        case notificationOpened(kind: String, topic: String? = nil)
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
        /// `source`: "home" (the circle on Home), "push" (a goal or nudge
        /// notification), "tab". `news`: the circle carried an unread badge.
        case friendsOpened(source: String, news: Bool)
        case usernameClaimed
        case friendRequestSent
        case friendAccepted
        case inviteShared
        case inviteCodeRedeemed              // joined Friends with someone's invite code (2026-10-18)
        case userBlocked
        case contentReported(kind: String)   // "profile" (posts are gone)
        case inviteRewarded                  // a brought friend sat; the grant landed
        case profileCreated(photo: Bool)
        case friendsIntroShown               // the one-time prompt for pre-Friends users

        // Meditating together (1.4, 2026-10-14): shared weekly goals with a
        // friend. Never who, never a day, never minutes: the goal's target
        // is a choice of 1 to 7, the rest are what was tapped.
        /// The goal flow opened. `source`: "friends_row" (the first-goal row
        /// on Friends), "together_add" (the Add beside "Meditating
        /// together"), "friend_page" (a friend's page).
        case goalStartOpened(source: String)
        /// The invite went out. `target` is days a week each, 1 to 7.
        case goalInvited(target: Int)
        /// An invite to me was answered.
        case goalInviteAnswered(accepted: Bool)
        /// Ended by me: a running goal, or my own invite taken back.
        case goalEnded(wasRunning: Bool)
        /// A goal's page. `state`: "active", "waiting_for_them",
        /// "invite_to_me".
        case goalOpened(state: String)
        /// `kind`: "nudge" or "high_five".
        case nudgeSent(kind: String)
        /// "Meditate now" on a goal's page (meditate first, then nudge).
        case goalMeditateTapped

        // Profile pictures (1.4, 2026-10-19)
        /// `source`: "camera", "library", "preset". `preset` is which of the
        /// 21 (`AvatarPreset.id`), only for a preset. `placement`:
        /// "profile" (create or edit) or "prompt" (the ask from Friends).
        case pictureChosen(source: String, placement: String, preset: String?)
        /// The one-time "Pick a picture" ask from Friends was shown.
        case picturePromptShown
        /// `answer`: "picked", "tomorrow", "never", "dismissed".
        case picturePromptAnswered(answer: String)

        // Invite codes (1.4, 2026-10-18). Never the code itself.
        /// The invite sheet opened. `source`: "header", "no_friends",
        /// "requests".
        case inviteOpened(source: String)
        /// The second share, the code as its own text, went out.
        case inviteCodeSent
        /// A code was typed or pasted and looked up. `outcome`: "found",
        /// "unknown", "yours", "blocked", "offline". `source`: "onboarding",
        /// "search".
        case inviteCodeLookedUp(outcome: String, source: String)

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
            case .rateLinkOpened: "rate_link_opened"
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
            case .widgetOpened: "widget_opened"
            case .widgetAdded: "widget_added"
            case .widgetRemoved: "widget_removed"
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
            case .inviteCodeRedeemed: "invite_code_redeemed"
            case .userBlocked: "user_blocked"
            case .contentReported: "content_reported"
            case .inviteRewarded: "invite_rewarded"
            case .profileCreated: "profile_created"
            case .friendsIntroShown: "friends_intro_shown"
            case .goalStartOpened: "goal_start_opened"
            case .goalInvited: "goal_invited"
            case .goalInviteAnswered: "goal_invite_answered"
            case .goalEnded: "goal_ended"
            case .goalOpened: "goal_opened"
            case .nudgeSent: "nudge_sent"
            case .goalMeditateTapped: "goal_meditate_tapped"
            case .pictureChosen: "picture_chosen"
            case .picturePromptShown: "picture_prompt_shown"
            case .picturePromptAnswered: "picture_prompt_answered"
            case .inviteOpened: "invite_opened"
            case .inviteCodeSent: "invite_code_sent"
            case .inviteCodeLookedUp: "invite_code_looked_up"
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
            case .onboardingStep(let id, let answer):
                (["step": id, "screen": Analytics.onboardingScreenName(for: id),
                  "flow": Analytics.appFlow] as [String: Any])
                    .merging(answer) { kept, _ in kept }
            case .onboardingResumed(let id): ["step": id, "screen": Analytics.onboardingScreenName(for: id)]
            case .signIn(let outcome), .reminderPermission(let outcome), .healthPermission(let outcome):
                ["outcome": outcome]
            case .sessionStarted(let source, let sound): ["source": source, "sound": sound]
            case .sessionCompleted(let source, let measured, let d, let s):
                ["source": source, "measured": measured, "duration": d, "streak": s]
            case .watchFallback(let reason): ["reason": reason]
            case .sessionDiscarded(let reason, let d): ["reason": reason, "duration": d]
            case .sessionStartFailed(let reason): ["reason": reason]
            case .rewardViewed(let stageUp, let goals): ["stage_up": stageUp, "goals": Analytics.countBand(goals)]
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
            case .notificationOpened(let kind, let topic):
                topic.map { ["kind": kind, "topic": $0] } ?? ["kind": kind]
            case .widgetOpened(let size), .widgetAdded(let size), .widgetRemoved(let size): ["size": size]
            case .awardUnlocked(let id): ["id": id]
            case .contentReported(let kind): ["kind": kind]
            case .profileCreated(let photo): ["photo": photo ? "yes" : "no"]
            case .friendsOpened(let source, let news): ["source": source, "news": news]
            case .goalStartOpened(let source): ["source": source]
            case .goalInvited(let target): ["target": target]
            case .goalInviteAnswered(let accepted): ["answer": accepted ? "yes" : "no"]
            case .goalEnded(let wasRunning): ["kind": wasRunning ? "ended" : "invite_cancelled"]
            case .goalOpened(let state): ["state": state]
            case .nudgeSent(let kind): ["kind": kind]
            case .pictureChosen(let source, let placement, let preset):
                preset.map { ["source": source, "placement": placement, "preset": $0] }
                    ?? ["source": source, "placement": placement]
            case .picturePromptAnswered(let answer): ["answer": answer]
            case .inviteOpened(let source): ["source": source]
            case .inviteCodeLookedUp(let outcome, let source): ["outcome": outcome, "source": source]
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
        if identifier == NotificationScheduler.reminderID
            || identifier.hasPrefix(ReminderScheduler.idPrefix) { return "reminder" }
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
        guard !postHogKey.isEmpty, !started else { return }
        // Turned off in Settings: the SDK is never set up, so this launch
        // makes no PostHog request of any kind, not even its remote config
        // (App Review pass, 2026-09-29, guideline 5.1.1(ii)).
        guard !isOptedOut else { return }
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
        // The SDK keeps its own opt-out flag on disk, and a person who turned
        // analytics off in an earlier launch and back on in this one could
        // still have it set. Ours is the only switch; make PostHog agree.
        PostHogSDK.shared.optIn()
        applyTeamDevice()
        sink = { event in
            PostHogSDK.shared.capture(event.name, properties: event.properties)
        }
        personSink = { props in
            PostHogSDK.shared.setPersonProperties(userPropertiesToSet: props)
        }
        started = true
        applyHasWidget()
        // Anything set before the SDK existed (WatchLink reads the pairing
        // at launch, before this runs) goes now.
        personSink(person)
        #endif
    }

    /// Whether `start()` set the SDK up. Release only; DEBUG never does.
    private static var started = false

    // MARK: - Opt-out

    /// The "Share usage analytics" switch in Settings (App Review pass,
    /// 2026-09-29, guideline 5.1.1(ii): a person must be able to stop data
    /// collection that the app's function does not need). Stored as OPTED
    /// OUT so an absent key reads as the default, on, which is what every
    /// install before this switch was doing.
    ///
    /// Off means nothing leaves the phone: `track` and person properties
    /// return before any sink, the SDK is told `optOut()` at once, and on
    /// the next launch `start()` does not set PostHog up at all.
    private static let optedOutKey = "analytics.optedOut.v1"

    static var isOptedOut: Bool {
        UserDefaults.standard.bool(forKey: optedOutKey)
    }

    static var isSharing: Bool { !isOptedOut }

    static func setSharing(_ on: Bool) {
        UserDefaults.standard.set(!on, forKey: optedOutKey)
        #if !DEBUG
        if on {
            if started {
                PostHogSDK.shared.optIn()
                applyTeamDevice()
                personSink(person)
            } else {
                // Off at launch, so the SDK was never set up; set it up now.
                start()
            }
        } else if started {
            // Stops capture and the lifecycle integration straight away, and
            // persists in the SDK's own storage as a second lock.
            PostHogSDK.shared.optOut()
        }
        #endif
    }

    // MARK: - Person properties

    /// Facts about this install, set on the ANONYMOUS PostHog person so a
    /// funnel can be split by them. Never an identify, never a name. Approved
    /// with the product owner (2026-09-28), and the list is closed:
    /// - `is_subscriber` (Bool) and `plan` (a `SubscriptionPlan` raw value,
    ///   or "none"), from the store's entitlement.
    /// - `has_paired_watch` (Bool), from WatchConnectivity.
    /// - `app_flow` ("1.1").
    /// Nothing measured, nothing Block knows. Onboarding answers are person
    /// properties too since 2026-10-13, but through `setOnboardingAnswer`,
    /// never through this dictionary: they belong to the person who gave
    /// them, and `reset` re-sends this dictionary to the NEXT person.
    private static var person: [String: Any] = ["app_flow": appFlow]

    static func setPersonProperties(_ props: [String: Any]) {
        person.merge(props) { _, new in new }
        // Kept locally so switching analytics back on sends the current
        // facts, but never sent while the switch is off.
        guard !isOptedOut else { return }
        personSink(props)
    }

    /// One onboarding answer (`OnboardingAnswerReport`) on the anonymous
    /// person, so funnels and retention can be split by it. Not kept in
    /// `person`: after a sign-out the next person on this phone has not
    /// given these answers.
    static func setOnboardingAnswer(_ props: [String: Any]) {
        guard !props.isEmpty, !isOptedOut else { return }
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
        // Skipped while analytics are off: PostHog's reset reloads its
        // feature flags over the network, and off means no request at all.
        guard started, !isOptedOut else { return }
        PostHogSDK.shared.reset()
        applyTeamDevice()
        applyHasWidget()
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

    /// `has_widget` on every event, so any funnel can be split by whether an
    /// 808 widget is on the home screen (`WidgetPresence`). Stored, so a
    /// reset can put it straight back.
    private static let hasWidgetKey = "analytics.hasWidget.v1"

    static func setHasWidget(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: hasWidgetKey)
        applyHasWidget()
    }

    private static func applyHasWidget() {
        #if !DEBUG
        guard started, !isOptedOut else { return }
        PostHogSDK.shared.register(["has_widget": UserDefaults.standard.bool(forKey: hasWidgetKey)])
        #endif
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
        "clutter":           "07 Does your mind feel cluttered?",
        "questionCount":     "08 Let's personalize 808 for you",
        "motivation":        "09 What matters most to you? (one pick)",
        "obstacles":         "10 What usually gets in the way?",
        "stress":            "11 How stressed have you been lately?",
        "wandering":         "12 How much of your day is your mind elsewhere?",
        "role":              "zz Which one sounds most like you? (cut)",
        "quietTime":         "14 When could you fit in a few quiet minutes?",
        "habitHistory":      "15 Tried to make meditation a habit before?",
        "age":               "16 How old are you?",
        "didYouKnow":        "zz Did you know? (four sourced facts) (cut)",
        "baseline":          "18 How often do you meditate right now?",
        "buildingPlan":      "19 Tailoring 808 to you",
        "mindProfile":       "20 Your mind profile",
        "lifeNumber":        "21 N years with your mind elsewhere (seasons clip)",
        "lifePause":         "zz What would you do with N years? (cut)",
        "lifeDots":          "zz This is your life, the dots (cut)",
        "goodNews":          "24 The good news (a quarter back)",
        "lifeMoments":       "25 N more years of family, fun, this world",
        "attentionHacked":   "zz Your attention has been hacked (cut)",
        "neuroBrain":        "26a Your brain becomes what you do every day",
        "neuroPick":         "26b Which would change your days the most?",
        "neuroPlan":         "26c Just a few minutes a day",
        "whyItWorks":        "27 How 808 makes meditation stick",
        "research":          "zz 808 is built on research (cut)",
        "socialProof":       "29 Made for people like you (rating ask)",
        "thisWeek":          "zz In 1 week, 808 will help you (cut)",
        "ascend":            "31 Ready to take control? (hold to ascend)",
        "paywall":           "32 Paywall",
        "permission":        "33 One nudge at your time (notifications)",
        "health":            "33a Health consent (Watch paired)",
        "blockApps":         "33b Which apps should Otto hold? (Block builds)",
        "blockSchedule":     "33c When should Otto hold them? (Block builds)",
        "signIn":            "34 Sign in with Apple",
        "profile":           "34a Create your profile (Friends builds)",
        "invitedFriends":    "34b You and your friend are friends (invite code)",
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

    static func track(_ event: Event) {
        // The Settings switch is off: nothing is sent (App Review pass,
        // 2026-09-29).
        guard !isOptedOut else { return }
        sink(event)
    }

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

    /// A small count as "0", "1", "2", "3plus".
    static func countBand(_ n: Int) -> String {
        n >= 3 ? "3plus" : String(max(n, 0))
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
