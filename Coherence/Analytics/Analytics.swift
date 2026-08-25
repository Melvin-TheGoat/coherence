import Foundation
import os
import PostHog

/// The app's single analytics doorway. Every tracked moment routes through
/// here, and here decides where it goes.
///
/// **Today it goes nowhere.** The sink is a no-op (console in DEBUG), so this
/// file changes nothing about what the app collects or transmits: no SDK, no
/// network, no privacy-manifest change, safe in beta builds. At launch the
/// real provider (PostHog was the pick, 2026-08-17) drops in behind
/// `Analytics.sink`, and the whole event set lights up in one commit —
/// together with the privacy policy, App Privacy labels and manifest updates,
/// which MUST land in that same pass.
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
        case watchGate(outcome: String)          // "hasWatch" | "waitlist" | "declined"

        // Core loop
        case sessionStarted(source: String, sound: String)   // source: "phone" | "watch"
        case sessionCompleted(durationBand: String, streakBand: String)
        case sessionStartFailed(reason: String)
        case resultViewed
        case resultMissing                        // a session ended with no stats: the failure metric

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

        var name: String {
            switch self {
            case .onboardingStep: "onboarding_step"
            case .onboardingCompleted: "onboarding_completed"
            case .watchGate: "watch_gate"
            case .sessionStarted: "session_started"
            case .sessionCompleted: "session_completed"
            case .sessionStartFailed: "session_start_failed"
            case .resultViewed: "result_viewed"
            case .resultMissing: "result_missing"
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
            }
        }

        var properties: [String: String] {
            switch self {
            case .onboardingStep(let id): ["step": id]
            case .watchGate(let outcome): ["outcome": outcome]
            case .sessionStarted(let source, let sound): ["source": source, "sound": sound]
            case .sessionCompleted(let d, let s): ["duration": d, "streak": s]
            case .sessionStartFailed(let reason): ["reason": reason]
            case .paywallViewed(let placement): ["placement": placement]
            case .purchase(let plan): ["plan": plan]
            case .awardUnlocked(let id): ["id": id]
            case .freeTierEntered(let rung): ["after_rung": rung]
            case .lockedTapped(let signal): ["signal": signal]
            case .skinLockedTapped(let skin): ["skin": skin]
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
        sink = { event in
            PostHogSDK.shared.capture(event.name, properties: event.properties)
        }
    }

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
