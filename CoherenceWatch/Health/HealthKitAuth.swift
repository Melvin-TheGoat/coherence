import Foundation
import HealthKit

/// HealthKit authorization for the Watch. All HealthKit code lives in the Watch
/// target — the iOS target only calls `startWatchApp` (Phase 4) and reads no
/// biometric data.
///
/// Minimal scope for the motion-based model: heart-rate READ (the deceleration
/// signal) + workout SHARE (to run the `.mindAndBody` session that keeps the app
/// active and streams HR). No HRV / heartbeat-series — those were for the dropped
/// coherence path.
enum HealthKitAuth {

    /// The single store instance the Watch uses for auth and workouts.
    static let store = HKHealthStore()

    /// Types we READ: live heart rate and workouts.
    private static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
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

    /// Whether we can actually read heart rate.
    ///
    /// **HealthKit will not tell us this.** `authorizationStatus(for:)` reports
    /// *share* status only — read grants are hidden on purpose so an app can't
    /// learn what a user declined. A denied read query doesn't error either; it
    /// just returns nothing.
    ///
    /// So we probe: ask for the single most recent heart-rate sample from the
    /// last day. An Apple Watch that's being worn records HR constantly, so a
    /// sample coming back proves the grant. Nothing coming back means either a
    /// denied read or a watch that hasn't been worn — both are cases where a
    /// session can't produce the HR evidence, so both should stop the session
    /// with the same explanation.
    static func canReadHeartRate() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let hrType = HKQuantityType(.heartRate)
        let since = Date().addingTimeInterval(-24 * 60 * 60)
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
