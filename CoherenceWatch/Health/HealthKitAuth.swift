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

    /// Types we READ: live heart rate, HRV, and workouts.
    private static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKObjectType.workoutType(),
        ]
    }

    /// Types we SHARE (write): the workout we record during a session.
    private static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    /// Requests authorization. Returns `true` if HealthKit is available and the
    /// prompt completed without error. The user's per-type grant/deny choices are
    /// private to HealthKit and deliberately not surfaced here.
    @discardableResult
    static func authorize() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    /// Whether recent heart-rate data is readable — a **fast-path hint, not a
    /// gate.**
    ///
    /// **HealthKit will not tell us whether a read was granted.**
    /// `authorizationStatus(for:)` reports *share* status only, and a denied
    /// read returns an empty result rather than an error, deliberately, so an
    /// app can't learn what a user declined.
    ///
    /// So this can only ever be a hint: `true` proves we can read, but `false`
    /// proves nothing — it's equally "permission denied", "watch not worn
    /// today", or "asked before authorization finished". **It must never block a
    /// session on its own.** An earlier version did exactly that and refused to
    /// start sessions for a user whose permissions were fully granted. The real
    /// gate is live HR arriving once the workout runs; see
    /// `WatchSessionManager`'s heart-rate watchdog.
    static func hasRecentHeartRateData() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let hrType = HKQuantityType(.heartRate)
        // A week, not a day: someone who left the Watch off the charger
        // overnight still has readable history, and a narrow window turned that
        // into a false "no permission".
        let since = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: hrType, predicate: predicate, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                cont.resume(returning: !(samples ?? []).isEmpty)
            }
            store.execute(q)
        }
    }
}
