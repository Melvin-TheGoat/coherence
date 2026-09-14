import Foundation
import HealthKit

/// HealthKit authorization for the Watch. All HealthKit code lives in the Watch
/// target — the iOS target only calls `startWatchApp` (Phase 4) and reads no
/// biometric data.
///
/// Scope: heart-rate READ (the deceleration signal), **HRV SDNN READ**, and
/// workout SHARE (to run the `.mindAndBody` session that keeps the app active
/// and streams HR).
///
/// **HRV and heart coherence are not the same thing, and only one of them is
/// out of reach.** This file used to say "no HRV / heartbeat-series, those were
/// for the dropped coherence path", which conflated them and cost us a signal.
/// Coherence needs the beat-to-beat interval *series*, which a third-party
/// workout genuinely cannot get (verified on device, Phase 2, and still true).
/// `heartRateVariabilitySDNN` is a single number the Watch computes itself and
/// hands to any app with permission. It was dropped as collateral of a decision
/// about something else.
///
/// Still NOT requested: `heartbeatSeries`. That one really is unavailable to us.
enum HealthKitAuth {

    /// The single store instance the Watch uses for auth and workouts.
    static let store = HKHealthStore()

    /// Requests authorization for the shared scope (`HealthScope`, so the phone
    /// and the Watch can never ask for different things). Returns `true` if
    /// HealthKit is available and the prompt completed without error. The
    /// user's per-type grant/deny choices are private to HealthKit and
    /// deliberately not surfaced here.
    ///
    /// On a paired Watch this is now the FALLBACK, not the first ask. The
    /// system can only show the Health sheet on the iPhone, so a request made
    /// here mid-session put a prompt on a screen the user was not looking at,
    /// and thirty seconds later the heart-rate watchdog aborted the session
    /// they had just started. Onboarding asks on the phone instead.
    @discardableResult
    static func authorize() async -> Bool {
        await HealthScope.request(using: store)
    }

    // NOTE: a 7-day heart-rate history probe used to live here, uncalled.
    // Deleted 2026-08-31: the privacy policy says heart rate is read live
    // during a session only, and dead code that would break that promise on
    // its first caller is a loaded gun, not a utility.
}
